import SwiftUI
import MacCleanKit

struct LargeOldFilesView: View {
    @Environment(AppState.self) private var appState
    @State private var results: [ScanResult] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanPhase = ""
    @State private var scanComplete = false
    @State private var completion: CleanSummary?
    @State private var cleaning: CleaningEngine.Progress?
    @State private var cleanTask: Task<Void, Never>?

    var body: some View {
        ModuleContainerView(
            title: L10n.tr("大文件与旧文件", "Large & Old Files", "Большие и старые файлы"),
            subtitle: L10n.tr(
                "找出 50 MB 以上的大型文件，并按媒体、套件、虚拟机、iOS 备份等分类",
                "Find files over 50 MB and review them by media, package, VM, iOS backup, and other categories",
                "Находите файлы больше 50 МБ и просматривайте их по категориям: медиа, пакеты, ВМ, резервные копии iOS и другие"
            ),
            theme: .files,
            emptyMessage: L10n.tr("未找到大文件或旧文件", "No large or old files found", "Большие или старые файлы не найдены"),
            results: results,
            selectedItems: $selectedItems,
            isScanning: isScanning,
            scanProgress: scanProgress,
            scanPhase: scanPhase,
            scanComplete: scanComplete,
            completion: completion,
            cleaning: cleaning,
            onScan: scan,
            onClean: clean,
            onCancelClean: { cleanTask?.cancel() },
            onReset: reset,
            resultsContent: {
                AnyView(
                    LargeFileCategoryResultsView(
                        results: results,
                        selectedItems: $selectedItems
                    )
                )
            }
        )
        .onAppear {
            if let e = appState.scanResultsStore.entry(for: .largeOldFiles) {
                results = e.results
                selectedItems = e.selection
                scanComplete = e.scanComplete
            }
        }
        .onDisappear {
            appState.scanResultsStore.save(
                results: results,
                selection: selectedItems,
                scanComplete: scanComplete,
                for: .largeOldFiles
            )
        }
    }

    private func scan() {
        isScanning = true
        scanComplete = false
        scanProgress = 0
        results = []
        selectedItems = []
        Task {
            scanPhase = L10n.tr(
                "正在扫描个人目录...",
                "Scanning home directory...",
                "Сканирование домашней папки..."
            )
            scanProgress = 0.15

            let module = LargeOldFilesModule()
            let scannedResults = await module.scan()
            guard !Task.isCancelled else {
                isScanning = false
                return
            }

            scanPhase = L10n.tr(
                "正在整理结果...",
                "Grouping results...",
                "Группировка результатов..."
            )
            scanProgress = 0.9
            results = scannedResults
            scanProgress = 1.0

            isScanning = false
            scanComplete = true
        }
    }

    private func clean() {
        let preCleanSelectedCount = selectedItems.count
        cleaning = CleaningEngine.Progress(
            totalItems: preCleanSelectedCount,
            processedItems: 0, removedSoFar: 0, freedBytesSoFar: 0
        )
        cleanTask = Task {
            let result = await CleanActions.executeUserClean(
                results: results,
                selectedItems: selectedItems,
                engine: appState.cleaningEngine,
                onProgress: { progress in
                    Task { @MainActor in cleaning = progress }
                }
            )
            cleaning = nil
            completion = CleanSummary(
                selectedCount: preCleanSelectedCount,
                removedCount: result.removedCount,
                freedBytes: result.freedBytes,
                errorMessages: result.errors.map(\.error)
            )
        }
    }

    private func reset() {
        results = []; selectedItems = []; completion = nil; cleaning = nil; cleanTask = nil; scanComplete = false
    }
}
