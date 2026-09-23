# CatCleaner

CatCleaner 是一個以 **Mac Sai** 為上游基礎、獨立維護的 macOS 清理與儲存空間分析工具。目標是在保留透明、安全清理架構的前提下，強化繁體中文（台灣）、開發者/AI 工具清理、重複檔案與照片整理，以及更保守的 retention-aware 清理策略。

> 狀態：早期開發版 `0.1.0`。目前尚未提供正式簽章、notarized release、Homebrew cask 或遠端安裝器。

## 目前已完成

- 產品名稱、bundle ID、shared defaults、log/database namespace 與 deep-link 已獨立為 CatCleaner。
- 新增 `zh-Hant-TW`，系統語系 `zh-TW / zh-HK / zh-MO / zh-Hant` 會選用繁體中文。
- 繁中採「簡中來源 → ICU Hans-Hant → 台灣術語校正」的集中式轉換，包含：
  - 設定
  - 快取
  - 垃圾桶
  - 解除安裝
  - 記憶體
  - 磁碟
  - 檔案 / 資料夾
  - 效能 / 網路 / 音訊 / 影片等
- 新增「開發者清理」scan-only 模組：
  - CatDesk build/recovery/snapshots
  - Codex cache/sessions
  - npm / npx / pip / Homebrew / node-gyp / Cargo
  - Playwright
  - Chrome cache / on-device AI model
  - Claude VM
  - Docker data
  - Alpha Consensus cache / retired runtimes
- Developer Cleanup 不是單純依路徑判斷垃圾，而是分成：
  - `safeWhenInactive`：可重建，但 owner 執行中不可動。
  - `retentionReview`：恢復、快照、模型或版本歷史，需 retention 證據。
  - `reportOnly`：VM、容器、sessions 等 stateful data，只報告不一鍵刪除。
- Developer Cleanup 的容量探測最多 4 路並行；已修正大型 `ps` 輸出可能造成的 pipe deadlock。
- CatCleaner 不再繼承 Mac Sai 的 Apple Developer Team ID；privileged/XPC trust 預設 fail-closed。
- upstream 更新檢查已停用，避免 CatCleaner 誤提示 Mac Sai release。

## Build 狀態

目前此 Mac 只安裝 Apple Command Line Tools，沒有完整 Xcode。因此：

- `swift build --target MacCleanKit`：PASS
- CatCleaner 新增 SwiftUI 檔案：Swift parser PASS
- 完整 `MacClean` app build：會因缺少 `SwiftUIMacros` plugin 失敗
- XCTest：會因 Command Line Tools 環境缺少完整 `XCTest` framework 失敗

完整 App build / XCTest 需要安裝完整 Xcode，並以 Xcode developer directory 執行。

## 本機開發

```bash
cd ~/Documents/CatCleaner
swift build --target MacCleanKit
```

完整 Xcode 安裝後可執行：

```bash
swift test
./scripts/build-dmg.sh --app-only
```

開發安裝腳本會使用：

```text
/Applications/CatCleaner.app
```

不會覆蓋 Mac Sai。

## 安全原則

CatCleaner 對清理功能採 fail-closed：

1. 大容量不等於垃圾。
2. owner 正在使用的資料不清。
3. 優先使用 owning tool 自己的 cleanup command。
4. recovery / snapshot / release history 必須先做 retention review。
5. VM、container volume、session、科學資料與使用者資料不因「很大」就列入一鍵清理。
6. 新 scanner 規則與 destructive executor 分離；新增 path rule 不會自動獲得刪除能力。

## 上游與授權

CatCleaner 衍生自 Mac Sai。原始碼上游：

- https://github.com/iliyami/MacSai

上游及本專案沿用 BSD 3-Clause 條款。請保留 `LICENSE` 與 `NOTICE` 中的著作權與授權資訊。

內部 SwiftPM target / executable 名稱目前仍保留 `MacClean`、`MacCleanKit`、`MacCleanMenu`，這是為了降低 fork 初期大規模 rename 的回歸風險；使用者面產品名稱與 bundle namespace 已是 CatCleaner。
