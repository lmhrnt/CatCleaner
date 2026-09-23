import SwiftUI
import MacCleanKit

struct ShredderView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var filesToShred: [URL] = []
    @State private var eraseMode: SecureEraser.EraseMode = .standard
    @State private var isProcessing = false
    @State private var result: SecureEraser.EraseResult?

    private let eraser = SecureEraser()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("文件粉碎", "Shredder", "Уничтожение файлов"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(L10n.tr(
                        "提供垃圾桶、永久删除与覆写后删除；SSD/APFS 上的覆写不保证物理区块不可恢复",
                        "Trash, permanent delete, or overwrite-then-delete. SSD/APFS overwrites cannot guarantee physical blocks are unrecoverable.",
                        "Корзина, немедленное удаление или перезапись перед удалением. На SSD/APFS перезапись не гарантирует стирание всех прежних физических блоков."
                    ))
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                Spacer()
            }
            .padding(20)

            Spacer()

            if let result {
                VStack(spacing: 16) {
                    Image(systemName: result.errors.isEmpty
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(result.errors.isEmpty ? Color.primary : Color.orange)
                    Text(L10n.tr(
                        "已处理 \(result.erasedCount) 个文件",
                        "\(result.erasedCount) files processed",
                        "Обработано файлов: \(result.erasedCount)"
                    ))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(FileSizeFormatter.format(result.totalSize))
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.7))

                    if let firstError = result.errors.first?.1 {
                        Text(firstError)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .textSelection(.enabled)

                        if result.errors.count > 1 {
                            Text(L10n.tr(
                                "以及另外 \(result.errors.count - 1) 个错误",
                                "And \(result.errors.count - 1) more error\(result.errors.count == 2 ? "" : "s")",
                                "И ещё \(result.errors.count - 1) \(L10n.russianPlural(result.errors.count - 1, one: "ошибка", few: "ошибки", many: "ошибок"))"))
                                .font(.system(size: 12))
                                .foregroundStyle(.primary.opacity(0.6))
                        }
                    }

                    Button(L10n.tr("完成", "Done", "Готово")) {
                        self.result = nil
                        filesToShred = []
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
            } else if isProcessing {
                ProgressView(L10n.tr("正在处理文件...", "Processing files...", "Обработка файлов..."))
                    .foregroundStyle(.primary)
                    .tint(.primary)
            } else if filesToShred.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "scissors")
                        .font(.system(size: 50))
                        .foregroundStyle(.primary.opacity(0.5))

                    Text(L10n.tr("将文件拖放到此处进行粉碎", "Drop files here to shred them", "Перетащите сюда файлы для уничтожения"))
                        .font(.system(size: 16))
                        .foregroundStyle(.primary.opacity(0.6))

                    Button(L10n.tr("选择文件", "Select Files", "Выбрать файлы")) {
                        selectFiles()
                    }
                    .buttonStyle(SuperEllipseButtonStyle(
                        gradient: ModuleTheme.files.gradient,
                        size: CGSize(width: 140, height: 44)
                    ))

                    // Erase mode picker
                    Picker(L10n.tr("模式", "Mode", "Режим"), selection: $eraseMode) {
                        Text(L10n.tr("移到废纸篓", "Move to Trash", "В Корзину")).tag(SecureEraser.EraseMode.standard)
                        Text(L10n.tr("永久删除", "Permanent Delete", "Безвозвратно")).tag(SecureEraser.EraseMode.permanent)
                        Text(L10n.tr("覆写后删除", "Overwrite then Delete", "Перезаписать и удалить")).tag(SecureEraser.EraseMode.secure)
                    }
                    .pickerStyle(.segmented)
                    // Hidden visually, kept for VoiceOver. Rendered inline,
                    // the label gets width-starved by the fixed 360pt frame
                    // (segments consume it all) and wraps one letter per
                    // line into a vertical "M o d e".
                    .labelsHidden()
                    .frame(width: 360)
                    .padding(.top, 8)
                    eraseModeNotice
                }
            } else {
                VStack(spacing: 16) {
                    Text(L10n.tr("已选择 \(filesToShred.count) 个文件", "\(filesToShred.count) files selected", "\(L10n.russianPlural(filesToShred.count, one: "Выбран", few: "Выбрано", many: "Выбрано")) \(filesToShred.count) \(L10n.russianPlural(filesToShred.count, one: "файл", few: "файла", many: "файлов"))"))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    List(filesToShred, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc")
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                filesToShred.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.inset)
                    .frame(maxHeight: 200)
                    .background {
                        if removeBackgroundColors { Color.clear }
                        else { Rectangle().fill(.ultraThinMaterial) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 40)

                    HStack(spacing: 6) {
                        Image(systemName: modeIcon)
                        Text(modeTitle)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                    eraseModeNotice

                    Button(L10n.tr("执行", "Execute", "Выполнить")) {
                        shred()
                    }
                    .buttonStyle(SuperEllipseButtonStyle(
                        gradient: LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing),
                        size: CGSize(width: 140, height: 44)
                    ))
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var eraseModeNotice: some View {
        switch eraseMode {
        case .standard:
            EmptyView()

        case .permanent:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(L10n.tr(
                    "永久删除会绕过垃圾桶，无法从垃圾桶恢复；这不等于 SSD 实体安全抹除。",
                    "Permanent delete bypasses Trash and cannot be restored from it. This is not the same as secure physical erasure on an SSD.",
                    "Безвозвратное удаление обходит Корзину и не позволяет восстановить файл из неё. Это не означает гарантированное физическое стирание на SSD."
                ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 20)

        case .secure:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(L10n.tr(
                    "APFS/SSD 采用写入时复制、磨损平均与控制器重映射；此模式只会覆写当前逻辑文件内容一次，再删除文件，不能证明所有旧 NAND 区块已被抹除。高敏感资料应使用 FileVault。",
                    "APFS/SSDs use copy-on-write, wear leveling, and controller remapping. This mode overwrites the current logical file once, then deletes it; it cannot prove all prior NAND blocks were erased. Use FileVault for sensitive data.",
                    "APFS/SSD используют copy-on-write, wear leveling и переназначение блоков. Режим один раз перезаписывает текущее логическое содержимое и удаляет файл, но не доказывает стирание всех старых NAND-блоков. Для чувствительных данных используйте FileVault."
                ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 20)
        }
    }

    private var modeTitle: String {
        switch eraseMode {
        case .standard:
            L10n.tr("移到垃圾桶", "Move to Trash", "В Корзину")
        case .permanent:
            L10n.tr("永久删除", "Permanent Delete", "Безвозвратно")
        case .secure:
            L10n.tr("覆写后删除", "Overwrite then Delete", "Перезаписать и удалить")
        }
    }

    private var modeIcon: String {
        switch eraseMode {
        case .standard: "trash"
        case .permanent: "trash.slash"
        case .secure: "externaldrive.badge.xmark"
        }
    }

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            filesToShred = panel.urls
        }
    }

    private func shred() {
        isProcessing = true
        Task {
            result = await eraser.erase(urls: filesToShred, mode: eraseMode)
            isProcessing = false
        }
    }
}
