# CatCleaner

CatCleaner 是一個以 **Mac Sai** 為上游基礎、獨立維護的 macOS 清理與儲存空間分析工具。目標是在保留透明、安全清理架構的前提下，強化繁體中文（台灣）、開發者/AI 工具清理、重複檔案與照片整理，以及更保守的 retention-aware 清理策略。

> 狀態：早期開發版 `0.1.0`。目前尚未提供正式簽章、notarized release、Homebrew cask 或遠端安裝器。上游 Mac Sai 的 AppIcon/demo/social-preview 資產已移除；在 CatCleaner 自有主圖示完成前，App 暫時使用 macOS generic application icon。

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
- 新增卸載器「已移除 App 殘留」獨立頁：
  - 重用既有 `AppLeftoversScanner` 與 Trash-first CleaningEngine
  - 預設零選取，逐項人工勾選
  - 只掃 Caches / Logs / HTTPStorages / Saved Application State / WebKit
  - Preferences / Containers / Group Containers / Keychain 不列入 orphan 清理
  - 同 vendor namespace 仍有已安裝 App 時保守保留 shared service/cache
  - reverse-DNS 格式收緊，避免 `catdesk-supervisor.launchd.err` 類一般 log 檔誤判
- Space Lens 磁碟分析強化：
  - 掃描進度改為不定進度 + 實際已枚舉項目數，不再顯示固定 50% 的假百分比
  - 可切換「個人資料夾」與目前已掛載磁碟/磁碟映像
  - 掃描 Macintosh HD 時明確剪掉 `/Volumes` 與 `/System/Volumes`，避免把外接磁碟、DMG、APFS Data/helper volume 或另一個 Macintosh HD mount 重複計入
  - 其他巢狀掛載點以 filesystem device boundary 阻擋；選定外接磁碟後則只掃該 volume 自身
  - 切換 volume 或取消掃描會用 generation token 丟棄舊掃描回傳，避免舊結果覆寫新畫面
- 啟動項管理強化：
  - System Events 讀取改為 JXA JSON，不再把 login-item 顯示名稱誤當 bundle ID
  - bundle ID 改由實際 App path / Info.plist 解析
  - 沒有可驗證 path 的 login item 只顯示、鎖定，不猜測修改
  - login-item 開關以精確 path 操作，參數透過 `osascript run(argv)` 傳入，避免字串插值/路徑跳脫問題
  - 由 CatCleaner 關閉的 login item 會保留為 off 狀態，可再次開啟；若使用者在系統設定外部重新啟用，remembered 狀態會自動清除
  - user LaunchAgent 狀態改以 `launchctl print-disabled` 為真實來源；`enable/disable` 持久化狀態，`bootstrap/bootout` 讓目前登入 session 立即生效
  - LaunchAgent 只允許修改 `~/Library/LaunchAgents` 直屬 regular `.plist`，缺 `Label`、巢狀路徑、symlink 與 system LaunchAgent/Daemon 都維持只讀
- 卸載器新增「已移除 App 殘留」獨立頁：
  - 只掃描 Caches、Logs、HTTPStorages、Saved Application State、WebKit 等安全殘留位置
  - 只接受 reverse-DNS bundle ID，並保護 Apple / shared framework / SwiftPM 基礎設施
  - 同 vendor sibling 採保守保留，避免把共享 updater/framework 當成孤兒
  - 以標準 Applications 目錄 + LaunchServices 雙重交叉檢查；搬到其他資料夾或外接磁碟但仍已註冊的 App 也能阻擋誤判
  - 預設零選取；人工勾選後仍走 CleaningEngine Trash-first，可從垃圾桶復原
- 強化「大型檔案」：
  - 保留 50 MB 門檻與手動選取
  - 新增影片、音訊、圖片、文件、壓縮檔、安裝套件、磁碟映像、虛擬機、iPhone/iPad 備份、其他分類
  - MobileSync backup 與 VM package 以整包顯示，不拆成內部檔案
  - VM/iOS backup 只掃 bounded 已知位置，不遞迴整個 ~/Library
  - 所有大型/特殊資料仍預設零選取，清理走既有 Trash-first + SafetyGuard
- 新增「相似照片」review-only 模組：
  - Apple Vision feature print 比較
  - 固定 Revision 1 以避免 SDK 升級時演算法默默漂移
  - metadata 預篩選 + 每張最多 48 個候選 + 全域最多 50,000 對
  - complete-link 保守分群，避免 A≈B、B≈C 就誤把 A/B/C 全部合成一群
  - 嚴格／平衡／寬鬆三個人工審查門檻
  - 不預選、不刪除、不丟垃圾桶、不 APFS consolidate
- 新增「已移除 App 殘留」專頁：
  - 重用既有 bundle-ID orphan detector，而不是名稱模糊比對
  - 只掃 Caches、Logs、HTTPStorages、Saved Application State、WebKit 頂層
  - Preferences、Containers、Group Containers、Keychain 不列為孤立殘留
  - 已安裝 App + LaunchServices 雙重交叉檢查
  - vendor namespace / helper lineage 保守 keep
  - 預設零選取，人工勾選後只移到 macOS 垃圾桶
- 新增「開發者清理」保守執行模組：
  - CatDesk build/recovery/snapshots
  - Codex cache/sessions
  - npm / npx / pip / Homebrew / node-gyp / Cargo
  - Playwright
  - Chrome cache / on-device AI model
  - Claude VM
  - Docker data
  - Alpha Consensus cache / retired runtimes
- Developer Cleanup 不是單純依路徑判斷垃圾，而是分成：
  - `safeWhenInactive`：可重建，但 owner 執行中不可動；仍須 stable-ID execution allowlist 才會出現手動清理選項。
  - `retentionReview`：恢復、快照、模型或版本歷史，需 retention 證據，不提供一鍵清理。
  - `reportOnly`：VM、容器、sessions 等 stateful data，只報告不一鍵刪除。
- 執行策略：
  - 一般 allowlisted cache root：再次掃描確認 owner inactive 後，透過既有 CleaningEngine 移到 macOS 垃圾桶。
  - CatDesk build cache：只呼叫 `catdesk-build-cache-gc --apply`，不刪整個 build-cache root。
  - 預設不勾選；每次清理前重新驗證；廣義 `~/Library/Caches/Google` 目前刻意不開放執行。
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

公開發佈前可執行只讀 readiness audit：

```bash
./scripts/release-readiness.sh
```

目前預期回報 `verdict=HOLD`，直到 CatCleaner 擁有完整 Xcode、自己的 GitHub origin、Developer ID，以及正式啟用的 release/signing workflow。warning（自有主圖示、自動更新、Homebrew、notary profile 等）會另外列出，不與 required blocker 混在一起。

## 本機開發

```bash
cd ~/Documents/CatCleaner
swift build --target MacCleanKit
```

完整 Xcode 安裝後可執行：

```bash
./scripts/build-preflight.sh --app
./scripts/test.sh
./scripts/build-dmg.sh --app-only
```

BuhoCleaner 功能對照與目前 build gate 狀態見：

```text
docs/BUHOCLEANER_PARITY.md
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
