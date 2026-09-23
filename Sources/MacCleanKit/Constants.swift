import Foundation

public enum MCConstants {
    public static let appName = "CatCleaner"
    public static let bundleIdentifier = "com.catcleaner.app"
    public static let helperBundleIdentifier = "com.catcleaner.helper"
    public static let menuBundleIdentifier = "com.catcleaner.menu"

    /// CatCleaner intentionally does not inherit the upstream project's Apple
    /// Developer Team ID. A downstream release must inject its own Team ID
    /// before any privileged/XPC trust path is enabled.
    ///
    /// Leaving this nil is fail-closed: callers cannot accidentally construct
    /// a trust requirement that authenticates binaries signed by the upstream
    /// project.
    public static let teamIdentifier: String? = nil

    /// Builds the strict Developer-ID requirement for a future privileged/XPC
    /// peer. Returns nil until CatCleaner has its own configured signing team.
    public static func codeSigningRequirement(for identifier: String) -> String? {
        guard let teamIdentifier else { return nil }
        return "identifier \"\(identifier)\" and anchor apple generic and "
            + "certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
    /// Per-CHUNK safety net enforced by SafetyGuard.validateDeletion.
    /// CleaningEngine internally chunks large selections into batches
    /// no larger than `cleanChunkSize` (5,000), so this cap is effectively
    /// a defense-in-depth boundary in case a future refactor accidentally
    /// bypasses the chunking. Total selection size is bounded by
    /// `maxTotalItemsPerCleanOperation` instead.
    public static let maxFilesPerOperation = 10_000

    /// CleaningEngine breaks large selections into chunks of this size so
    /// per-chunk SafetyGuard validation never trips on legitimate-but-large
    /// cleanups (Chrome cache alone often has 20k+ entries). 5k leaves
    /// 50% headroom under `maxFilesPerOperation`.
    public static let cleanChunkSize = 5_000

    /// Hard upper bound on a single Clean operation, regardless of
    /// chunking. Catches genuinely pathological scan results (e.g., a
    /// buggy module returning every file on disk) while leaving plenty
    /// of room for real cache cleanups. Set well above the largest
    /// legitimate selection observed in the wild (~200k).
    public static let maxTotalItemsPerCleanOperation = 500_000

    /// Selections above this size show a confirmation modal before Clean
    /// fires. Catches the "I just clicked Clean and now my Mac is going
    /// to do something for 5 minutes — was that intentional?" surprise.
    /// 50k = ~5MB of cache items on average; comfortably covers normal
    /// usage but flags the genuinely-big cleanups.
    public static let cleanConfirmationThreshold = 50_000
    public static let scanThrottleInterval: TimeInterval = 0.05 // 50ms UI update throttle

    // MARK: - Protected Paths (never touch these)

    public static let protectedPaths: Set<String> = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/Library/Apple",
        "/private/var/db",
    ]

    public static let protectedApps: Set<String> = [
        "com.apple.finder",
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.Terminal",
        "com.apple.systempreferences",
        "com.apple.ActivityMonitor",
        "com.apple.Console",
        "com.apple.DiskUtility",
        "com.apple.dt.Xcode",
        "com.apple.AppStore",
        "com.apple.iCal",
        "com.apple.AddressBook",
        "com.apple.Preview",
        "com.apple.TextEdit",
        "com.apple.calculator",
        "com.apple.Dictionary",
        "com.apple.Maps",
        "com.apple.Notes",
        "com.apple.reminders",
        "com.apple.Stickies",
        "com.apple.VoiceMemos",
        "com.apple.stocks",
        "com.apple.weather",
        "com.apple.Passwords",
        "com.apple.FaceTime",
        "com.apple.MobileSMS",
        "com.apple.Photos",
        "com.apple.Music",
    ]

    // MARK: - User Home Library Subdirectories

    public static let home = FileManager.default.homeDirectoryForCurrentUser

    public static let userLibrary = home.appending(path: "Library")
    public static let userCaches = userLibrary.appending(path: "Caches")
    public static let userLogs = userLibrary.appending(path: "Logs")
    public static let userPreferences = userLibrary.appending(path: "Preferences")
    public static let userAppSupport = userLibrary.appending(path: "Application Support")
    public static let userContainers = userLibrary.appending(path: "Containers")
    public static let userGroupContainers = userLibrary.appending(path: "Group Containers")
    public static let userLaunchAgents = userLibrary.appending(path: "LaunchAgents")
    public static let userSavedAppState = userLibrary.appending(path: "Saved Application State")
    public static let userCookies = userLibrary.appending(path: "Cookies")
    public static let userHTTPStorages = userLibrary.appending(path: "HTTPStorages")
    public static let userAppScripts = userLibrary.appending(path: "Application Scripts")
    public static let userWebKit = userLibrary.appending(path: "WebKit")

    // MARK: - System Library Directories

    public static let systemLibrary = URL(filePath: "/Library")
    public static let systemCaches = systemLibrary.appending(path: "Caches")
    public static let systemLogs = systemLibrary.appending(path: "Logs")
    public static let systemLaunchAgents = systemLibrary.appending(path: "LaunchAgents")
    public static let systemLaunchDaemons = systemLibrary.appending(path: "LaunchDaemons")
    public static let varLog = URL(filePath: "/var/log")

    // MARK: - Special Directories

    public static let userTrash = home.appending(path: ".Trash")
    public static let downloads = home.appending(path: "Downloads")
    public static let documentVersions = home.appending(path: ".DocumentRevisions-V100")
    public static let mobileBackups = userAppSupport.appending(path: "MobileSync/Backup")

    // MARK: - Xcode Directories

    public static let xcodeDerivedData = userLibrary.appending(path: "Developer/Xcode/DerivedData")
    public static let xcodeArchives = userLibrary.appending(path: "Developer/Xcode/Archives")
    public static let xcodeDeviceSupport = userLibrary.appending(path: "Developer/Xcode/iOS DeviceSupport")
    public static let coreSimulator = userLibrary.appending(path: "Developer/CoreSimulator")
    public static let xcodePreviews = userLibrary.appending(path: "Developer/Xcode/UserData/Previews")

    // MARK: - Browser Directories

    public static let safariCache = userLibrary.appending(path: "Caches/com.apple.Safari")
    public static let chromeDefault = userAppSupport.appending(path: "Google/Chrome/Default")
    public static let chromeCache = userCaches.appending(path: "Google/Chrome")
    public static let firefoxProfiles = userAppSupport.appending(path: "Firefox/Profiles")
    public static let firefoxCache = userCaches.appending(path: "Firefox/Profiles")

    // MARK: - Mail Directories

    public static let mailData = userLibrary.appending(path: "Mail")
    public static let mailDownloads = userLibrary.appending(path: "Mail Downloads")
    public static let mailContainerDownloads = userContainers
        .appending(path: "com.apple.mail/Data/Library/Mail Downloads")

    // MARK: - Dev Tool Caches

    public static let homebrewCache = userCaches.appending(path: "Homebrew")
    public static let npmCache = userCaches.appending(path: "npm")
    public static let pipCache = userCaches.appending(path: "pip")
    public static let cargoRegistry = home.appending(path: ".cargo/registry")

    // MARK: - Developer & AI Tool Caches
    //
    // Cache-only. The tools below keep history/memory/sessions/extensions right
    // next to these caches; those are user data and are deliberately NOT listed.

    // npm's real cache on macOS is ~/.npm/_cacache (not ~/Library/Caches/npm).
    public static let npmCacache = home.appending(path: ".npm/_cacache")
    public static let cargoRegistryCache = home.appending(path: ".cargo/registry/cache")
    public static let cargoRegistrySrc = home.appending(path: ".cargo/registry/src")
    public static let gradleCaches = home.appending(path: ".gradle/caches")
    public static let gradleDaemon = home.appending(path: ".gradle/daemon")
    public static let gradleWrapperDists = home.appending(path: ".gradle/wrapper/dists")

    public static let claudeCache = home.appending(path: ".claude/cache")
    public static let claudePasteCache = home.appending(path: ".claude/paste-cache")
    public static let claudeShellSnapshots = home.appending(path: ".claude/shell-snapshots")
    public static let codexTmp = home.appending(path: ".codex/.tmp")
    public static let codexCache = home.appending(path: ".codex/cache")

    /// Standard VS Code-family Electron cache dirs under Application Support.
    /// `User/` and installed `extensions` are excluded (user data / software).
    public static func electronEditorCaches(_ appSupportName: String) -> [URL] {
        let base = userAppSupport.appending(path: appSupportName)
        return ["Cache", "Code Cache", "GPUCache", "CachedData", "CachedProfilesData"]
            .map { base.appending(path: $0) }
    }
    public static var antigravityCaches: [URL] { electronEditorCaches("Antigravity") }
    public static var cursorCaches: [URL] { electronEditorCaches("Cursor") }

    // MARK: - Preserved Languages

    // English, Chinese, Russian (in common modern and legacy forms), and Base
    // are never offered for deletion. These include the interface languages
    // CatCleaner supports plus the base resources many apps require.
    public static let preservedLanguages: Set<String> = [
        "en.lproj", "English.lproj", "Base.lproj", "en_US.lproj", "en_GB.lproj",
        "zh.lproj", "zh-Hans.lproj", "zh-Hant.lproj", "zh_CN.lproj", "zh_TW.lproj",
        "Chinese.lproj", "Simplified Chinese.lproj", "Traditional Chinese.lproj",
        "ru.lproj", "ru-RU.lproj", "ru_RU.lproj", "Russian.lproj",
    ]

    // MARK: - Log File Path

    public static let operationLogDir = userLogs.appending(path: "CatCleaner")
    public static let operationLogFile = operationLogDir.appending(path: "operations.log")

    // MARK: - Project links

    /// Upstream source reference retained for attribution while CatCleaner has
    /// no public repository of its own.
    public static let repoURL = URL(string: "https://github.com/iliyami/MacSai")!
    public static let issuesURL: URL? = nil
    /// CatCleaner does not own a release channel yet. Keep these nil so every
    /// update-check entry point fails closed instead of querying the upstream
    /// Mac Sai project or its Homebrew cask.
    public static let releasesURL: URL? = nil
    public static let latestReleaseAPI: URL? = nil
    public static let homebrewCaskAPI: URL? = nil

    /// Enable only after CatCleaner owns a signed release feed and, if used,
    /// a CatCleaner-specific Homebrew cask.
    public static let updateChecksEnabled = false

    // MARK: - App version
    //
    // Bumped alongside the VERSION file at the repo root. CI verifies the
    // two stay in sync (scripts/check-version-sync.sh runs in ci.yml) —
    // a mismatch fails the build loudly. Build-time codegen via a SwiftPM
    // plugin was tried (commit history) but doesn't work under multi-arch
    // `swift build --arch arm64 --arch x86_64` because xcbuild doesn't
    // execute plugins.
    public static let appVersion = "0.1.0"
}
