import Foundation
import AppKit
import MacCleanKit

public struct MaintenanceModule: ScanModule {
    public let id = "maintenance"
    public var name: String { L10n.tr("维护", "Maintenance", "Обслуживание") }
    public let category = ModuleCategory.performance

    public init() {}

    public func scan() async -> [ScanResult] { [] }
}

// MARK: - Maintenance Executor
//
// `MaintenanceTask` (the enum + descriptions + system commands) lives in
// MacCleanKit. This actor runs those commands: admin ones through in-process
// AppleScript (password cached per process, issue #143), the rest via Process.

public actor MaintenanceExecutor {
    public struct TaskResult: Sendable {
        public let task: MaintenanceTask
        public let success: Bool
        public let output: String
        public let error: String?
    }

    private let privilegedRunner: any PrivilegedShellRunning
    private let commandExists: @Sendable (String) -> Bool
    private let mailRoot: URL
    private let mailIsRunning: @Sendable () -> Bool
    private let trashItem: @Sendable (URL) throws -> Void
    private let safetyGuard = SafetyGuard()

    public init() {
        self.init(
            privilegedRunner: AppleScriptPrivilegedRunner(),
            commandExists: { FileManager.default.isExecutableFile(atPath: $0) },
            mailRoot: MCConstants.mailData,
            mailIsRunning: {
                NSWorkspace.shared.runningApplications.contains {
                    $0.bundleIdentifier == "com.apple.mail" && !$0.isTerminated
                }
            },
            trashItem: { url in
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        )
    }

    init(
        privilegedRunner: any PrivilegedShellRunning,
        commandExists: @escaping @Sendable (String) -> Bool,
        mailRoot: URL = MCConstants.mailData,
        mailIsRunning: @escaping @Sendable () -> Bool = {
            NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == "com.apple.mail" && !$0.isTerminated
            }
        },
        trashItem: @escaping @Sendable (URL) throws -> Void = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        self.privilegedRunner = privilegedRunner
        self.commandExists = commandExists
        self.mailRoot = mailRoot.standardizedFileURL
        self.mailIsRunning = mailIsRunning
        self.trashItem = trashItem
    }

    public func execute(_ task: MaintenanceTask) async -> TaskResult {
        if case .speedUpMail = task { return await reindexMail() }
        if case .pruneDocker = task { return await pruneDocker() }

        guard let (command, args) = task.systemCommand else {
            return TaskResult(task: task, success: false, output: "",
                              error: L10n.tr("该任务没有可执行的系统命令", "Task has no system command", "Для этой задачи нет системной команды"))
        }

        // Report a missing system tool instead of running it and surfacing the
        // raw shell error. Apple removed `/usr/sbin/periodic` in macOS 26, so
        // Run Maintenance Scripts failed with
        // `/bin/sh: /usr/sbin/periodic: No such file or directory` (issue #129)
        // — which reads as an app bug rather than a tool the OS dropped. Gating
        // here rather than per-task covers every hard-coded path in
        // `systemCommand`, the same way `pruneDocker` already gates on the
        // Docker CLI. Checked unprivileged, so an admin task fails before the
        // password prompt rather than after it.
        guard task.systemCommandIsAvailable(existing: commandExists) else {
            return TaskResult(
                task: task, success: false, output: "",
                error: L10n.tr("\(command) 在当前 macOS 版本中不可用，无法执行该任务。",
                               "\(command) isn't available on this version of macOS, so this task can't run.",
                               "\(command) недоступно в этой версии macOS, поэтому эту задачу нельзя выполнить."))
        }

        if task.requiresAdmin {
            return await runAdminProcess(task: task, command: command, args: args)
        }
        return await runProcess(task: task, command: command, args: args)
    }

    /// Run a root-requiring command via the standard macOS admin-auth prompt
    /// (`do shell script … with administrator privileges`). Executed
    /// in-process so successive tasks reuse the cached credentials (issue
    /// #143) — spawning `/usr/bin/osascript` each time could not. The
    /// command strings come from the fixed `MaintenanceTask` enum (never
    /// user input).
    private func runAdminProcess(task: MaintenanceTask, command: String, args: [String]) async -> TaskResult {
        let shell = MaintenanceShell.commandLine(command, args)
        let result = await privilegedRunner.run(commandLine: shell)

        if result.success {
            return TaskResult(task: task, success: true, output: result.output, error: nil)
        }

        let err = result.error ?? ""
        if MaintenanceShell.isAuthorizationCancelled(err, errorNumber: result.errorNumber) {
            return TaskResult(task: task, success: false, output: "",
                              error: L10n.tr("已取消——未授予管理员权限。", "Cancelled — administrator access was not granted.", "Отменено: не предоставлены права администратора."))
        }
        // Strip AppleScript's "1:92: execution error: … (1)" wrapper so the
        // user sees the real underlying message (issue #82).
        return TaskResult(task: task, success: false, output: "",
                          error: MaintenanceShell.humanReadableError(err))
    }

    private func runProcess(task: MaintenanceTask, command: String, args: [String]) async -> TaskResult {
        await Task.detached(priority: .utility) {
            do {
                let result = try ProcessOutputCapture.run(
                    executable: URL(fileURLWithPath: command),
                    arguments: args
                )
                return TaskResult(
                    task: task,
                    success: result.exitCode == 0,
                    output: result.stdout,
                    error: result.stderr.isEmpty ? nil : result.stderr
                )
            } catch {
                return TaskResult(
                    task: task,
                    success: false,
                    output: "",
                    error: error.localizedDescription
                )
            }
        }.value
    }

    private func reindexMail() async -> TaskResult {
        guard !mailIsRunning() else {
            return TaskResult(
                task: .speedUpMail,
                success: false,
                output: "",
                error: L10n.tr(
                    "请先完全退出“邮件”App，再重建索引。",
                    "Quit Mail.app completely before rebuilding its index.",
                    "Полностью закройте Почту перед перестроением индекса."
                )
            )
        }

        let candidates = Self.mailIndexCandidates(
            mailRoot: mailRoot,
            fileManager: .default
        )

        guard !candidates.isEmpty else {
            return TaskResult(
                task: .speedUpMail,
                success: true,
                output: L10n.tr(
                    "未找到可重建的邮件 Envelope Index。",
                    "No rebuildable Mail Envelope Index was found.",
                    "Индекс Envelope Index для перестроения не найден."
                ),
                error: nil
            )
        }

        do {
            try safetyGuard.validateDeletion(paths: candidates)
        } catch {
            return TaskResult(
                task: .speedUpMail,
                success: false,
                output: "",
                error: error.localizedDescription
            )
        }

        // Fresh owner gate immediately before the first mutation.
        guard !mailIsRunning() else {
            return TaskResult(
                task: .speedUpMail,
                success: false,
                output: "",
                error: L10n.tr(
                    "“邮件”App 在确认后又启动了，因此已取消索引重建。",
                    "Mail.app started after confirmation, so the index rebuild was cancelled.",
                    "Почта была запущена после подтверждения, поэтому перестроение индекса отменено."
                )
            )
        }

        var moved = 0
        var errors: [String] = []

        for url in candidates {
            do {
                try trashItem(url)
                moved += 1
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        guard errors.isEmpty else {
            return TaskResult(
                task: .speedUpMail,
                success: false,
                output: moved > 0
                    ? L10n.tr(
                        "已有 \(moved) 个索引文件移到垃圾桶。",
                        "\(moved) index files were moved to Trash before the failure.",
                        "До ошибки в Корзину перемещено файлов индекса: \(moved)."
                    )
                    : "",
                error: errors.joined(separator: "\n")
            )
        }

        return TaskResult(
            task: .speedUpMail,
            success: true,
            output: L10n.tr(
                "已将 \(moved) 个邮件索引文件移到垃圾桶。下次启动“邮件”时会自动重建。",
                "Moved \(moved) Mail index files to Trash. Mail will rebuild them on next launch.",
                "Файлов индекса Почты перемещено в Корзину: \(moved). При следующем запуске Почта создаст их заново."
            ),
            error: nil
        )
    }

    /// Returns the index family from the highest Mail version directory that
    /// actually contains a rebuildable Envelope Index. Older V* trees are left
    /// untouched so stale migrations/backups do not get modified incidentally.
    static func mailIndexCandidates(
        mailRoot: URL,
        fileManager: FileManager
    ) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: mailRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let versions: [(number: Int, url: URL)] = entries.compactMap { url in
            let name = url.lastPathComponent
            guard name.first == "V",
                  let number = Int(name.dropFirst()),
                  let values = try? url.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                  ),
                  values.isDirectory == true,
                  values.isSymbolicLink != true
            else {
                return nil
            }
            return (number, url)
        }
        .sorted { $0.number > $1.number }

        let names = [
            "Envelope Index",
            "Envelope Index-shm",
            "Envelope Index-wal",
            "Envelope Index-journal",
        ]

        for version in versions {
            let mailData = version.url.appending(path: "MailData")
            guard let values = try? mailData.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ),
            values.isDirectory == true,
            values.isSymbolicLink != true
            else {
                continue
            }

            let candidates = names.compactMap { name -> URL? in
                let url = mailData.appending(path: name)
                guard let itemValues = try? url.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                ),
                itemValues.isRegularFile == true,
                itemValues.isSymbolicLink != true
                else {
                    return nil
                }
                return url
            }

            if candidates.contains(where: { $0.lastPathComponent == "Envelope Index" }) {
                return candidates
            }
        }

        return []
    }

    /// Reclaim Docker space via `docker system prune -f`. Gated on the Docker
    /// CLI existing (resolved from MaintenanceTask.dockerCandidatePaths); if it
    /// isn't installed we report that instead of failing obscurely. Runs as the
    /// user (the CLI talks to Docker Desktop's daemon), so no admin prompt.
    private func pruneDocker() async -> TaskResult {
        guard let docker = MaintenanceTask.resolveDockerPath(existing: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            return TaskResult(
                task: .pruneDocker, success: false, output: "",
                error: L10n.tr("未找到 Docker 命令行工具。请确认已安装 Docker Desktop。",
                               "Docker CLI not found. Make sure Docker Desktop is installed.",
                "Команда Docker не найдена. Убедитесь, что Docker Desktop установлен."))
        }
        return await runProcess(task: .pruneDocker, command: docker, args: ["system", "prune", "-f"])
    }
}
