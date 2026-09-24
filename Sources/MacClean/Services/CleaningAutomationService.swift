import AppKit
import Foundation
import MacCleanKit
import UserNotifications

@MainActor
final class CleaningAutomationService {
    static let shared = CleaningAutomationService()

    private var browserTerminationObserver: NSObjectProtocol?
    private var trashSweepTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard browserTerminationObserver == nil else { return }

        browserTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  let bundleIdentifier = application.bundleIdentifier,
                  let browser = BrowserCleanupTarget.target(for: bundleIdentifier) else {
                return
            }

            Task { @MainActor [weak self] in
                await self?.handleBrowserTermination(browser)
            }
        }

        if CleaningAutomationPreferences.browserMode == .notify {
            requestNotificationPermission()
        }

        trashSweepTask?.cancel()
        trashSweepTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Check shortly after launch, then every six hours while CatCleaner
            // remains running. The preference defaults OFF.
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                await self.emptyAgedTrashIfEnabled()
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    func stop() {
        if let browserTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(browserTerminationObserver)
            self.browserTerminationObserver = nil
        }
        trashSweepTask?.cancel()
        trashSweepTask = nil
    }

    private func handleBrowserTermination(_ browser: BrowserCleanupTarget) async {
        // Browsers may briefly respawn helpers/processes during normal shutdown.
        // Wait for the process tree to settle, then require a full browser exit.
        try? await Task.sleep(for: .seconds(2))

        let stillRunning = NSWorkspace.shared.runningApplications.contains { app in
            guard let bundleIdentifier = app.bundleIdentifier else { return false }
            return browser.bundleIdentifiers.contains(bundleIdentifier)
        }

        let mode = CleaningAutomationPreferences.browserMode
        guard CleaningAutomationPolicy.shouldHandleBrowserTermination(
            browser: browser,
            mode: mode,
            browserEnabled: CleaningAutomationPreferences.isEnabled(browser),
            stillRunning: stillRunning
        ) else {
            return
        }

        let items = Self.safeCacheRootItems(for: browser)
        guard !items.isEmpty else {
            recordSummary("\(browser.displayName)：沒有偵測到可清理的安全快取")
            return
        }

        let estimatedBytes = await Self.estimatedAllocatedSize(of: items.map(\.url))

        guard CleaningAutomationPolicy.shouldAutoCleanBrowser(mode: mode) else {
            let message = "\(browser.displayName) 已關閉；安全快取約 "
                + ByteCountFormatter.string(
                    fromByteCount: Int64(estimatedBytes),
                    countStyle: .file
                )
                + "，可在 CatCleaner 手動清理"
            recordSummary(message)
            await sendNotification(title: "CatCleaner 清理提醒", body: message)
            return
        }

        // Re-check immediately before mutation. If the browser reopened while
        // scanning/estimating, fail closed and leave everything untouched.
        let reopened = NSWorkspace.shared.runningApplications.contains { app in
            guard let bundleIdentifier = app.bundleIdentifier else { return false }
            return browser.bundleIdentifiers.contains(bundleIdentifier)
        }
        guard !reopened else {
            recordSummary("\(browser.displayName) 已重新開啟；自動清理已取消")
            return
        }

        let result = await CleaningEngine().clean(items: items, mode: .trash)
        recordSummary(
            "\(browser.displayName)：已將 \(result.removedCount) 個安全快取根目錄移到垃圾桶，約 "
                + ByteCountFormatter.string(
                    fromByteCount: Int64(result.freedBytes),
                    countStyle: .file
                )
                + "；略過 \(result.skippedCount) 項，錯誤 \(result.errors.count) 項"
        )
    }

    private func emptyAgedTrashIfEnabled() async {
        guard CleaningAutomationPreferences.emptyTrashEnabled else { return }

        let outcome = await TrashBinsModule().scanReportingPermissions()
        guard !outcome.permissionDenied else {
            recordSummary("自動清空垃圾桶：需要「完整磁碟存取權」，本次未執行")
            return
        }

        let now = Date()
        let ageDays = CleaningAutomationPreferences.emptyTrashAgeDays
        let agedItems = outcome.results
            .flatMap(\.items)
            .filter {
                CleaningAutomationPolicy.shouldEmptyTrashItem(
                    modificationDate: $0.modificationDate,
                    now: now,
                    minimumAgeDays: ageDays
                )
            }

        guard !agedItems.isEmpty else { return }

        let result = await CleaningEngine().clean(items: agedItems, mode: .permanent)
        recordSummary(
            "自動清空垃圾桶：永久刪除 \(result.removedCount) 項（僅處理至少 \(ageDays) 天前的項目），"
                + "略過 \(result.skippedCount) 項，錯誤 \(result.errors.count) 項"
        )
    }

    func requestNotificationPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound]
            )
        }
    }

    private func sendNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.catcleaner.cleaning-automation.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func recordSummary(_ message: String) {
        SharedAppState.defaults.set(
            message,
            forKey: CleaningAutomationPreferences.lastBrowserCleanupSummaryKey
        )
        SharedAppState.defaults.set(
            Date(),
            forKey: CleaningAutomationPreferences.lastBrowserCleanupDateKey
        )
    }

    private static func safeCacheRootItems(
        for browser: BrowserCleanupTarget
    ) -> [FileItem] {
        let fileManager = FileManager.default

        return browser.safeCacheRoots.compactMap { url in
            let path = url.path(percentEncoded: false)
            guard fileManager.fileExists(atPath: path),
                  let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .isPackageKey,
                    .nameKey,
                    .contentModificationDateKey,
                ]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else {
                return nil
            }

            return FileItem(
                url: url,
                name: values.name ?? url.lastPathComponent,
                size: 0,
                allocatedSize: 0,
                isDirectory: true,
                isSymlink: false,
                isPackage: values.isPackage ?? false,
                modificationDate: values.contentModificationDate
            )
        }
    }

    private static func estimatedAllocatedSize(of roots: [URL]) async -> UInt64 {
        await Task.detached(priority: .utility) {
            estimatedAllocatedSizeSynchronously(of: roots)
        }.value
    }

    private nonisolated static func estimatedAllocatedSizeSynchronously(
        of roots: [URL]
    ) -> UInt64 {
        let fileManager = FileManager.default
        var total: UInt64 = 0

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .totalFileAllocatedSizeKey,
                    .isRegularFileKey,
                ],
                options: [.skipsPackageDescendants]
            ) else {
                continue
            }

            while let candidate = enumerator.nextObject() as? URL {
                guard let values = try? candidate.resourceValues(forKeys: [
                    .totalFileAllocatedSizeKey,
                    .isRegularFileKey,
                ]),
                values.isRegularFile == true else {
                    continue
                }
                total += UInt64(values.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
