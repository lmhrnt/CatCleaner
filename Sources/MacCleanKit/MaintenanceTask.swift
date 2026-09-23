import Foundation

/// The set of maintenance tasks CatCleaner knows how to run. Pure data — the
/// actual `Process` execution happens in `MaintenanceExecutor` in the
/// MacClean target.
public enum MaintenanceTask: String, CaseIterable, Identifiable, Sendable {
    case freeUpRAM = "Free Up RAM"
    case freeUpPurgeableSpace = "Free Up Purgeable Space"
    case runMaintenanceScripts = "Run Maintenance Scripts"
    // NOTE: "Repair Disk Permissions" was removed (issue #82). Apple deleted
    // the `diskutil repairPermissions` verb in OS X 10.11 El Capitan, so the
    // task could only ever fail on supported macOS. Repairing system
    // permissions is obsolete under SIP + the sealed System volume, and the
    // home-folder alternative (`diskutil resetUserPermissions`) is undocumented,
    // Apple-deprecated, slow, and ACL-incomplete — not fit for a one-click tool.
    case verifyStartupDisk = "Verify Startup Disk"
    case speedUpMail = "Speed Up Mail"
    case rebuildLaunchServices = "Rebuild Launch Services"
    case reindexSpotlight = "Reindex Spotlight"
    case flushDNSCache = "Flush DNS Cache"
    case thinTimeMachineSnapshots = "Thin Time Machine Snapshots"
    case pruneDocker = "Reclaim Docker Space"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .freeUpRAM: L10n.tr("释放内存", rawValue, "Освободить ОЗУ")
        case .freeUpPurgeableSpace: L10n.tr("释放可清除空间", rawValue, "Освободить место, доступное для очистки")
        case .runMaintenanceScripts: L10n.tr("运行维护脚本", rawValue, "Запустить скрипты обслуживания")
        case .verifyStartupDisk: L10n.tr("验证启动磁盘", rawValue, "Проверить загрузочный диск")
        case .speedUpMail: L10n.tr("加速邮件", rawValue, "Ускорить Почту")
        case .rebuildLaunchServices: L10n.tr("重建启动服务", rawValue, "Перестроить Launch Services")
        case .reindexSpotlight: L10n.tr("重建 Spotlight 索引", rawValue, "Переиндексировать Spotlight")
        case .flushDNSCache: L10n.tr("刷新 DNS 缓存", rawValue, "Очистить кэш DNS")
        case .thinTimeMachineSnapshots: L10n.tr("精简 Time Machine 快照", rawValue, "Сократить снимки Time Machine")
        case .pruneDocker: L10n.tr("回收 Docker 空间", rawValue, "Освободить место Docker")
        }
    }

    public var icon: String {
        switch self {
        case .freeUpRAM: "memorychip"
        case .freeUpPurgeableSpace: "internaldrive"
        case .runMaintenanceScripts: "terminal"
        case .verifyStartupDisk: "checkmark.shield"
        case .speedUpMail: "envelope"
        case .rebuildLaunchServices: "arrow.triangle.2.circlepath"
        case .reindexSpotlight: "magnifyingglass"
        case .flushDNSCache: "network"
        case .thinTimeMachineSnapshots: "clock.arrow.circlepath"
        case .pruneDocker: "shippingbox"
        }
    }

    public var description: String {
        switch self {
        case .freeUpRAM:
            L10n.tr(
                "请求 macOS 清理可回收的非活动与文件缓存内存；系统通常会自行管理这些内存",
                "Ask macOS to purge reclaimable inactive/file-cache memory; macOS normally manages this automatically",
                "Попросить macOS очистить высвобождаемую неактивную память и файловый кэш; обычно система управляет этим автоматически"
            )
        case .freeUpPurgeableSpace:
            L10n.tr(
                "以低优先级请求 Time Machine 精简本地快照，尝试回收一种常见的可清除空间来源；不代表所有可清除空间",
                "Ask Time Machine at low urgency to thin local snapshots, attempting to reclaim one common source of purgeable space; this does not represent all purgeable space",
                "Попросить Time Machine с низким приоритетом сократить локальные снимки, чтобы попытаться освободить один из распространённых источников очищаемого места; это не всё очищаемое пространство"
            )
        case .runMaintenanceScripts:
            L10n.tr("执行 macOS 内置的每日、每周和每月维护任务", "Execute macOS built-in daily, weekly, and monthly maintenance routines", "Запустить встроенные ежедневные, еженедельные и ежемесячные задачи обслуживания macOS")
        case .verifyStartupDisk:
            L10n.tr("检查启动磁盘的文件系统完整性", "Check file system integrity of the boot disk", "Проверить целостность файловой системы загрузочного диска")
        case .speedUpMail:
            L10n.tr(
                "关闭“邮件”后，将当前 Envelope Index 移到垃圾桶并让 Mail 下次启动时重建",
                "After Mail.app is closed, move the current Envelope Index to Trash and let Mail rebuild it on next launch",
                "После закрытия Почты переместить текущий Envelope Index в Корзину и позволить Почте создать его заново при следующем запуске"
            )
        case .rebuildLaunchServices:
            L10n.tr("修复 Finder 的文件类型与应用打开方式数据库", "Repair Finder's file-type-to-application mapping database", "Исправить базу сопоставлений типов файлов и приложений Finder")
        case .reindexSpotlight:
            L10n.tr("重建 Spotlight 搜索索引，提高搜索准确性", "Rebuild the Spotlight search index for improved search accuracy", "Перестроить поисковый индекс Spotlight, чтобы повысить точность поиска")
        case .flushDNSCache:
            L10n.tr("清除本地 DNS 缓存并强制重新解析", "Clear the local DNS cache and force fresh lookups", "Очистить локальный кэш DNS и принудительно обновить разрешение имён")
        case .thinTimeMachineSnapshots:
            L10n.tr("缩减本地 Time Machine 快照以回收磁盘空间", "Reduce local Time Machine snapshot sizes to reclaim disk space", "Уменьшить локальные снимки Time Machine, чтобы освободить место на диске")
        case .pruneDocker:
            L10n.tr("清理未使用的 Docker 镜像、已停止的容器和构建缓存", "Remove unused Docker images, stopped containers, and build cache", "Удалить неиспользуемые образы Docker, остановленные контейнеры и кэш сборки")
        }
    }

    /// How much disruption to expect from running this task.
    ///
    /// `.safe` — runs and finishes; the user's experience doesn't change.
    /// `.advanced` — has side effects the user will notice for minutes/hours
    /// after the task itself "succeeds." Must require explicit consent
    /// before being run; must not be included in bulk "run all" operations.
    public enum Severity: Sendable {
        case safe
        case advanced
    }

    public var severity: Severity {
        switch self {
        // Read-only or trivially reversible — run on click.
        case .verifyStartupDisk,        // read-only check
             .flushDNSCache,            // re-resolves in ms
             .runMaintenanceScripts:    // Apple-blessed periodic routines
            .safe

        // Noticeable/irreversible side effects — require explicit consent.
        case .freeUpRAM,                // drops caches; apps/files may reload and briefly slow down
             .freeUpPurgeableSpace,     // thins local Time Machine snapshots
             .speedUpMail,              // rebuilds Mail envelope index
             .rebuildLaunchServices,    // wipes app/file-type DB — hours of broken double-clicks
             .reindexSpotlight,         // wipes Spotlight index — search dies for hours
             .thinTimeMachineSnapshots, // deletes local TM snapshots
             .pruneDocker:              // removes unused docker images/cache, irreversible
            .advanced
        }
    }

    /// Plain-English description of what the user will EXPERIENCE during
    /// and after this task runs. Shown in the confirmation modal before
    /// an advanced task is dispatched. Always written in the user's voice,
    /// never in implementation language.
    public var sideEffects: String {
        switch self {
        case .freeUpRAM:
            L10n.tr(
                "内存使用数字可能暂时下降，但这不会增加物理 RAM，也不保证持续提速。被清掉的应用与文件缓存需要重新加载，短时间内反而可能变慢；macOS 平时会自动回收这些内存。",
                "Reported memory use may drop temporarily, but this does not add physical RAM or guarantee a lasting speedup. Apps and file data whose caches were purged may need to reload and can briefly become slower; macOS normally reclaims this memory automatically.",
                "Показатель занятой памяти может временно снизиться, но это не добавляет физическую ОЗУ и не гарантирует длительного ускорения. Приложениям и файлам может потребоваться заново загрузить очищенный кэш, поэтому система на короткое время может стать медленнее; обычно macOS сама освобождает эту память."
            )
        case .freeUpPurgeableSpace:
            L10n.tr(
                "会请求 Time Machine 以低优先级删除/精简这台 Mac 的本地快照，因此部分本机还原点可能不再可用；备份磁盘或远端备份不会因此被删除。tmutil 只会尝试回收指定容量，实际回收量可能较少，而且这只针对可清除空间的一种来源。",
                "Time Machine is asked at low urgency to delete/thin local snapshots on this Mac, so some local restore points may no longer be available. Backups on a backup disk or remote destination are not deleted by this command. tmutil only attempts to reclaim the requested amount, may reclaim less, and this targets just one source of purgeable space.",
                "Time Machine с низким приоритетом попытается удалить/сократить локальные снимки на этом Mac, поэтому некоторые локальные точки восстановления могут стать недоступны. Резервные копии на внешнем или удалённом хранилище этой командой не удаляются. tmutil лишь пытается освободить заданный объём, может освободить меньше и затрагивает только один источник очищаемого пространства."
            )
        case .runMaintenanceScripts:
            L10n.tr("通常没有可见影响——这些脚本与 macOS 夜间自动运行的维护脚本相同。", "No visible effect — these are the same scripts macOS runs on its own overnight.", "Обычно без заметных последствий — это те же скрипты обслуживания, которые macOS запускает ночью.")
        case .verifyStartupDisk:
            L10n.tr("会产生几分钟磁盘活动。该操作为只读，无论结果如何都不会更改磁盘内容。", "A few minutes of disk activity. Read-only — nothing on disk is changed regardless of the outcome.", "Несколько минут активности диска. Операция выполняется только для чтения — содержимое диска не изменится независимо от результата.")
        case .speedUpMail:
            L10n.tr(
                "必须先完全退出“邮件”。CatCleaner 会把当前 Mail 版本的 Envelope Index、WAL/SHM 等索引文件移到 macOS 垃圾桶，而不是永久删除；下次启动“邮件”会从头重建索引。重建完成前，搜索和未读数可能暂时不准确（大型邮箱通常需 10–30 分钟）。",
                "Mail.app must be fully quit first. CatCleaner moves the current Mail version's Envelope Index and WAL/SHM companions to the macOS Trash rather than deleting them permanently; Mail rebuilds the index from scratch on next launch. Search and unread counts may be temporarily inaccurate until rebuilding finishes (typically 10–30 minutes on a large mailbox).",
                "Сначала полностью закройте Почту. CatCleaner переместит Envelope Index текущей версии Почты и файлы WAL/SHM в Корзину macOS вместо безвозвратного удаления; при следующем запуске Почта создаст индекс заново. До завершения поиска и счётчики непрочитанных сообщений могут быть временно неточными (обычно 10–30 минут для большого ящика)."
            )
        case .rebuildLaunchServices:
            L10n.tr("macOS 的“哪类文件由哪个应用打开”数据库会被清除并重建。完成前（通常数小时），双击文件可能失败或打开错误应用，默认应用设置可能重置，Spotlight 启动应用也可能不可用。重启可加快恢复。", "macOS's database of \"which app opens which file type\" is erased and rebuilt. Until it finishes (often several hours), double-clicking files may fail or open the wrong app, default-app settings may reset, and launching apps via Spotlight may not work. A reboot speeds this up.", "База macOS, определяющая, каким приложением открывается каждый тип файлов, будет удалена и создана заново. До завершения (часто несколько часов) двойной щелчок по файлам может не работать или открывать неверное приложение, настройки приложений по умолчанию могут сброситься, а запуск приложений через Spotlight — не работать. Перезагрузка ускорит восстановление.")
        case .reindexSpotlight:
            L10n.tr("Spotlight 的整个搜索索引会被清除并重建。数小时内 Spotlight 搜索可能返回空结果（主目录越大耗时越久），系统搜索和智能文件夹也会受影响。", "Spotlight's entire search index is erased and rebuilt. Spotlight search will return empty results for several hours (longer for large home directories). System search and Smart Folders are affected too.", "Весь поисковый индекс Spotlight будет удалён и создан заново. Несколько часов поиск Spotlight может возвращать пустые результаты (дольше для больших домашних папок). Системный поиск и смарт-папки также будут затронуты.")
        case .flushDNSCache:
            L10n.tr("浏览器和其他网络应用会在下次请求时重新解析主机名，影响通常只有毫秒级。", "Browsers and other network apps re-resolve hostnames on next request — milliseconds of impact.", "Браузеры и другие сетевые приложения заново определят адреса хостов при следующем запросе — это займёт миллисекунды.")
        case .thinTimeMachineSnapshots:
            L10n.tr("会删除本地 Time Machine 快照以释放空间。远程或备份盘上的快照不受影响，你仍可从 Time Machine 备份恢复。", "Local Time Machine snapshots are deleted to free disk space. Remote/backup-drive snapshots are unaffected; you can still restore from the Time Machine backup itself.", "Локальные снимки Time Machine будут удалены для освобождения места. Снимки на удалённых дисках и дисках резервного копирования не затрагиваются; восстановление из самой резервной копии Time Machine останется доступно.")
        case .pruneDocker:
            L10n.tr("运行 docker system prune，删除未使用的镜像、已停止的容器、未使用的网络和构建缓存。此操作不可撤销（不会进入废纸篓）。正在运行的容器、使用中的镜像和命名卷不受影响，磁盘映像 Docker.raw 也不会被直接删除。", "Runs docker system prune, removing unused images, stopped containers, unused networks, and build cache. This is irreversible (it does not go to the Trash). Running containers, in-use images, and named volumes are untouched, and the Docker.raw disk image is never deleted directly.", "Будет запущена команда docker system prune, которая удалит неиспользуемые образы, остановленные контейнеры, неиспользуемые сети и кэш сборки. Операция необратима (данные не попадают в Корзину). Работающие контейнеры, используемые образы и именованные тома не затрагиваются; образ диска Docker.raw напрямую не удаляется.")
        }
    }

    /// True for tasks whose command needs root (purge, periodic, …). The
    /// executor runs these via the standard macOS admin-auth prompt
    /// (`do shell script … with administrator privileges`) so they actually
    /// execute, instead of failing as a plain unprivileged `Process`.
    public var requiresAdmin: Bool {
        switch self {
        // Need root to actually run. `tmutil thinlocalsnapshots` and
        // `mdutil -E` both silently fail without it (issue #82: reindex was
        // wrongly unprivileged, which is the report's likely second error).
        case .freeUpRAM, .freeUpPurgeableSpace, .runMaintenanceScripts,
             .reindexSpotlight, .thinTimeMachineSnapshots:
            true
        // `diskutil verifyVolume /` runs read-only without root, so don't
        // burden the user with a password prompt for it (issue #82).
        case .verifyStartupDisk, .speedUpMail, .rebuildLaunchServices,
             .flushDNSCache, .pruneDocker:
            false
        }
    }

    /// The system executable + arguments that implement this task.
    /// Pure data — the MacClean target's `MaintenanceExecutor` uses this
    /// to invoke `Process`. Tasks that aren't a simple command (e.g., Mail
    /// reindex which deletes a specific file) return `nil`.
    public var systemCommand: (executable: String, arguments: [String])? {
        switch self {
        case .freeUpRAM:
            ("/usr/sbin/purge", [])
        case .freeUpPurgeableSpace:
            // Thin low-urgency (1) local snapshots to actually reclaim
            // purgeable space. The old `diskutil apfs listSnapshots /` only
            // listed them and freed nothing (issue #82). Aggressive thinning
            // lives in `thinTimeMachineSnapshots` (urgency 4).
            ("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "1"])
        case .runMaintenanceScripts:
            ("/usr/sbin/periodic", ["daily", "weekly", "monthly"])
        case .verifyStartupDisk:
            ("/usr/sbin/diskutil", ["verifyVolume", "/"])
        case .speedUpMail:
            nil
        case .rebuildLaunchServices:
            ("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
             ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"])
        case .reindexSpotlight:
            ("/usr/bin/mdutil", ["-E", "/"])
        case .flushDNSCache:
            ("/usr/bin/dscacheutil", ["-flushcache"])
        case .thinTimeMachineSnapshots:
            ("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "4"])
        case .pruneDocker:
            nil
        }
    }

    /// Where the Docker CLI may live, in priority order. Pure data so the
    /// resolver is unit-testable.
    public static let dockerCandidatePaths = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
    ]

    /// First candidate path for which `existing` is true, or nil if Docker
    /// isn't installed. `existing` is injected so tests don't touch the disk.
    public static func resolveDockerPath(existing: (String) -> Bool) -> String? {
        dockerCandidatePaths.first(where: existing)
    }

    /// Whether this task's `systemCommand` executable is present on the running
    /// system. `existing` is injected so tests don't touch the disk, matching
    /// `resolveDockerPath(existing:)`.
    ///
    /// The paths in `systemCommand` are absolute and hard-coded, and Apple does
    /// remove them: `/usr/sbin/periodic` is gone on macOS 26 (issue #129), just
    /// as `diskutil repairPermissions` went earlier (issue #82). Without this
    /// check the task runs anyway and the user sees the raw shell failure —
    /// `/bin/sh: /usr/sbin/periodic: No such file or directory` — which reads
    /// like a bug in the app rather than a tool the OS no longer ships.
    ///
    /// Tasks with no `systemCommand` (Mail reindex, Docker prune) are handled
    /// by their own code paths and report `true` here.
    public func systemCommandIsAvailable(existing: (String) -> Bool) -> Bool {
        guard let command = systemCommand else { return true }
        return existing(command.executable)
    }
}
