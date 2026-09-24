import Foundation
import MacCleanKit

struct DeveloperCleanupExecutionSummary: Sendable, Equatable {
    let requestedCount: Int
    let trashedCount: Int
    let movedToTrashBytes: UInt64
    let garbageCollectedCount: Int
    let garbageCollectedBytes: UInt64
    let blockedCount: Int
    let errors: [String]

    static func empty(requestedCount: Int) -> Self {
        Self(
            requestedCount: requestedCount,
            trashedCount: 0,
            movedToTrashBytes: 0,
            garbageCollectedCount: 0,
            garbageCollectedBytes: 0,
            blockedCount: requestedCount,
            errors: []
        )
    }
}

/// Executes only the separately allowlisted subset of Developer Cleanup.
///
/// Discovery never grants deletion authority. Every execution starts from a
/// fresh scanner result, then rechecks the selected roots immediately before
/// mutation. General cache roots go through CleaningEngine's Trash-first path;
/// CatDesk build artifacts delegate to CatDesk's retention-aware GC helper.
struct DeveloperCleanupExecutor: Sendable {
    private let homeURL: URL
    private let processSnapshotOverride: String?
    private let cleanMode: CleaningEngine.CleanMode

    init(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        processSnapshot: String? = nil,
        cleanMode: CleaningEngine.CleanMode = .trash
    ) {
        self.homeURL = homeURL.standardizedFileURL
        self.processSnapshotOverride = processSnapshot
        self.cleanMode = cleanMode
    }

    func execute(
        selectedIDs: Set<String>,
        engine: CleaningEngine
    ) async -> DeveloperCleanupExecutionSummary {
        guard !selectedIDs.isEmpty else {
            return .empty(requestedCount: 0)
        }

        let requestedCount = selectedIDs.count
        let initialFresh = await DeveloperCleanupScanner(
            homeURL: homeURL,
            processSnapshot: processSnapshotOverride
        ).scan()
        let initialByID = Dictionary(uniqueKeysWithValues: initialFresh.map { ($0.id, $0) })

        var trashIDs = Set<String>()
        var gcIDs = Set<String>()
        var blockedCount = 0
        var errors: [String] = []

        for id in selectedIDs.sorted() {
            guard let candidate = initialByID[id],
                  let method = DeveloperCleanupExecutionPolicy.method(for: candidate)
            else {
                blockedCount += 1
                errors.append("\(id): no longer eligible for cleanup")
                continue
            }

            switch method {
            case .trashExactRoot:
                trashIDs.insert(id)
            case .catDeskBuildCacheGC:
                gcIDs.insert(id)
            }
        }

        if Task.isCancelled {
            return Self.summary(
                requestedCount: requestedCount,
                trashedCount: 0,
                movedToTrashBytes: 0,
                garbageCollectedCount: 0,
                garbageCollectedBytes: 0,
                blockedCount: blockedCount + trashIDs.count + gcIDs.count,
                errors: errors
            )
        }

        var trashedCount = 0
        var movedToTrashBytes: UInt64 = 0
        var garbageCollectedCount = 0
        var garbageCollectedBytes: UInt64 = 0

        // Fresh gate immediately before the Trash mutation. We trust only this
        // scan's canonical paths and current owner state, not UI/stale paths.
        if !trashIDs.isEmpty {
            let preTrashFresh = await DeveloperCleanupScanner(
                homeURL: homeURL,
                processSnapshot: processSnapshotOverride
            ).scan()
            let preTrashByID = Dictionary(uniqueKeysWithValues: preTrashFresh.map { ($0.id, $0) })
            var items: [FileItem] = []

            for id in trashIDs.sorted() {
                guard let candidate = preTrashByID[id],
                      DeveloperCleanupExecutionPolicy.method(for: candidate) == .trashExactRoot
                else {
                    blockedCount += 1
                    errors.append("\(id): owner/path state changed before cleanup")
                    continue
                }

                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(
                    atPath: candidate.url.path,
                    isDirectory: &isDirectory
                ),
                isDirectory.boolValue
                else {
                    blockedCount += 1
                    errors.append("\(id): expected cache root is no longer a directory")
                    continue
                }

                guard CleanFilter.isActionable(candidate.url) else {
                    blockedCount += 1
                    errors.append("\(id): path is not currently actionable")
                    continue
                }

                items.append(
                    FileItem(
                        url: candidate.url,
                        name: candidate.url.lastPathComponent,
                        size: candidate.allocatedSize,
                        allocatedSize: candidate.allocatedSize,
                        isDirectory: true
                    )
                )
            }

            if !items.isEmpty && !Task.isCancelled {
                let result = await engine.clean(items: items, mode: cleanMode)
                trashedCount += result.removedCount
                movedToTrashBytes += result.freedBytes
                blockedCount += result.skippedCount
                errors.append(contentsOf: result.errors.map {
                    "\($0.path): \($0.error)"
                })
            } else if Task.isCancelled {
                blockedCount += items.count
            }
        }

        // CatDesk gets its own final fresh gate and its own bounded helper.
        // Never fall back to trashing ~/.catdesk/build-cache as a whole.
        for id in gcIDs.sorted() {
            if Task.isCancelled {
                blockedCount += 1
                continue
            }

            let preGCFresh = await DeveloperCleanupScanner(
                homeURL: homeURL,
                processSnapshot: processSnapshotOverride
            ).scan()
            guard let candidate = preGCFresh.first(where: { $0.id == id }),
                  DeveloperCleanupExecutionPolicy.method(for: candidate) == .catDeskBuildCacheGC
            else {
                blockedCount += 1
                errors.append("\(id): owner/path state changed before CatDesk GC")
                continue
            }

            let result = await Self.runCatDeskBuildCacheGC(
                homeURL: homeURL,
                targetURL: candidate.url
            )

            if result.success {
                garbageCollectedCount += 1
                garbageCollectedBytes += result.reclaimedBytes
            } else {
                blockedCount += 1
                errors.append("\(id): \(result.message)")
            }
        }

        return Self.summary(
            requestedCount: requestedCount,
            trashedCount: trashedCount,
            movedToTrashBytes: movedToTrashBytes,
            garbageCollectedCount: garbageCollectedCount,
            garbageCollectedBytes: garbageCollectedBytes,
            blockedCount: blockedCount,
            errors: errors
        )
    }

    private struct GCResult: Sendable {
        let success: Bool
        let reclaimedBytes: UInt64
        let message: String
    }

    private struct ProcessResult: Sendable {
        let exitCode: Int32
        let output: String
    }

    private static func runCatDeskBuildCacheGC(
        homeURL: URL,
        targetURL: URL
    ) async -> GCResult {
        let helper = homeURL
            .appendingPathComponent(".catdesk/bin/catdesk-build-cache-gc")
            .standardizedFileURL

        let expectedTarget = homeURL
            .appendingPathComponent(".catdesk/build-cache")
            .standardizedFileURL

        guard targetURL.standardizedFileURL == expectedTarget else {
            return GCResult(
                success: false,
                reclaimedBytes: 0,
                message: "CatDesk 編譯快取路徑未通過精確路徑防護檢查"
            )
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: targetURL.path,
            isDirectory: &isDirectory
        ),
        isDirectory.boolValue
        else {
            return GCResult(
                success: false,
                reclaimedBytes: 0,
                message: "CatDesk 編譯快取根目錄不是資料夾"
            )
        }

        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return GCResult(
                success: false,
                reclaimedBytes: 0,
                message: "CatDesk 編譯快取清理工具目前無法使用"
            )
        }

        let before = await Task.detached(priority: .utility) {
            directorySizeBytes(targetURL)
        }.value

        let processResult = await Task.detached(priority: .utility) {
            runProcess(executable: helper.path, arguments: ["--apply"])
        }.value

        guard processResult.exitCode == 0 else {
            let tail = processResult.output
                .split(separator: "\n")
                .suffix(5)
                .joined(separator: " | ")
            return GCResult(
                success: false,
                reclaimedBytes: 0,
                message: tail.isEmpty
                    ? "CatDesk 編譯快取清理失敗，結束代碼 \(processResult.exitCode)"
                    : "CatDesk 編譯快取清理失敗：\(tail)"
            )
        }

        let after = await Task.detached(priority: .utility) {
            directorySizeBytes(targetURL)
        }.value

        return GCResult(
            success: true,
            reclaimedBytes: before > after ? before - after : 0,
            message: "完成"
        )
    }

    private static func directorySizeBytes(_ url: URL) -> UInt64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let result = runProcess(
            executable: "/usr/bin/du",
            arguments: ["-sk", url.path]
        )
        guard result.exitCode == 0,
              let first = result.output
                .split(whereSeparator: { $0.isWhitespace })
                .first,
              let kib = UInt64(first)
        else {
            return 0
        }
        return kib * 1024
    }

    /// Bounded local command runner for fixed executables/arguments only.
    /// Output is drained before waitUntilExit to avoid pipe-buffer deadlocks.
    private static func runProcess(
        executable: String,
        arguments: [String]
    ) -> ProcessResult {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return ProcessResult(
                exitCode: process.terminationStatus,
                output: String(data: data, encoding: .utf8) ?? ""
            )
        } catch {
            return ProcessResult(
                exitCode: -1,
                output: error.localizedDescription
            )
        }
    }

    private static func summary(
        requestedCount: Int,
        trashedCount: Int,
        movedToTrashBytes: UInt64,
        garbageCollectedCount: Int,
        garbageCollectedBytes: UInt64,
        blockedCount: Int,
        errors: [String]
    ) -> DeveloperCleanupExecutionSummary {
        DeveloperCleanupExecutionSummary(
            requestedCount: requestedCount,
            trashedCount: trashedCount,
            movedToTrashBytes: movedToTrashBytes,
            garbageCollectedCount: garbageCollectedCount,
            garbageCollectedBytes: garbageCollectedBytes,
            blockedCount: blockedCount,
            errors: errors
        )
    }
}
