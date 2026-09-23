import Foundation

/// User-facing language for the CatCleaner interface.
///
/// We keep the preference in the shared defaults suite so the main app and the
/// menu-bar helper switch languages together.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case ru = "ru"
    case zhHans = "zh-Hans"
    case zhHantTW = "zh-Hant-TW"
    case en = "en"

    public static let defaultsKey = "appLanguage"
    public static let fallback: AppLanguage = .en

    public var id: String { rawValue }

    public var localeIdentifier: String { resolved.localeIdentifierForResolvedLanguage }

    private var localeIdentifierForResolvedLanguage: String {
        switch self {
        case .system:
            Self.systemPreferred.localeIdentifierForResolvedLanguage
        case .ru:
            "ru"
        case .zhHans:
            "zh-Hans"
        case .zhHantTW:
            "zh-Hant-TW"
        case .en:
            "en"
        }
    }

    public var resolved: AppLanguage {
        switch self {
        case .system: Self.systemPreferred
        case .ru, .zhHans, .zhHantTW, .en: self
        }
    }

    public static var systemPreferred: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        return preferredLanguage(for: preferred)
    }

    static func preferredLanguage(for identifier: String) -> AppLanguage {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        let parts = normalized.split(separator: "-").map(String.init)
        guard let language = parts.first else { return .en }

        switch language {
        case "ru":
            return .ru
        case "zh":
            // Traditional Chinese locales/scripts used by Taiwan, Hong Kong,
            // and Macau should never silently fall back to Simplified Chinese.
            let traditionalMarkers = Set(["hant", "tw", "hk", "mo"])
            return parts.dropFirst().contains(where: traditionalMarkers.contains)
                ? .zhHantTW
                : .zhHans
        default:
            return .en
        }
    }

    /// Label shown in the language picker. These are intentionally native names
    /// instead of going through `L10n.tr`, so users can always find their
    /// preferred language even if the current UI language is unfamiliar.
    public var pickerLabel: String {
        switch self {
        case .system: L10n.tr("跟随系统", "System", "Системный")
        case .ru: "Русский"
        case .zhHans: "简体中文"
        case .zhHantTW: "繁體中文（台灣）"
        case .en: "English"
        }
    }

    public static var current: AppLanguage {
        get {
            if let raw = SharedAppState.defaults.string(forKey: defaultsKey),
               let language = AppLanguage(rawValue: raw) {
                return language
            }
            if let raw = UserDefaults.standard.string(forKey: defaultsKey),
               let language = AppLanguage(rawValue: raw) {
                return language
            }
            return fallback
        }
        set {
            SharedAppState.defaults.set(newValue.rawValue, forKey: defaultsKey)
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    /// Set a product default without changing an existing user choice. Tests and
    /// command-line tools keep the English fallback, while the shipped apps call
    /// this on launch to follow the user's system language by default.
    public static func registerDefault(_ language: AppLanguage) {
        guard SharedAppState.defaults.string(forKey: defaultsKey) == nil,
              UserDefaults.standard.string(forKey: defaultsKey) == nil else { return }
        current = language
    }
}

/// Lightweight runtime localization used by both executables.
///
/// The project is mostly SwiftUI views plus model strings that were originally
/// hard-coded. A full `.strings` migration would require touching almost every
/// call site and packaging resource bundles for the custom app builder. This
/// helper keeps the current no-resource build flow while still allowing instant
/// Simplified Chinese/Traditional Chinese (Taiwan)/English/Russian switching at runtime.
public enum L10n {
    /// Keeps newly added strings usable until a Russian translation is supplied.
    /// Existing localized strings use the three-argument overload below.
    public static func tr(_ zhHans: String, _ english: @autoclosure () -> String) -> String {
        switch AppLanguage.current.resolved {
        case .zhHans: zhHans
        case .zhHantTW: zhHantTW(zhHans)
        case .system, .en: english()
        case .ru: russianFallbacks[zhHans] ?? english()
        }
    }

    public static func tr(
        _ zhHans: String,
        _ english: @autoclosure () -> String,
        _ russian: @autoclosure () -> String
    ) -> String {
        switch AppLanguage.current.resolved {
        case .system, .en: english()
        case .ru: russian()
        case .zhHans: zhHans
        case .zhHantTW: zhHantTW(zhHans)
        }
    }

    public static func tr(_ zhHans: String) -> String {
        switch AppLanguage.current.resolved {
        case .system, .en:
            englishFallbacks[zhHans] ?? zhHans
        case .ru:
            russianFallbacks[zhHans] ?? englishFallbacks[zhHans] ?? zhHans
        case .zhHans:
            zhHans
        case .zhHantTW:
            zhHantTW(zhHans)
        }
    }

    /// Converts the existing Simplified-Chinese source string to Traditional
    /// Chinese, then applies Taiwan-specific terminology. Keeping this in one
    /// place lets the existing L10n call sites gain zh-Hant-TW coverage without
    /// duplicating a fourth argument everywhere.
    private static func zhHantTW(_ zhHans: String) -> String {
        let converted = zhHans.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? zhHans

        // Phrase-first replacements align generic Traditional Chinese with
        // common Taiwan/macOS terminology.
        let replacements: [(String, String)] = [
            ("應用程序", "應用程式"),
            ("卸載器", "解除安裝工具"),
            ("卸載", "解除安裝"),
            ("廢紙簍", "垃圾桶"),
            ("高速緩存", "快取"),
            ("緩存", "快取"),
            ("文件夾", "資料夾"),
            ("大文件", "大型檔案"),
            ("文檔", "文件"),
            ("文件", "檔案"),
            ("壓縮包", "壓縮檔"),
            ("安裝包", "安裝套件"),
            ("內存", "記憶體"),
            ("磁盤", "磁碟"),
            ("設置", "設定"),
            ("偏好設定面板", "偏好設定面板"),
            ("偏好設置", "偏好設定"),
            ("日誌", "記錄"),
            ("搜索", "搜尋"),
            ("查找", "尋找"),
            ("程序", "程式"),
            ("網絡", "網路"),
            ("視頻", "影片"),
            ("音頻", "音訊"),
            ("鼠標", "滑鼠"),
            ("點擊", "按一下"),
            ("賬戶", "帳號"),
            ("帳戶", "帳號"),
            ("默認", "預設"),
            ("恢復默認", "回復預設值"),
            ("刷新", "重新整理"),
            ("優化", "最佳化"),
            ("性能", "效能"),
            ("擴展", "擴充功能"),
            ("垃圾文件", "垃圾檔案")
        ]

        return replacements.reduce(converted) { partial, pair in
            partial.replacingOccurrences(of: pair.0, with: pair.1)
        }
    }

    /// Selects the Russian noun form for a non-negative count.
    /// Examples: 1 файл, 2 файла, 5 файлов, 11 файлов, 21 файл.
    public static func russianPlural(
        _ count: Int,
        one: String,
        few: String,
        many: String
    ) -> String {
        let magnitude = count.magnitude
        let mod10 = magnitude % 10
        let mod100 = magnitude % 100

        if mod10 == 1, mod100 != 11 { return one }
        if (2...4).contains(mod10), !(12...14).contains(mod100) { return few }
        return many
    }

    /// Small fallback table for values that are assembled dynamically or flow
    /// through model properties. Most UI strings use the three-argument overload
    /// so every supported translation lives beside the original expression.
    private static let englishFallbacks: [String: String] = [
        "智能扫描": "Smart Scan",
        "系统垃圾": "System Junk",
        "邮件附件": "Mail Attachments",
        "废纸篓": "Trash Bins",
        "恶意软件清理": "Malware Removal",
        "隐私清理": "Privacy",
        "已保存的 Wi-Fi": "Saved Wi-Fi",
        "应用权限": "App Permissions",
        "权限总览": "Permissions",
        "优化": "Optimization",
        "维护": "Maintenance",
        "卸载器": "Uninstaller",
        "扩展": "Extensions",
        "应用更新": "Updater",
        "空间透视": "Space Lens",
        "大文件与旧文件": "Large & Old Files",
        "重复文件": "Duplicates",
        "文件粉碎": "Shredder",
        "开发者清理": "Developer Cleanup",
        "CatDesk 编译缓存": "CatDesk Build Cache",
        "CatDesk 恢复记录": "CatDesk Recovery",
        "CatDesk 安全快照": "CatDesk Safety Snapshots",
        "Codex 缓存": "Codex Cache",
        "Codex 会话": "Codex Sessions",
        "npm 内容缓存": "npm Content Cache",
        "npx 临时安装缓存": "npx Ephemeral Install Cache",
        "pip 缓存": "pip Cache",
        "Homebrew 缓存": "Homebrew Cache",
        "Playwright 浏览器缓存": "Playwright Browser Cache",
        "node-gyp 标头缓存": "node-gyp Header Cache",
        "Cargo 套件缓存": "Cargo Package Cache",
        "Cargo Git 缓存": "Cargo Git Cache",
        "Chrome 应用缓存": "Chrome App Cache",
        "Chrome 本机 AI 模型": "Chrome On-device AI Model",
        "Claude 虚拟机": "Claude VM",
        "Docker 数据": "Docker Data",
        "Alpha Consensus 缓存": "Alpha Consensus Cache",
        "Alpha Consensus 旧运行时": "Alpha Consensus Retired Runtimes",
        "仅在没有编译进程使用时清理；保留生产运行时": "Clean only when no build process is using it; keep the production runtime.",
        "必须先按恢复操作分类与保留期限审查": "Classify recovery operations and apply retention review first.",
        "只清理已证明被取代的快照，禁止整批删除": "Only remove snapshots proven superseded; never bulk-delete them.",
        "关闭 Codex/ChatGPT 后才可清理可重建缓存": "Close Codex/ChatGPT before cleaning rebuildable cache.",
        "会话是状态数据，只报告容量，不作为垃圾自动删除": "Sessions are stateful data; report size only and never auto-delete them as junk.",
        "优先使用 npm 自带清理命令": "Prefer npm's own cleanup command.",
        "无 npm/npx 进程时可重建": "Rebuildable when no npm/npx process is active.",
        "优先使用 pip cache purge": "Prefer pip cache purge.",
        "优先使用 brew cleanup": "Prefer brew cleanup.",
        "关闭 Playwright 工作后可重新下载": "Re-downloadable after Playwright work has stopped.",
        "已下载的 Node 标头可按版本重新取得": "Downloaded Node headers can be fetched again by version.",
        "Rust 编译运行中禁止清理": "Never clean while a Rust build is running.",
        "Chrome 运行中禁止修改其缓存": "Do not modify Chrome cache while Chrome is running.",
        "大型可重新下载模型；关闭 Chrome 后另行确认再清理": "Large re-downloadable model; close Chrome and review separately before cleanup.",
        "虚拟机可能含状态；只报告，不做一键删除": "The VM may contain state; report only, with no one-click deletion.",
        "应通过 Docker 自身清理未使用资源，绝不直接删除卷": "Use Docker's own cleanup for unused resources; never delete volumes directly.",
        "运行中保持不动；关闭后仅清理可重建缓存": "Leave untouched while running; clean only rebuildable cache after exit.",
        "必须保护 current/previous，并按版本保留策略审查": "Protect current/previous releases and review version retention before cleanup.",
        "设置": "Settings",
        "清理": "Cleanup",
        "防护": "Protection",
        "性能": "Performance",
        "应用": "Applications",
        "文件": "Files",
        "全部": "All",
        "未使用": "Unused",
        "第三方": "Third-party",
        "快速": "Quick",
        "平衡": "Balanced",
        "深度": "Deep",
        "开启": "enable",
        "关闭": "disable",
        "压缩包": "Archives",
        "已选择": "Selected",
        "运行中": "Running",
        "未知": "Unknown",
        "进度": "Progress",
        "释放内存": "Free Up RAM",
        "释放可清除空间": "Free Up Purgeable Space",
        "运行维护脚本": "Run Maintenance Scripts",
        "验证启动磁盘": "Verify Startup Disk",
        "加速邮件": "Speed Up Mail",
        "重建启动服务": "Rebuild Launch Services",
        "重建 Spotlight 索引": "Reindex Spotlight",
        "刷新 DNS 缓存": "Flush DNS Cache",
        "精简 Time Machine 快照": "Thin Time Machine Snapshots",
    ]

    private static let russianFallbacks: [String: String] = [
        "智能扫描": "Умное сканирование",
        "系统垃圾": "Системный мусор",
        "邮件附件": "Почтовые вложения",
        "废纸篓": "Корзины",
        "恶意软件清理": "Удаление угроз",
        "隐私清理": "Конфиденциальность",
        "已保存的 Wi-Fi": "Сохранённые сети Wi-Fi",
        "应用权限": "Разрешения приложений",
        "权限总览": "Обзор разрешений",
        "优化": "Оптимизация",
        "维护": "Обслуживание",
        "卸载器": "Удаление приложений",
        "扩展": "Расширения",
        "应用更新": "Обновления",
        "空间透视": "Карта диска",
        "大文件与旧文件": "Большие и старые файлы",
        "重复文件": "Дубликаты",
        "文件粉碎": "Уничтожение файлов",
        "设置": "Настройки",
        "清理": "Очистка",
        "防护": "Защита",
        "性能": "Производительность",
        "应用": "Приложения",
        "文件": "Файлы",
        "全部": "Все",
        "未使用": "Неиспользуемые",
        "第三方": "Сторонние",
        "快速": "Быстро",
        "平衡": "Сбалансированно",
        "深度": "Глубоко",
        "开启": "включить",
        "关闭": "отключить",
        "压缩包": "Архивы",
        "已选择": "Выбрано",
        "运行中": "Работает",
        "未知": "Неизвестно",
        "进度": "Ход выполнения",
        "可用磁盘空间": "Свободное место на диске",
        "GPU 使用率": "Загрузка GPU",
        "内存使用率": "Использование памяти",
        "电池温度": "Температура аккумулятора",
        "菜单栏显示": "Показатель в строке меню",
        "选择应用图标旁显示的紧凑数值。GPU 或电池温度不可用时显示 --。":
            "Выберите компактный показатель рядом со значком приложения. Если данные GPU или температуры аккумулятора недоступны, отображается --.",
        "释放内存": "Освободить оперативную память",
        "释放可清除空间": "Освободить место, доступное для очистки",
        "运行维护脚本": "Запустить скрипты обслуживания",
        "验证启动磁盘": "Проверить загрузочный диск",
        "加速邮件": "Ускорить Почту",
        "重建启动服务": "Перестроить Launch Services",
        "重建 Spotlight 索引": "Перестроить индекс Spotlight",
        "刷新 DNS 缓存": "Очистить кэш DNS",
        "精简 Time Machine 快照": "Проредить снимки Time Machine",
    ]
}
