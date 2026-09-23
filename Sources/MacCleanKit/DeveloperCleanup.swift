import Foundation

/// High-level storage semantics for development and AI-tool data.
///
/// These are intentionally about *rebuildability and retention*, not merely
/// pathname patterns. CatCleaner never treats every large directory as junk.
public enum DeveloperCleanupKind: String, Sendable, CaseIterable {
    case rebuildableCache
    case boundedRetention
    case downloadedModel
    case statefulRuntime
}

/// The most aggressive action CatCleaner may recommend for a candidate.
///
/// V1 is scan-only; these values describe policy and are not execution hooks.
public enum DeveloperCleanupDisposition: String, Sendable, CaseIterable {
    /// Rebuildable data. A future cleanup action may run only while its owner is
    /// inactive and should prefer the owning tool's cleanup command.
    case safeWhenInactive

    /// Recovery/snapshot/release history that needs a retention index or other
    /// bounded-review proof before permanent deletion.
    case retentionReview

    /// Stateful data such as VM disks, container volumes, or user sessions.
    /// Report size only; never present as one-click junk.
    case reportOnly
}

public struct DeveloperCleanupCandidate: Identifiable, Sendable, Equatable {
    public let id: String
    public let titleKey: String
    public let owner: String
    public let url: URL
    public let allocatedSize: UInt64
    public let kind: DeveloperCleanupKind
    public let disposition: DeveloperCleanupDisposition
    public let ownerActive: Bool
    public let policyNoteKey: String

    public init(
        id: String,
        titleKey: String,
        owner: String,
        url: URL,
        allocatedSize: UInt64,
        kind: DeveloperCleanupKind,
        disposition: DeveloperCleanupDisposition,
        ownerActive: Bool,
        policyNoteKey: String
    ) {
        self.id = id
        self.titleKey = titleKey
        self.owner = owner
        self.url = url
        self.allocatedSize = allocatedSize
        self.kind = kind
        self.disposition = disposition
        self.ownerActive = ownerActive
        self.policyNoteKey = policyNoteKey
    }

    public var canBecomeCleanable: Bool {
        disposition == .safeWhenInactive && !ownerActive
    }
}

/// Read-only scanner for high-value developer / AI storage.
///
/// The scanner has no deletion API. Keeping discovery separate from execution
/// prevents a newly-added path rule from silently becoming a destructive rule.
public struct DeveloperCleanupScanner: Sendable {
    private let homeURL: URL
    private let processSnapshotOverride: String?

    public init(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        processSnapshot: String? = nil
    ) {
        self.homeURL = homeURL.standardizedFileURL
        self.processSnapshotOverride = processSnapshot
    }

    public func scan(maxConcurrentSizeProbes: Int = 4) async -> [DeveloperCleanupCandidate] {
        let processText = processSnapshotOverride ?? Self.currentProcessText()
        let definitions = Self.definitions(homeURL: homeURL).filter {
            FileManager.default.fileExists(atPath: $0.url.path)
        }
        guard !definitions.isEmpty else { return [] }

        let concurrency = min(max(1, maxConcurrentSizeProbes), definitions.count)

        let candidates = await withTaskGroup(of: DeveloperCleanupCandidate.self) { group in
            var nextIndex = 0
            var collected: [DeveloperCleanupCandidate] = []
            collected.reserveCapacity(definitions.count)

            func submit(_ definition: Definition) {
                group.addTask {
                    let url = definition.url.standardizedFileURL
                    let size = Self.allocatedSize(of: url)
                    let active = definition.activeMatch.matches(
                        processText: processText,
                        exactPath: url.path
                    )

                    return DeveloperCleanupCandidate(
                        id: definition.id,
                        titleKey: definition.titleKey,
                        owner: definition.owner,
                        url: url,
                        allocatedSize: size,
                        kind: definition.kind,
                        disposition: definition.disposition,
                        ownerActive: active,
                        policyNoteKey: definition.policyNoteKey
                    )
                }
            }

            while nextIndex < concurrency {
                submit(definitions[nextIndex])
                nextIndex += 1
            }

            while let candidate = await group.next() {
                collected.append(candidate)
                if nextIndex < definitions.count {
                    submit(definitions[nextIndex])
                    nextIndex += 1
                }
            }

            return collected
        }

        return candidates.sorted {
            if $0.allocatedSize == $1.allocatedSize {
                return $0.id < $1.id
            }
            return $0.allocatedSize > $1.allocatedSize
        }
    }

    // MARK: - Definitions

    private struct Definition: Sendable {
        let id: String
        let titleKey: String
        let owner: String
        let url: URL
        let kind: DeveloperCleanupKind
        let disposition: DeveloperCleanupDisposition
        let activeMatch: ActiveMatch
        let policyNoteKey: String
    }

    private enum ActiveMatch: Sendable {
        case none
        case exactPath
        case tokens([String])

        func matches(processText: String, exactPath: String) -> Bool {
            switch self {
            case .none:
                return false
            case .exactPath:
                return processText.contains(exactPath)
            case .tokens(let tokens):
                let lower = processText.lowercased()
                return tokens.contains { lower.contains($0.lowercased()) }
            }
        }
    }

    private static func definitions(homeURL: URL) -> [Definition] {
        func path(_ relative: String) -> URL {
            homeURL.appendingPathComponent(relative).standardizedFileURL
        }

        return [
            // CatDesk — build products are rebuildable, while rollback stores
            // require their own retention evidence before any purge.
            Definition(
                id: "catdesk-build-cache",
                titleKey: "CatDesk 编译缓存",
                owner: "CatDesk",
                url: path(".catdesk/build-cache"),
                kind: .rebuildableCache,
                disposition: .safeWhenInactive,
                activeMatch: .exactPath,
                policyNoteKey: "仅在没有编译进程使用时清理；保留生产运行时"
            ),
            Definition(
                id: "catdesk-recovery",
                titleKey: "CatDesk 恢复记录",
                owner: "CatDesk",
                url: path(".catdesk/recovery_bin"),
                kind: .boundedRetention,
                disposition: .retentionReview,
                activeMatch: .none,
                policyNoteKey: "必须先按恢复操作分类与保留期限审查"
            ),
            Definition(
                id: "catdesk-snapshots",
                titleKey: "CatDesk 安全快照",
                owner: "CatDesk",
                url: path(".catdesk/safety_snapshots"),
                kind: .boundedRetention,
                disposition: .retentionReview,
                activeMatch: .none,
                policyNoteKey: "只清理已证明被取代的快照，禁止整批删除"
            ),

            // Codex / ChatGPT.
            Definition(
                id: "codex-cache",
                titleKey: "Codex 缓存",
                owner: "Codex",
                url: path("Library/Caches/Codex"),
                kind: .rebuildableCache,
                disposition: .safeWhenInactive,
                activeMatch: .tokens(["/Codex", "ChatGPT.app"]),
                policyNoteKey: "关闭 Codex/ChatGPT 后才可清理可重建缓存"
            ),
            Definition(
                id: "codex-sessions",
                titleKey: "Codex 会话",
                owner: "Codex",
                url: path(".codex/sessions"),
                kind: .statefulRuntime,
                disposition: .reportOnly,
                activeMatch: .tokens(["/Codex", "ChatGPT.app"]),
                policyNoteKey: "会话是状态数据，只报告容量，不作为垃圾自动删除"
            ),

            // Package managers / build tooling.
            Definition(
                id: "npm-content-cache",
                titleKey: "npm 内容缓存",
                owner: "npm",
                url: path(".npm/_cacache"),
                kind: .rebuildableCache,
                disposition: .safeWhenInactive,
                activeMatch: .tokens(["npm ", "npx "]),
                policyNoteKey: "优先使用 npm 自带清理命令"
            ),
            Definition(
                id: "npx-ephemeral-cache",
                titleKey: "npx 临时安装缓存",
                owner: "npx",
                url: path(".npm/_npx"),
                kind: .rebuildableCache,
                disposition: .safeWhenInactive,
                activeMatch: .tokens(["npm ", "npx "]),
                policyNoteKey: "无 npm/npx 进程时可重建"
            ),
            Definition(
                id: "pip-cache",
                titleKey: "pip 缓存",
                owner: "pip",
                url: path("Library/Caches/pip"),
                kind: .rebuildableCache,
                disposition: .safeWhenInactive,
                activeMatch: .tokens(["pip ", "python -m pip"]),
                policyNoteKey: "优先使用 pip cache purge"
            ),
            Definition(
                id: "homebrew-cache",
                titleKey: "Homebrew 缓存",
                owner: "Homebrew",
                url: path("Library/Caches/Homebrew"),
                kind: .rebuildableCache,
                disposition: .safeWhenInactive,
                activeMatch: .tokens(["brew "]),
                policyNoteKey: "优先使用 brew cleanup"
            ),
            Definition(
                id: "playwright-browsers",
                titleKey: "Playwright 浏览器缓存",
                owner: "Playwright",
                url: path("Library/Caches/ms-playwright"),
                kind: .rebuildableCache,
                disposition: .safeWhenInactive,
                activeMatch: .tokens(["playwright"]),
                policyNoteKey: "关闭 Playwright 工作后可重新下载"
            ),
            Definition(
                id: "node-gyp-cache",
                titleKey: "node-gyp 标头缓存",
                owner: "node-gyp",
                url: path("Library/Caches/node-gyp"),
                kind: .rebuildableCache,
                disposition: .safeWhenInactive,
                activeMatch: .tokens(["node-gyp"]),
                policyNoteKey: "已下载的 Node 标头可按版本重新取得"
            ),
            Definition(
                id: "cargo-registry",
                titleKey: "Cargo 套件缓存",
                owner: "Cargo",
                url: path(".cargo/registry"),
                kind: .rebuildableCache,
                disposition: .safeWhenInactive,
                activeMatch: .tokens(["cargo ", "rustc "]),
                policyNoteKey: "Rust 编译运行中禁止清理"
            ),
            Definition(
                id: "cargo-git",
                titleKey: "Cargo Git 缓存",
                owner: "Cargo",
                url: path(".cargo/git"),
                kind: .rebuildableCache,
                disposition: .safeWhenInactive,
                activeMatch: .tokens(["cargo ", "rustc "]),
                policyNoteKey: "Rust 编译运行中禁止清理"
            ),

            // Browser / AI tools.
            Definition(
                id: "chrome-cache",
                titleKey: "Chrome 应用缓存",
                owner: "Google Chrome",
                url: path("Library/Caches/Google"),
                kind: .rebuildableCache,
                disposition: .safeWhenInactive,
                activeMatch: .tokens(["Google Chrome"]),
                policyNoteKey: "Chrome 运行中禁止修改其缓存"
            ),
            Definition(
                id: "chrome-on-device-model",
                titleKey: "Chrome 本机 AI 模型",
                owner: "Google Chrome",
                url: path("Library/Application Support/Google/Chrome/OptGuideOnDeviceModel"),
                kind: .downloadedModel,
                disposition: .retentionReview,
                activeMatch: .tokens(["Google Chrome"]),
                policyNoteKey: "大型可重新下载模型；关闭 Chrome 后另行确认再清理"
            ),
            Definition(
                id: "claude-vm",
                titleKey: "Claude 虚拟机",
                owner: "Claude",
                url: path("Library/Application Support/Claude/vm_bundles"),
                kind: .statefulRuntime,
                disposition: .reportOnly,
                activeMatch: .tokens(["Claude.app", "/Claude "]),
                policyNoteKey: "虚拟机可能含状态；只报告，不做一键删除"
            ),
            Definition(
                id: "docker-data",
                titleKey: "Docker 数据",
                owner: "Docker",
                url: path("Library/Containers/com.docker.docker"),
                kind: .statefulRuntime,
                disposition: .reportOnly,
                activeMatch: .tokens(["Docker.app", "com.docker"]),
                policyNoteKey: "应通过 Docker 自身清理未使用资源，绝不直接删除卷"
            ),
            Definition(
                id: "alpha-cache",
                titleKey: "Alpha Consensus 缓存",
                owner: "Alpha Consensus",
                url: path("Library/Caches/Alpha Consensus"),
                kind: .rebuildableCache,
                disposition: .safeWhenInactive,
                activeMatch: .tokens(["Alpha Consensus", "Application Support/Alpha Consensus"]),
                policyNoteKey: "运行中保持不动；关闭后仅清理可重建缓存"
            ),
            Definition(
                id: "alpha-retired-runtimes",
                titleKey: "Alpha Consensus 旧运行时",
                owner: "Alpha Consensus",
                url: path("Library/Application Support/Alpha Consensus/Recovery/retired-releases"),
                kind: .boundedRetention,
                disposition: .retentionReview,
                activeMatch: .exactPath,
                policyNoteKey: "必须保护 current/previous，并按版本保留策略审查"
            )
        ]
    }

    // MARK: - Read-only probes

    private static func currentProcessText() -> String {
        run(executable: "/bin/ps", arguments: ["-axo", "command="]) ?? ""
    }

    private static func allocatedSize(of url: URL) -> UInt64 {
        guard let output = run(executable: "/usr/bin/du", arguments: ["-sk", url.path]),
              let first = output.split(whereSeparator: { $0.isWhitespace }).first,
              let kib = UInt64(first)
        else {
            return 0
        }
        return kib * 1024
    }

    private static func run(executable: String, arguments: [String]) -> String? {
        let process = Process()
        let stdout = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        // These read-only probes do not need stderr. Sending it to /dev/null
        // prevents a second pipe from becoming another back-pressure source.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            // Drain stdout while the child is running. Waiting first can
            // deadlock when a large process-table listing exceeds the kernel
            // pipe buffer on a busy developer machine.
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
