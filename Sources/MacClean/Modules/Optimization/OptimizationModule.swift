import Foundation
import AppKit
import Darwin
import MacCleanKit

public struct OptimizationModule: ScanModule {
    public let id = "optimization"
    public var name: String { L10n.tr("优化", "Optimization", "Оптимизация") }
    public let category = ModuleCategory.performance

    public init() {}

    public func scan() async -> [ScanResult] {
        []
    }
}

// MARK: - Unified Auto-Start Model

public struct AutoStartItem: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let bundleIdentifier: String?
    public let programPath: String?
    public let configFilePath: String?
    public let sourceType: SourceType
    public let isSystem: Bool
    public var isEnabled: Bool

    public enum SourceType: String, Sendable, CaseIterable {
        case loginItem
        case launchAgent
        case launchDaemon

        public var localizedName: String {
            switch self {
            case .loginItem:    return L10n.tr("登录项", "Login Item", "Объект входа")
            case .launchAgent:  return L10n.tr("启动代理", "Launch Agent", "Агент запуска")
            case .launchDaemon: return L10n.tr("启动守护进程", "Launch Daemon", "Демон запуска")
            }
        }
    }

    public var hasConfigFile: Bool {
        guard let p = configFilePath else { return false }
        return !p.isEmpty
    }

    public var hasAppPath: Bool {
        guard let p = programPath else { return false }
        return !p.isEmpty
    }

    public var canToggle: Bool {
        switch sourceType {
        case .loginItem:
            return hasAppPath
        case .launchAgent, .launchDaemon:
            return !isSystem
        }
    }
}

// MARK: - Unified Auto-Start Manager

public final class AutoStartManager: @unchecked Sendable {
    static let disabledLoginItemsKey =
        "catcleaner.optimization.disabled-login-items-v1"

    private let defaults: UserDefaults
    private let loginItemProvider: () -> [AutoStartItem]

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(
            defaults: defaults,
            loginItemProvider: { Self.loadLoginItemsViaSystemEvents() }
        )
    }

    init(
        defaults: UserDefaults,
        loginItemProvider: @escaping () -> [AutoStartItem]
    ) {
        self.defaults = defaults
        self.loginItemProvider = loginItemProvider
    }

    // MARK: Public API

    public func getItems() -> [AutoStartItem] {
        var seen = Set<String>()
        let all = getLoginItems() + getLaunchAgents() + getLaunchDaemons()
        return all.filter { item in
            let key = item.bundleIdentifier ?? item.name
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    public func getLoginItems() -> [AutoStartItem] {
        let activeItems = loginItemProvider()
        let activePaths = Set(activeItems.compactMap(\.programPath))

        var remembered = rememberedDisabledLoginItems()
        var changed = false

        // If the user re-enabled an item outside CatCleaner, System Events sees
        // it as active again. Drop the stale remembered-disabled record.
        for path in activePaths where remembered.removeValue(forKey: path) != nil {
            changed = true
        }

        var disabledItems: [AutoStartItem] = []
        for (path, storedName) in remembered.sorted(by: { $0.key < $1.key }) {
            guard FileManager.default.fileExists(atPath: path) else {
                remembered.removeValue(forKey: path)
                changed = true
                continue
            }

            let url = URL(fileURLWithPath: path)
            let displayName = storedName.isEmpty
                ? FileManager.default.displayName(atPath: path)
                : storedName

            disabledItems.append(
                AutoStartItem(
                    name: displayName,
                    bundleIdentifier: Bundle(url: url)?.bundleIdentifier,
                    programPath: path,
                    configFilePath: path,
                    sourceType: .loginItem,
                    isSystem: false,
                    isEnabled: false
                )
            )
        }

        if changed {
            storeDisabledLoginItems(remembered)
        }

        return (activeItems + disabledItems).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func getLaunchAgents() -> [AutoStartItem] {
        var agents: [AutoStartItem] = []
        agents.append(contentsOf: scanPlistDir(MCConstants.userLaunchAgents, type: .launchAgent, isSystem: false))
        agents.append(contentsOf: scanPlistDir(MCConstants.systemLaunchAgents, type: .launchAgent, isSystem: true))
        return agents
    }

    public func getLaunchDaemons() -> [AutoStartItem] {
        scanPlistDir(MCConstants.systemLaunchDaemons, type: .launchDaemon, isSystem: true)
    }

    // MARK: Toggle

    public enum ToggleError: LocalizedError {
        case systemItemReadOnly
        case unreadablePlist
        case loginItemPathUnavailable
        case sfltoolFailed(String)

        public var errorDescription: String? {
            switch self {
            case .systemItemReadOnly:
                return L10n.tr(
                    "系统启动项为只读。",
                    "System startup items are read-only.",
                    "Системные элементы автозапуска доступны только для чтения."
                )
            case .unreadablePlist:
                return L10n.tr(
                    "无法读取此启动项配置。",
                    "This startup-item configuration could not be read.",
                    "Не удалось прочитать конфигурацию элемента автозапуска."
                )
            case .loginItemPathUnavailable:
                return L10n.tr(
                    "此登录项没有可验证的应用路径，因此 CatCleaner 不会直接修改它。",
                    "This login item has no verifiable app path, so CatCleaner will not modify it directly.",
                    "У этого объекта входа нет проверяемого пути к приложению, поэтому CatCleaner не будет изменять его напрямую."
                )
            case .sfltoolFailed(let message):
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty
                    ? L10n.tr(
                        "修改登录项失败。",
                        "Failed to change the login item.",
                        "Не удалось изменить объект входа."
                    )
                    : trimmed
            }
        }
    }

    public func toggleItem(_ item: AutoStartItem, enabled: Bool) throws {
        switch item.sourceType {
        case .loginItem:
            guard let path = item.programPath, !path.isEmpty else {
                throw ToggleError.loginItemPathUnavailable
            }

            try toggleLoginItem(path: path, enabled: enabled)

            var remembered = rememberedDisabledLoginItems()
            if enabled {
                remembered.removeValue(forKey: path)
            } else {
                remembered[path] = item.name
            }
            storeDisabledLoginItems(remembered)

        case .launchAgent, .launchDaemon:
            try togglePlistItem(item, enabled: enabled)
        }
    }

    // MARK: Open in Finder

    public func openConfigInFinder(_ item: AutoStartItem) {
        guard let path = item.configFilePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    public func openAppInFinder(_ item: AutoStartItem) {
        guard let path = item.programPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - Login Items Acquisition

    /// Read login items from System Settings → General → Login Items & Extensions
    /// via System Events (AppleScript). This is the only reliable API on macOS 15+
    /// — sfltool dumpbtm only returns system-level items (UID -2), and the old
    /// backgrounditems.btm plist path no longer exists.
    private struct SystemEventsLoginItemRecord: Decodable {
        let name: String
        let path: String?
        let hidden: Bool
    }

    private static func loadLoginItemsViaSystemEvents() -> [AutoStartItem] {
        let script = """
        const se = Application('System Events');
        const items = se.loginItems().map(item => {
          let path = null;
          try {
            const value = item.path();
            if (value !== null && value !== undefined && String(value) !== "missing value") {
              path = String(value);
            }
          } catch (_) {}
          return {
            name: String(item.name()),
            path,
            hidden: Boolean(item.hidden())
          };
        });
        JSON.stringify(items);
        """

        let result = Self.runOsaScript(
            arguments: ["-l", "JavaScript", "-e", script]
        )
        guard result.exitCode == 0 else { return [] }

        return Self.parseSystemEventsLoginItems(
            result.output,
            bundleIdentifierForPath: { path in
                Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
            }
        )
    }

    static func parseSystemEventsLoginItems(
        _ output: String,
        bundleIdentifierForPath: (String) -> String?
    ) -> [AutoStartItem] {
        guard let data = output.data(using: .utf8),
              let records = try? JSONDecoder().decode(
                [SystemEventsLoginItemRecord].self,
                from: data
              )
        else {
            return []
        }

        return records.compactMap { record in
            let trimmedName = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return nil }

            let path = record.path.flatMap { raw -> String? in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != "missing value" else { return nil }
                return trimmed
            }

            return AutoStartItem(
                name: trimmedName,
                bundleIdentifier: path.flatMap(bundleIdentifierForPath),
                programPath: path,
                configFilePath: path,
                sourceType: .loginItem,
                isSystem: false,
                isEnabled: true
            )
        }
    }

    @available(*, deprecated, message: "sfltool dumpbtm only shows system-level items, not user login items")
    public func reloadLoginItemsViaSfltool() -> [AutoStartItem] { [] }

    // MARK: - Launch Agents / Daemons Acquisition

    private func scanPlistDir(_ dir: URL, type: AutoStartItem.SourceType, isSystem: Bool) -> [AutoStartItem] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var items: [AutoStartItem] = []
        for url in contents where url.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }

            let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
            let program: String?
            if let prog = plist["Program"] as? String {
                program = prog
            } else if let args = plist["ProgramArguments"] as? [String] {
                program = args.first
            } else {
                program = nil
            }
            let disabled = plist["Disabled"] as? Bool ?? false

            // Resolve a human-readable name
            let name: String
            if let progPath = program, let displayName = resolveAppNameFromPath(progPath) {
                name = displayName
            } else {
                name = label
            }

            items.append(AutoStartItem(
                name: name,
                bundleIdentifier: label,
                programPath: program,
                configFilePath: url.path,
                sourceType: type,
                isSystem: isSystem,
                isEnabled: !disabled
            ))
        }
        return items
    }

    // MARK: - Helpers

    private func resolveAppNameFromPath(_ path: String) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return FileManager.default.displayName(atPath: expanded)
    }

    private func rememberedDisabledLoginItems() -> [String: String] {
        defaults.dictionary(forKey: Self.disabledLoginItemsKey) as? [String: String] ?? [:]
    }

    private func storeDisabledLoginItems(_ items: [String: String]) {
        defaults.set(items, forKey: Self.disabledLoginItemsKey)
    }

    // MARK: - Toggle Implementations


    private func toggleLoginItem(path: String, enabled: Bool) throws {
        let script: String
        if enabled {
            script = """
            on run argv
                if (count of argv) is not 1 then error "expected one login-item path"
                set targetPath to item 1 of argv
                tell application "System Events"
                    make new login item at end with properties {path:targetPath, hidden:false}
                end tell
            end run
            """
        } else {
            script = """
            on run argv
                if (count of argv) is not 1 then error "expected one login-item path"
                set targetPath to item 1 of argv
                tell application "System Events"
                    repeat with loginItem in every login item
                        try
                            set itemPath to path of loginItem
                            if itemPath is not missing value and (itemPath as text) is targetPath then
                                delete loginItem
                                return "removed"
                            end if
                        end try
                    end repeat
                end tell
                error "no login item matched the requested path"
            end run
            """
        }

        let result = Self.runOsaScript(
            arguments: ["-e", script, "--", path]
        )
        guard result.exitCode == 0 else {
            throw ToggleError.sfltoolFailed(result.output)
        }
    }

    private struct ScriptResult {
        let exitCode: Int32
        let output: String
    }

    private static func runOsaScript(arguments: [String]) -> ScriptResult {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            // Drain output while the child runs. Waiting first can deadlock if
            // an automation error or diagnostic exceeds the pipe buffer.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return ScriptResult(
                exitCode: process.terminationStatus,
                output: String(data: data, encoding: .utf8) ?? ""
            )
        } catch {
            return ScriptResult(
                exitCode: -1,
                output: error.localizedDescription
            )
        }
    }

    private func togglePlistItem(_ item: AutoStartItem, enabled: Bool) throws {
        guard !item.isSystem else { throw ToggleError.systemItemReadOnly }
        guard item.sourceType == .launchAgent,
              let configPath = item.configFilePath
        else {
            throw ToggleError.systemItemReadOnly
        }

        let configURL = URL(fileURLWithPath: configPath).standardizedFileURL
        guard Self.isSafeUserLaunchAgentConfig(configURL) else {
            throw ToggleError.unreadablePlist
        }

        let data = try Data(contentsOf: configURL)
        guard var plist = try PropertyListSerialization.propertyList(
            from: data,
            format: nil
        ) as? [String: Any] else {
            throw ToggleError.unreadablePlist
        }

        // Recheck immediately before mutation so a path that changed between
        // read and write fails closed rather than following a replacement
        // symlink outside ~/Library/LaunchAgents.
        guard Self.isSafeUserLaunchAgentConfig(configURL) else {
            throw ToggleError.unreadablePlist
        }

        plist["Disabled"] = !enabled
        let newData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try newData.write(to: configURL)
    }

    static func isSafeUserLaunchAgentConfig(
        _ url: URL,
        expectedRoot: URL = MCConstants.userLaunchAgents
    ) -> Bool {
        let standardized = url.standardizedFileURL
        let root = expectedRoot.standardizedFileURL

        guard standardized.deletingLastPathComponent() == root,
              standardized.pathExtension.lowercased() == "plist"
        else {
            return false
        }

        var metadata = stat()
        guard lstat(standardized.path(percentEncoded: false), &metadata) == 0 else {
            return false
        }

        let type = metadata.st_mode & S_IFMT
        return type == S_IFREG
    }
}

// MARK: - Backward-compatible Wrappers

public final class LoginItemsManager: @unchecked Sendable {
    public struct LoginItem: Identifiable, Sendable {
        public let id: UUID = UUID()
        public let name: String
        public let path: URL
        public let bundleIdentifier: String?
        public var isEnabled: Bool

        public var asAutoStartItem: AutoStartItem {
            AutoStartItem(
                name: name,
                bundleIdentifier: bundleIdentifier,
                programPath: path.path,
                configFilePath: path.path,
                sourceType: .loginItem,
                isSystem: false,
                isEnabled: isEnabled
            )
        }
    }

    private let inner = AutoStartManager()
    public init() {}

    public func getLoginItems() -> [LoginItem] {
        // Old behaviour read LaunchAgents plists as "login items" — that was
        // incorrect.  Redirect to the new unified manager which actually reads
        // real macOS login items.  Launch agents are now under
        // LaunchAgentsManager / the unified AutoStartManager.
        inner.getLoginItems().map { item in
            LoginItem(
                name: item.name,
                path: URL(fileURLWithPath: item.configFilePath ?? item.programPath ?? ""),
                bundleIdentifier: item.bundleIdentifier,
                isEnabled: item.isEnabled
            )
        }
    }

    public func toggleItem(_ item: LoginItem, enabled: Bool) throws {
        try inner.toggleItem(item.asAutoStartItem, enabled: enabled)
    }
}

public final class LaunchAgentsManager: @unchecked Sendable {
    public struct LaunchAgent: Identifiable, Sendable {
        public let id: UUID = UUID()
        public let label: String
        public let path: URL
        public let program: String?
        public let isSystem: Bool
        public var isEnabled: Bool

        public var asAutoStartItem: AutoStartItem {
            AutoStartItem(
                name: label,
                bundleIdentifier: label,
                programPath: program,
                configFilePath: path.path,
                sourceType: .launchAgent,
                isSystem: isSystem,
                isEnabled: isEnabled
            )
        }
    }

    private let inner = AutoStartManager()
    public init() {}

    public func getLaunchAgents() -> [LaunchAgent] {
        inner.getLaunchAgents().map { item in
            LaunchAgent(
                label: item.name,
                path: URL(fileURLWithPath: item.configFilePath ?? ""),
                program: item.programPath,
                isSystem: item.isSystem,
                isEnabled: item.isEnabled
            )
        }
    }

    public enum ToggleError: Error { case systemAgentReadOnly, unreadablePlist }

    public func toggleAgent(_ agent: LaunchAgent, enabled: Bool) throws {
        do {
            try inner.toggleItem(agent.asAutoStartItem, enabled: enabled)
        } catch AutoStartManager.ToggleError.systemItemReadOnly {
            throw ToggleError.systemAgentReadOnly
        } catch AutoStartManager.ToggleError.unreadablePlist {
            throw ToggleError.unreadablePlist
        } catch {
            throw ToggleError.unreadablePlist
        }
    }
}

// MARK: - Process Monitor

public final class ProcessMonitor: @unchecked Sendable {
    public struct ProcessInfo: Identifiable, Sendable {
        public let id: Int32
        public let name: String
        public let cpuUsage: Double
        public let memoryBytes: UInt64
        public let isResponsive: Bool
    }

    public init() {}

    public func getRunningApps() -> [ProcessInfo] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let name = app.localizedName, !app.isHidden else { return nil }
            return ProcessInfo(
                id: app.processIdentifier,
                name: name,
                cpuUsage: 0,
                memoryBytes: 0,
                isResponsive: !app.isTerminated
            )
        }
    }

    public func forceQuit(pid: Int32) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.forceTerminate()
        }
    }
}
