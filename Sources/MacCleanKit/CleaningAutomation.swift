import Foundation

public enum BrowserCleanupTarget: String, CaseIterable, Identifiable, Sendable, Codable {
    case safari
    case chrome
    case firefox

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Google Chrome"
        case .firefox: "Firefox"
        }
    }

    public var bundleIdentifiers: Set<String> {
        switch self {
        case .safari:
            ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
        case .chrome:
            ["com.google.Chrome", "com.google.Chrome.canary"]
        case .firefox:
            ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition"]
        }
    }

    /// Cache-only roots. No cookies, passwords, autofill, bookmarks,
    /// browser profiles, extensions, or Keychain material are included.
    public var safeCacheRoots: [URL] {
        switch self {
        case .safari:
            [MCConstants.safariCache]
        case .chrome:
            [
                MCConstants.chromeCache,
                MCConstants.chromeDefault.appending(path: "Cache"),
                MCConstants.chromeDefault.appending(path: "Code Cache"),
            ]
        case .firefox:
            [MCConstants.firefoxCache]
        }
    }

    public static func target(for bundleIdentifier: String) -> BrowserCleanupTarget? {
        allCases.first { $0.bundleIdentifiers.contains(bundleIdentifier) }
    }
}

public enum AutomaticBrowserCleanupMode: String, CaseIterable, Sendable, Codable {
    case off
    case notify
    case moveSafeCachesToTrash

    public var localizedName: String {
        switch self {
        case .off: L10n.tr("关闭", "Off", "Выкл.")
        case .notify: L10n.tr("只提醒", "Notify only", "Только уведомлять")
        case .moveSafeCachesToTrash:
            L10n.tr(
                "自动将安全缓存移到废纸篓",
                "Automatically move safe caches to Trash",
                "Автоматически перемещать безопасный кэш в Корзину"
            )
        }
    }
}

public enum CleaningAutomationPreferences {
    public static let browserModeKey = "cleaningAutomationBrowserMode"
    public static let safariEnabledKey = "cleaningAutomationSafariEnabled"
    public static let chromeEnabledKey = "cleaningAutomationChromeEnabled"
    public static let firefoxEnabledKey = "cleaningAutomationFirefoxEnabled"
    public static let smartThresholdMBKey = "cleaningAutomationSmartThresholdMB"
    public static let emptyTrashEnabledKey = "cleaningAutomationEmptyTrashEnabled"
    public static let emptyTrashAgeDaysKey = "cleaningAutomationEmptyTrashAgeDays"
    public static let lastBrowserCleanupSummaryKey = "cleaningAutomationLastBrowserCleanupSummary"
    public static let lastBrowserCleanupDateKey = "cleaningAutomationLastBrowserCleanupDate"

    public static var browserMode: AutomaticBrowserCleanupMode {
        get {
            guard let raw = SharedAppState.defaults.string(forKey: browserModeKey),
                  let mode = AutomaticBrowserCleanupMode(rawValue: raw) else {
                return .off
            }
            return mode
        }
        set {
            SharedAppState.defaults.set(newValue.rawValue, forKey: browserModeKey)
        }
    }

    public static func isEnabled(_ browser: BrowserCleanupTarget) -> Bool {
        let key: String
        switch browser {
        case .safari: key = safariEnabledKey
        case .chrome: key = chromeEnabledKey
        case .firefox: key = firefoxEnabledKey
        }

        guard SharedAppState.defaults.object(forKey: key) != nil else {
            return true
        }
        return SharedAppState.defaults.bool(forKey: key)
    }

    public static var smartThresholdMB: Int {
        get {
            let raw = SharedAppState.defaults.object(forKey: smartThresholdMBKey) as? Int ?? 500
            return min(max(raw, 100), 10_240)
        }
        set {
            SharedAppState.defaults.set(min(max(newValue, 100), 10_240), forKey: smartThresholdMBKey)
        }
    }

    public static var emptyTrashEnabled: Bool {
        get { SharedAppState.defaults.bool(forKey: emptyTrashEnabledKey) }
        set { SharedAppState.defaults.set(newValue, forKey: emptyTrashEnabledKey) }
    }

    public static var emptyTrashAgeDays: Int {
        get {
            let raw = SharedAppState.defaults.object(forKey: emptyTrashAgeDaysKey) as? Int ?? 30
            return min(max(raw, 1), 365)
        }
        set {
            SharedAppState.defaults.set(min(max(newValue, 1), 365), forKey: emptyTrashAgeDaysKey)
        }
    }
}

public enum CleaningAutomationPolicy {
    public static func shouldHandleBrowserTermination(
        browser: BrowserCleanupTarget,
        mode: AutomaticBrowserCleanupMode,
        browserEnabled: Bool,
        stillRunning: Bool
    ) -> Bool {
        mode != .off && browserEnabled && !stillRunning
    }

    public static func shouldAutoCleanBrowser(
        mode: AutomaticBrowserCleanupMode
    ) -> Bool {
        mode == .moveSafeCachesToTrash
    }

    public static func shouldRaiseSmartCleaningAlert(
        reclaimableBytes: UInt64,
        thresholdMB: Int
    ) -> Bool {
        let threshold = UInt64(min(max(thresholdMB, 100), 10_240)) * 1_000_000
        return reclaimableBytes >= threshold
    }

    public static func shouldEmptyTrashItem(
        modificationDate: Date?,
        now: Date,
        minimumAgeDays: Int
    ) -> Bool {
        guard let modificationDate else { return false }
        let age = now.timeIntervalSince(modificationDate)
        let days = TimeInterval(min(max(minimumAgeDays, 1), 365)) * 86_400
        return age >= days
    }
}
