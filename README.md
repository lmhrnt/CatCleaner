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
  - 重用既有 `AppLeftoversScanner` 與 Trash-first CleaningEngine，不另寫更激進的 orphan 判定
  - 只掃 Caches / Logs / HTTPStorages / Saved Application State / WebKit；Preferences / Containers / Group Containers / Keychain 不列入清理
  - 以標準 Applications 位置 + LaunchServices 雙重確認 App 是否仍存在；搬到其他資料夾或外接磁碟但仍已註冊的 App 也會阻擋誤判
  - 同 vendor namespace 仍有已安裝 App 時保守保留 shared service/cache；只接受 reverse-DNS bundle ID，避免一般 log 檔誤判
  - 預設零選取；清理前會 fresh orphan scan，人工確認後才走 `CleanActions -> CleaningEngine -> macOS Trash`，可從垃圾桶復原
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
- Smart Scan 僅執行真正會產生掃描結果的模組；Uninstaller / Updater / Optimization / Maintenance 與大型檔案等 action/review-only 模組不再出現幽靈掃描步驟。Checklist 直接由 `ScanCoordinator` 的註冊與 `includedInSmartScan` 契約產生，避免 UI 與 runtime 漂移。
- Smart Scan 結果頁分開顯示清理候選容量、惡意項目數與隱私痕跡數，並按 URL 去重；清理確認/完成頁會依實際 category 精確區分「移到垃圾桶（可復原）／垃圾桶內容永久刪除（不可復原）／Universal Binary 原地精簡」，不再用單一『可從垃圾桶恢復』文案掩蓋不同執行語意。

## Build 狀態

目前此 Mac 已具備完整 Xcode 27.0 開發環境，且本機與 GitHub CI 都能執行完整建置／測試 gate：

- `./scripts/xcode-qualification.sh --full`：PASS；包含 fresh XCTest + coverage、完整功能 gate、universal app build、bundle identity／架構／codesign 驗證
- `./scripts/local-app-readiness.sh`：`LOCAL_APP_READY`，`required_blockers=0`
- GitHub `CatCleaner CI`：`Build, Test & Bundle` 與 `Safety & Downstream Isolation Audit` 皆 PASS
- 本機安裝版使用 `CatCleaner Local Code Signing`，供本機自用；Developer ID／notarization 仍屬可選的公開發佈基礎設施

完整 App build / XCTest 由 `./scripts/xcode-qualification.sh --full` 對目前乾淨 HEAD/tree 執行。full mode 會先移除 `.build/out` 的舊 SwiftPM compiled products，避免 stale XCTest binary 被誤當成目前 source 的結果；全部通過後會把已驗證的 universal `CatCleaner.app` 封存在 `.build/qualification/CatCleaner.app`，並產生 `.build/qualification/xcode-qualification-v1.json`。後續本機 native rebuild 不會覆蓋這份 qualification snapshot。

CatCleaner 目前的主要使用目標是**本機自用 App**，不要求付費 Apple Developer Program、Developer ID、notarization、App Store 或 GitHub Release：

```bash
./scripts/feature-readiness.sh --full
./scripts/xcode-qualification.sh --full
./scripts/dev-install.sh
./scripts/local-app-readiness.sh
```

最終本機 gate 為 `verdict=LOCAL_APP_READY`。本機安裝使用獨立的 `CatCleaner Local Code Signing` 自簽 identity，使 bundle 的 code-sign identity 在重建後保持穩定；它**不是 Developer ID**，只供這台 Mac 自用。公開發佈仍保留為另一條可選的 fail-closed workflow，但不再是本機使用的 blocker。

## 本機開發

```bash
cd ~/Documents/CatCleaner
swift build --target MacCleanKit
```

完整 Xcode 安裝後先執行 exact-source qualification，再安裝本機 App：

```bash
./scripts/xcode-qualification.sh --full
./scripts/dev-install.sh
./scripts/local-app-readiness.sh
```

qualification 會依序執行 app/tests preflight、fresh XCTest coverage、完整功能 gate、universal `.app` build、bundle ID／版本／架構／codesign 驗證，並在全部通過後產生 SHA-bound receipt。dev install 則建立／使用 CatCleaner 專用本機簽章、建置 native-arch release、安裝到 `/Applications/CatCleaner.app` 並做啟動 smoke test。若只要快速開發驗證，可用：

```bash
./scripts/xcode-qualification.sh --quick
```

建置/測試入口會自動尋找目前 `DEVELOPER_DIR`、`/Applications/Xcode.app`、`/Applications/Xcode-beta.app` 或 `~/Applications/Xcode.app`，並只對該命令設定 Xcode developer directory；**不會修改全機 `xcode-select`**。只有 Command Line Tools 時會在真正編譯前以明確訊息 fail-closed，核心仍可用 `swift build --target MacCleanKit`。

BuhoCleaner 功能對照與目前 build gate 狀態見：

```text
docs/BUHOCLEANER_PARITY.md
```

開發安裝腳本會使用：

```text
/Applications/CatCleaner.app
```

不會覆蓋 Mac Sai。

## 隱私與網路

- 無 analytics、廣告追蹤、遙測或第三方 crash-reporting SDK。
- 清理、磁碟分析、重複檔案、相似照片與開發者掃描都在本機完成。
- CatCleaner 自身更新通道目前 fail-closed，不連 upstream Mac Sai / Homebrew。
- 第三方 App 更新檢查只有使用者按下「檢查更新」才會直接連各 App 的 HTTPS Sparkle feed。
- 網路能力由 `scripts/check-network-surface.py` 與 CI allowlist 強制限制。
- 詳見 `PRIVACY.md`。

### 自行驗證無遙測

不必只依賴上述宣告；可在專案根目錄直接執行：

```bash
python3 scripts/check-network-surface.py
rg -n 'URLSession|NSURLConnection' Sources --glob '*.swift'
lsof -i -P -n | grep -i 'CatCleaner\|MacClean' || echo "no CatCleaner network sockets"
```

第一個命令是 CI 使用的 bounded network-surface contract；後兩個命令分別讓你檢查原始碼中的網路 API 與目前實際開啟的 socket。

## 安全原則

CatCleaner 對清理功能採 fail-closed：

1. 大容量不等於垃圾。
2. owner 正在使用的資料不清。
3. 優先使用 owning tool 自己的 cleanup command。
4. recovery / snapshot / release history 必須先做 retention review。
5. VM、container volume、session、科學資料與使用者資料不因「很大」就列入一鍵清理。
6. 新 scanner 規則與 destructive executor 分離；新增 path rule 不會自動獲得刪除能力。
7. 通用 `~/Library/Caches` 與 `/Library/Caches` 仍會掃描，但不再預設勾選：generic scanner 無法可靠證明 owner App 已停止。具體工具快取若要安全執行，使用 Developer Cleanup 的 fresh active-owner gate。

## 上游與授權

CatCleaner 衍生自 Mac Sai。原始碼上游：

- https://github.com/iliyami/MacSai

上游及本專案沿用 BSD 3-Clause 條款。請保留 `LICENSE` 與 `NOTICE` 中的著作權與授權資訊。

內部 SwiftPM target / executable 名稱目前仍保留 `MacClean`、`MacCleanKit`、`MacCleanMenu`，這是為了降低 fork 初期大規模 rename 的回歸風險；使用者面產品名稱與 bundle namespace 已是 CatCleaner。
