import XCTest

@testable import MacCleanKit

final class LocalizationTests: AppLanguageTestCase {
    func testRussianIsSelectableAndUsesRussianLocale() {
        XCTAssertTrue(AppLanguage.allCases.contains(.ru))
        XCTAssertEqual(AppLanguage.ru.rawValue, "ru")
        XCTAssertEqual(AppLanguage.ru.localeIdentifier, "ru")
        XCTAssertEqual(AppLanguage.ru.pickerLabel, "Русский")
    }

    func testPreferredLanguageRecognizesRussianIdentifiers() {
        XCTAssertEqual(AppLanguage.preferredLanguage(for: "ru-RU"), .ru)
        XCTAssertEqual(AppLanguage.preferredLanguage(for: "ru_KZ"), .ru)
        XCTAssertEqual(AppLanguage.preferredLanguage(for: "RU_ru"), .ru)
        XCTAssertEqual(AppLanguage.preferredLanguage(for: "zh-Hans-CN"), .zhHans)
        XCTAssertEqual(AppLanguage.preferredLanguage(for: "en-US"), .en)
        XCTAssertEqual(AppLanguage.preferredLanguage(for: "de-DE"), .en)
    }

    func testTraditionalChineseTaiwanIsSelectableAndUsesTaiwanLocale() {
        XCTAssertTrue(AppLanguage.selectableCases.contains(.zhHantTW))
        XCTAssertFalse(AppLanguage.selectableCases.contains(.en))
        XCTAssertEqual(AppLanguage.fallback, .zhHantTW)
        XCTAssertEqual(AppLanguage.zhHantTW.rawValue, "zh-Hant-TW")
        XCTAssertEqual(AppLanguage.zhHantTW.localeIdentifier, "zh-Hant-TW")
        XCTAssertEqual(AppLanguage.zhHantTW.pickerLabel, "繁體中文（台灣）")
    }

    func testTaiwaneseChineseProductDefaultMigratesNewAndEnglishPreferences() {
        SharedAppState.defaults.removeObject(forKey: AppLanguage.defaultsKey)
        UserDefaults.standard.removeObject(forKey: AppLanguage.defaultsKey)
        AppLanguage.prepareTaiwaneseChineseProductDefault()
        XCTAssertEqual(AppLanguage.current, .zhHantTW)

        AppLanguage.current = .en
        AppLanguage.prepareTaiwaneseChineseProductDefault()
        XCTAssertEqual(AppLanguage.current, .zhHantTW)
        XCTAssertEqual(AppLanguage.productLanguage(.en), .zhHantTW)
        XCTAssertEqual(AppLanguage.productLanguage(.zhHans), .zhHans)
    }

    func testPreferredLanguageRecognizesTraditionalChineseIdentifiers() {
        XCTAssertEqual(AppLanguage.preferredLanguage(for: "zh-TW"), .zhHantTW)
        XCTAssertEqual(AppLanguage.preferredLanguage(for: "zh_Hant_TW"), .zhHantTW)
        XCTAssertEqual(AppLanguage.preferredLanguage(for: "zh-HK"), .zhHantTW)
        XCTAssertEqual(AppLanguage.preferredLanguage(for: "zh-MO"), .zhHantTW)
        XCTAssertEqual(AppLanguage.preferredLanguage(for: "zh-Hans-CN"), .zhHans)
        XCTAssertEqual(AppLanguage.preferredLanguage(for: "zh-CN"), .zhHans)
    }

    func testTraditionalChineseTaiwanTerminology() {
        AppLanguage.current = .zhHantTW
        XCTAssertEqual(L10n.tr("设置", "Settings", "Настройки"), "設定")
        XCTAssertEqual(L10n.tr("系统缓存", "System Cache", "Системный кэш"), "系統快取")
        XCTAssertEqual(L10n.tr("卸载器", "Uninstaller", "Деинсталлятор"), "解除安裝工具")
        XCTAssertEqual(L10n.tr("废纸篓", "Trash", "Корзина"), "垃圾桶")
        XCTAssertEqual(L10n.tr("大型文件", "Large Files", "Большие файлы"), "大型檔案")
        XCTAssertEqual(L10n.tr("内存", "Memory", "Память"), "記憶體")
        XCTAssertEqual(L10n.tr("磁盘", "Disk", "Диск"), "磁碟")
        XCTAssertEqual(L10n.tr("智能扫描", "Smart Scan"), "智慧掃描")
        XCTAssertEqual(L10n.tr("界面语言", "Interface Language"), "介面語言")
        XCTAssertEqual(L10n.tr("菜单栏显示", "Menu bar display"), "選單列顯示")
        XCTAssertEqual(L10n.tr("用户缓存", "User caches"), "使用者快取")
        XCTAssertEqual(L10n.tr("正在加载数据", "Loading data"), "正在載入資料")
        XCTAssertEqual(L10n.tr("查看服务器", "View server"), "檢視伺服器")
        XCTAssertEqual(L10n.tr("处理器", "CPU"), "處理器")
        XCTAssertEqual(L10n.tr("图形处理器", "GPU"), "圖形處理器")
        XCTAssertEqual(L10n.tr("实时系统状态", "Live system stats"), "即時系統狀態")
        XCTAssertEqual(L10n.tr("屏幕顶部", "Top of screen"), "螢幕頂部")
        XCTAssertEqual(L10n.tr("正在读取进程", "Reading processes"), "正在讀取行程")
        XCTAssertEqual(L10n.tr("互联网插件", "Internet Plug-Ins"), "網際網路插件")
        XCTAssertEqual(L10n.tr("集成开发环境", "IDE"), "整合式開發環境")
        XCTAssertEqual(L10n.tr("人工智能工具", "AI tools"), "人工智慧工具")
    }

    func testThreeLanguageTranslation() {
        AppLanguage.current = .ru
        XCTAssertEqual(L10n.tr("设置", "Settings", "Настройки"), "Настройки")

        AppLanguage.current = .en
        XCTAssertEqual(L10n.tr("设置", "Settings", "Настройки"), "Settings")

        AppLanguage.current = .zhHans
        XCTAssertEqual(L10n.tr("设置", "Settings", "Настройки"), "设置")
    }

    func testRussianDynamicFallbackTranslation() {
        AppLanguage.current = .ru
        XCTAssertEqual(L10n.tr("设置"), "Настройки")
        XCTAssertEqual(L10n.tr("未知键"), "未知键")
    }

    func testUntranslatedStringFallsBackToEnglishInRussian() {
        AppLanguage.current = .ru
        XCTAssertEqual(L10n.tr("新功能", "New feature"), "New feature")
    }

    func testKnownTwoArgumentStringUsesRussianFallback() {
        AppLanguage.current = .ru

        let cases = [
            ("可用磁盘空间", "Free disk space", "Свободное место на диске"),
            ("GPU 使用率", "GPU usage", "Загрузка GPU"),
            ("内存使用率", "Memory usage", "Использование памяти"),
            ("电池温度", "Battery temperature", "Температура аккумулятора"),
            ("菜单栏显示", "Menu bar display", "Показатель в строке меню"),
            (
                "选择应用图标旁显示的紧凑数值。GPU 或电池温度不可用时显示 --。",
                "Choose the compact value shown next to the app icon. Unavailable GPU or battery sensors appear as --.",
                "Выберите компактный показатель рядом со значком приложения. Если данные GPU или температуры аккумулятора недоступны, отображается --."
            ),
        ]

        for (chinese, english, russian) in cases {
            XCTAssertEqual(L10n.tr(chinese, english), russian)
        }
    }

    func testRussianPluralRules() {
        let cases: [(Int, String)] = [
            (0, "файлов"), (1, "файл"), (2, "файла"), (4, "файла"), (5, "файлов"),
            (11, "файлов"), (12, "файлов"), (14, "файлов"), (21, "файл"),
            (22, "файла"), (25, "файлов"), (101, "файл"), (111, "файлов"),
        ]

        for (count, expected) in cases {
            XCTAssertEqual(
                L10n.russianPlural(count, one: "файл", few: "файла", many: "файлов"),
                expected,
                "Unexpected Russian plural for \(count)"
            )
        }
    }

    func testFileTypeCategoryLabelsFollowRussianLanguage() {
        AppLanguage.current = .ru
        XCTAssertEqual(FileTypeCategory.folders.label, "Папки")
        XCTAssertEqual(FileTypeCategory.diskImages.label, "Образы дисков")
        XCTAssertEqual(FileTypeCategory.other.label, "Другое")
    }

    func testMaintenanceTaskMetadataFollowsRussianLanguage() {
        AppLanguage.current = .ru

        XCTAssertEqual(MaintenanceTask.freeUpRAM.title, "Освободить ОЗУ")
        XCTAssertEqual(
            MaintenanceTask.flushDNSCache.description,
            "Очистить локальный кэш DNS и принудительно обновить разрешение имён"
        )
        XCTAssertTrue(MaintenanceTask.rebuildLaunchServices.sideEffects.contains("час"))
    }

    func testScanCategoryMetadataFollowsRussianLanguage() {
        AppLanguage.current = .ru

        XCTAssertEqual(ScanCategory.userCaches.displayName, "Кэш пользователя")
        XCTAssertEqual(
            ScanCategory.userCaches.subtitle,
            "Временные файлы приложений обычно восстанавливаемы. Общий сканер кэша не может надёжно подтвердить, что приложение-владелец не используется, поэтому по умолчанию требуется ручная проверка."
        )
    }

    func testFileGroupingAndSortLabelsFollowRussianLanguage() {
        AppLanguage.current = .ru

        XCTAssertEqual(FileGroup.fileTypeLabel("mp4"), "Видео")
        XCTAssertEqual(FileGroup.ageLabel(days: 400), "Более 1 года")
        XCTAssertEqual(FileListSort.sizeDescending.label, "Сначала крупные")
    }
}
