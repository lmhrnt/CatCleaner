import Foundation
import OSLog

/// Walks an entire `.app` bundle and thins every fat Mach-O inside it via
/// `ThinBinaryOperation`, preserving each binary's original code signature.
///
/// We deliberately do NOT re-sign the bundle. `lipo -thin` keeps the kept
/// architecture slice signed exactly as the developer shipped it, so a
/// normally-laid-out bundle stays validly signed by its original identity
/// (Developer ID + Team ID + notarization) with no further work. Re-signing
/// ad-hoc — what an earlier version did — strips the Team ID and bricks
/// hardened-runtime apps (library validation kills them at launch) while also
/// breaking keychain access and notarization.
///
/// The one hazard is a universal binary that the bundle seals as a plain
/// resource (e.g. a helper nested under `Contents/Resources/`): thinning it
/// invalidates the bundle signature and we can't fix that without the
/// developer's private key. So if the bundle was validly signed before
/// thinning and is no longer valid after, we roll the entire bundle back to
/// its original state and fail — an unchanged app beats a broken one.
public actor ThinAppBundleOperation {

    public struct Result: Sendable {
        public let binariesProcessed: Int
        public let binariesThinned: Int
        public let bytesSaved: UInt64
        public let perBinaryErrors: [String: String]   // path → error
        public let bundleVerifyFailed: Bool
    }

    public enum OpError: Error, LocalizedError, Sendable {
        case noFatBinariesFound
        case unsafeBundle(String)
        case bundleInUse(pids: [String])
        case bundleVerifyFailed(stderr: String)

        public var errorDescription: String? {
            switch self {
            case .noFatBinariesFound:
                L10n.tr(
                    "应用包中未找到通用 Mach-O 二进制文件",
                    "no fat (universal) Mach-O binaries found in bundle",
                    "В пакете нет универсальных бинарных файлов Mach-O"
                )
            case .unsafeBundle(let reason):
                L10n.tr(
                    "应用包不符合精简安全范围：\(reason)",
                    "app bundle is outside the safe thinning scope: \(reason)",
                    "Пакет приложения вне безопасной области обработки: \(reason)"
                )
            case .bundleInUse(let pids):
                L10n.tr(
                    "应用包正被进程 \(pids.joined(separator: ", ")) 使用——请退出应用后重试",
                    "bundle is in use by process(es) \(pids.joined(separator: ", ")) — quit the app and try again",
                    "Пакет используют процессы \(pids.joined(separator: ", ")). Закройте приложение и повторите попытку"
                )
            case .bundleVerifyFailed(let s):
                L10n.tr(
                    "精简会使应用的代码签名失效，因此已回滚：\(s)",
                    "thinning would have invalidated the app's code signature, so it was rolled back: \(s)",
                    "Удаление лишних архитектур сделало бы подпись кода приложения недействительной, поэтому изменения отменены: \(s)"
                )
            }
        }
    }

    private let logger = Logger(subsystem: MCConstants.bundleIdentifier,
                                category: "ThinAppBundleOperation")
    private let allowedRoots: [URL]
    private let safetyGuard: SafetyGuard

    public init() {
        self.allowedRoots = Self.productionAllowedRoots
        self.safetyGuard = SafetyGuard()
    }

    /// Test-only/internal injection point. Production callers use `init()`,
    /// which is permanently scoped to /Applications and ~/Applications.
    init(
        allowedRoots: [URL],
        safetyGuard: SafetyGuard = SafetyGuard()
    ) {
        self.allowedRoots = allowedRoots
        self.safetyGuard = safetyGuard
    }

    public func thin(bundle: URL, to targetArch: BinaryArch) async throws -> Result {
        try Self.validateBundleScope(
            bundle,
            allowedRoots: allowedRoots,
            safetyGuard: safetyGuard
        )

        // Pre-flight: nothing else may be using the bundle. If the user is
        // running Slack and tries to thin Slack, lipo would succeed but the
        // running process holds stale handles into the old binary that's
        // now sitting in our temp dir. Refuse rather than half-mutate.
        let busyPIDs = try Self.pidsHoldingFilesIn(bundle: bundle)
        if !busyPIDs.isEmpty {
            throw OpError.bundleInUse(pids: busyPIDs)
        }

        let binaries = MachOWalker.fatBinaries(in: bundle)
        guard !binaries.isEmpty else { throw OpError.noFatBinariesFound }

        // Was the bundle validly signed before we touched it? Only then do we
        // owe it a post-thin validity guarantee. An unsigned/dev bundle has no
        // signature to preserve or break, so thinning is best-effort there.
        let bundleWasSigned = Self.codesignVerifiesDeep(bundle)

        let fm = FileManager.default
        let backupDir = fm.temporaryDirectory
            .appending(path: "macclean-bundlethin-\(UUID().uuidString)")
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        // Cleaned up explicitly on success and on rollback; defer is the
        // backstop for any unexpected throw in between.
        defer { try? fm.removeItem(at: backupDir) }

        let op = ThinBinaryOperation()
        var thinned = 0
        var saved: UInt64 = 0
        var perBin: [String: String] = [:]
        var rollback: [(binary: URL, backup: URL)] = []

        for (index, binary) in binaries.enumerated() {
            let backupURL = backupDir.appending(path: "\(index).original")
            do {
                let r = try await op.thin(binary: binary, to: targetArch, backupTo: backupURL)
                thinned += 1
                saved += r.bytesSaved
                rollback.append((binary: binary, backup: backupURL))
            } catch {
                let path = binary.path(percentEncoded: false)
                perBin[path] = error.localizedDescription
                logger.error("ThinBinaryOperation failed on \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Safety gate: a bundle that was validly signed must still be valid
        // after thinning. If it isn't (a universal binary was sealed as a
        // plain resource, say), restore every thinned binary from its backup
        // and fail — we will not leave the user a broken app, and we will not
        // "fix" it by re-signing it into a different identity.
        if thinned > 0, bundleWasSigned, !Self.codesignVerifiesDeep(bundle) {
            for entry in rollback {
                try? fm.removeItem(at: entry.binary)
                try? fm.moveItem(at: entry.backup, to: entry.binary)
            }
            try? fm.removeItem(at: backupDir)
            throw OpError.bundleVerifyFailed(
                stderr: L10n.tr(
                    "精简后应用包无法再通过 codesign --verify",
                    "bundle no longer passes codesign --verify after thinning",
                    "После обработки пакет больше не проходит codesign --verify"
                )
            )
        }

        try? fm.removeItem(at: backupDir)

        return Result(
            binariesProcessed: binaries.count,
            binariesThinned: thinned,
            bytesSaved: saved,
            perBinaryErrors: perBin,
            bundleVerifyFailed: false
        )
    }

    // MARK: - Bundle scope

    /// The mutating actuator has its own path gate; it does not trust the UI or
    /// a stale scanner result to have supplied a safe application bundle.
    static let productionAllowedRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        MCConstants.home.appending(path: "Applications", directoryHint: .isDirectory),
    ]

    static func validateBundleScope(
        _ bundle: URL,
        allowedRoots: [URL] = productionAllowedRoots,
        safetyGuard: SafetyGuard = SafetyGuard()
    ) throws {
        let standardized = bundle.standardizedFileURL
        let path = standardized.path(percentEncoded: false)

        guard standardized.pathExtension.lowercased() == "app" else {
            throw OpError.unsafeBundle("not an .app bundle: \(path)")
        }

        guard let values = try? standardized.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ),
        values.isDirectory == true,
        values.isSymbolicLink != true
        else {
            throw OpError.unsafeBundle("bundle is missing, not a directory, or is a symbolic link")
        }

        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        let resolvedPath = resolved.path(percentEncoded: false)

        // Thinning mutates code in place, so reject any symlinked path rather
        // than merely checking that its textual prefix looks like Applications.
        // This also closes parent-directory symlink escapes.
        guard resolvedPath == path else {
            throw OpError.unsafeBundle("bundle path resolves through a symbolic link")
        }

        func isStrictDescendant(_ child: URL, of root: URL) -> Bool {
            let childPath = child.standardizedFileURL.path(percentEncoded: false)
            let rootPath = root.standardizedFileURL.path(percentEncoded: false)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let normalizedRoot = rootPath.isEmpty ? "/" : "/" + rootPath
            guard childPath != normalizedRoot else { return false }
            let prefix = normalizedRoot == "/" ? "/" : normalizedRoot + "/"
            return childPath.hasPrefix(prefix)
        }

        let insideAllowedRoot = allowedRoots.contains { root in
            isStrictDescendant(standardized, of: root)
                && isStrictDescendant(resolved, of: root.resolvingSymlinksInPath())
        }

        guard insideAllowedRoot else {
            throw OpError.unsafeBundle("bundle is not under /Applications or ~/Applications")
        }

        do {
            try safetyGuard.validatePath(standardized)
        } catch {
            throw OpError.unsafeBundle(error.localizedDescription)
        }
    }

    // MARK: - lsof pre-flight

    /// Returns the PIDs of any processes with open file descriptors anywhere
    /// inside `bundle`. Implemented via `lsof +D` — recursive directory
    /// scan. Returns an empty array if nothing is holding the bundle open.
    ///
    /// `lsof` exits 1 in BOTH cases of "no match" and "yes match, also some
    /// warnings printed to stderr" — so we ignore the exit code and parse
    /// stdout directly. Empty stdout → bundle is quiescent.
    static func pidsHoldingFilesIn(bundle: URL) throws -> [String] {
        let (_, stdout, _) = try runProcess("/usr/sbin/lsof", [
            "-F", "p",                                       // PID-only output
            "+D", bundle.path(percentEncoded: false),        // recurse into dir
        ])
        var pids = Set<String>()
        for line in stdout.split(separator: "\n") where line.first == "p" {
            pids.insert(String(line.dropFirst()))
        }
        return Array(pids)
    }

    // MARK: - codesign helpers

    /// True if the whole bundle (including nested code) passes
    /// `codesign --verify --deep`. Used both to learn whether the bundle was
    /// validly signed before thinning and to confirm it still is afterward.
    private static func codesignVerifiesDeep(_ bundle: URL) -> Bool {
        guard let (status, _, _) = try? runProcess("/usr/bin/codesign", [
            "--verify", "--deep", bundle.path(percentEncoded: false),
        ]) else { return false }
        return status == 0
    }

    private static func runProcess(
        _ executable: String, _ args: [String]
    ) throws -> (Int32, String, String) {
        let result = try ProcessOutputCapture.run(
            executable: URL(fileURLWithPath: executable),
            arguments: args
        )
        return (result.exitCode, result.stdout, result.stderr)
    }
}
