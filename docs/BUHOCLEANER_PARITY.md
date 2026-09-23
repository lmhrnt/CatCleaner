# CatCleaner × BuhoCleaner 功能對照

> 基準：使用者提供的 BuhoCleaner 功能介紹。
> 本文件是工程能力對照，不代表與 BuhoCleaner 有商業、品牌或程式碼關係。

## 狀態定義

- ✅ **已實作**：CatCleaner 已有對應功能與安全路徑。
- 🛡️ **已實作但更保守**：功能存在，但刻意不提供高風險一鍵刪除。
- ⚠️ **基礎設施待完成**：功能程式已存在，但正式發佈/簽章環境尚未配置。

## 功能矩陣

| BuhoCleaner 類功能 | CatCleaner | CatCleaner 實作 |
|---|---|---|
| 一鍵系統垃圾掃描 | ✅ | Smart Scan + System Junk，多類別掃描 |
| 系統/應用程式快取與記錄 | ✅ | Caches / Logs / package manager / IDE / AI tool categories |
| 瀏覽器相關清理 | ✅ | Privacy / browser cache ownership safeguards |
| 垃圾桶 | ✅ | Trash 模組；清空垃圾桶是明確不可逆確認 |
| 可清除空間 | ✅ | Maintenance / Purgeable Space |
| App 完整解除安裝 | ✅ | Uninstaller + associated files |
| 已刪除 App 殘留 | ✅ | Removed App Leftovers；bundle-ID / LaunchServices 交叉檢查，預設零選取 |
| 大型檔案 >50 MB | ✅ | Large & Old Files |
| 音訊/影片/圖片/文件分類 | ✅ | LargeFileKind + category chips |
| 安裝套件/磁碟映像/壓縮檔 | ✅ | LargeFileKind |
| 虛擬機資料 | 🛡️ | bounded known-root discovery，整包顯示、不拆 VM 內部檔案、預設零選取 |
| iPhone / iPad 備份 | 🛡️ | MobileSync backup 整包顯示；System Junk 另有 30 天舊備份掃描 |
| 精確重複檔案 | ✅ | size → partial hash → full SHA-256 |
| APFS 重複資料整併 | ✅ | exact duplicates 可 consolidate；與相似照片隔離 |
| 相似照片 | 🛡️ | Apple Vision feature print + bounded pair plan + complete-link review groups；只審查、不自動刪 |
| 啟動 App 管理 | ✅ | Login Items / LaunchAgents / LaunchDaemons，含 launchd-state hardening |
| 背景服務啟動項 | ✅ | Optimization 模組 |
| 磁碟空間視覺化 | ✅ | Space Lens；含 volume scanning hardening |
| 即時 CPU / RAM / Disk | ✅ | Menu bar SystemStats |
| Battery / Network | ✅ | Menu bar monitor 額外提供 |
| 一鍵釋放 RAM | 🛡️ | `/usr/sbin/purge`；需明確確認，說明僅暫時清快取、不增加實體 RAM，也不保證持續加速 |
| Spotlight 重建 | ✅ | Maintenance / Spotlight Reindex |
| DNS 快取重置 | ✅ | Maintenance / DNS Flush |
| 碎紙機 | 🛡️ | Trash／立即刪除／單次邏輯覆寫後刪除；明確提示 APFS/SSD 無法保證物理 NAND 抹除 |
| Docker 清理 | 🛡️ | 使用 Docker 自身清理未使用資源；不直接刪 volume |
| 開發工具垃圾 | ✅ | Xcode / package manager / IDE caches |
| AI 工具/模型/VM 儲存 | 🛡️ | Developer Cleanup；active owner gate、retentionReview、reportOnly |
| CatDesk build/recovery/snapshot | 🛡️ | build cache 使用 bounded CatDesk GC；recovery/snapshot 不給一般一鍵刪除 |
| 繁體中文（台灣） | ✅ | zh-Hant-TW + 台灣術語集中轉換 |
| 本地端執行 / 零遙測方向 | ✅ | 本地掃描；未新增 telemetry |
| Apple Silicon | ✅ | SwiftPM / arm64 開發路徑 |
| macOS 14+ | ✅ | Package.swift 最低 macOS 14 |
| 正式 Developer ID 簽章 | ⚠️ | CatCleaner 不繼承 upstream Team ID；自己的 Team ID 尚未配置 |
| Notarization | ⚠️ | 發佈 workflow 刻意 disabled，避免誤用 upstream identity |
| 自動更新 | ⚠️ | fail-closed；等待 CatCleaner 自有 signed release feed |
| Homebrew cask | ⚠️ | fail-closed；不發佈 upstream mac-sai cask |

## CatCleaner 額外安全差異

CatCleaner 的設計不把「容量很大」直接等同「垃圾」：

1. **active owner gate**：App/編譯工作正在使用就不清。
2. **scanner ≠ execution authority**：新增掃描規則不會自動獲得刪除權。
3. **Trash-first**：一般可重建資料優先移到 macOS 垃圾桶。
4. **retention-aware**：recovery / snapshot / release history 需 retention proof。
5. **stateful report-only**：VM、containers、sessions 等預設只報告。
6. **相似照片 review-only**：視覺相似不等於 bit-identical，不做自動刪除。
7. **VM / iOS backup bundle semantics**：整包顯示，避免將內部檔案拆散誤刪。
8. **downstream identity fail-closed**：不繼承 Mac Sai 的 Team ID、release feed、Homebrew cask。

## 目前建置驗證狀態

本機目前只選到：

```text
/Library/Developer/CommandLineTools
```

精確驗證：

| Gate | 結果 | 原因 |
|---|---|---|
| `swift build --target MacCleanKit` | ✅ PASS | Core 不需要 SwiftUI macro plugin |
| `swift build --product MacCleanMenu` | ❌ RC 1 | CLT 缺 `SwiftUIMacros.StateMacro` plugin |
| `swift build --product MacClean` | ❌ RC 1 | CLT 缺 `SwiftUIMacros.StateMacro` plugin |
| `swift test` | ❌ RC 1 | CLT 無法解析 `XCTest` |
| Vision API minimal typecheck | ✅ PASS | 已驗證 Revision 1 / scaleFit / computeDistance API |
| 多個非 SwiftUI pipeline semantic typecheck | ✅ PASS | Developer Cleanup、Similar Photos、Large Files 等 |

這是**建置環境限制**，不是目前觀察到的 CatCleaner core compile failure。完整 App / XCTest 最終 gate 需要完整 Xcode。

## 建置 preflight

```bash
./scripts/build-preflight.sh --core-only
./scripts/build-preflight.sh --app
./scripts/build-preflight.sh --tests
```

preflight 不會修改 `xcode-select`、不會安裝 Xcode，也不會下載任何大型工具鏈。完整 Xcode 若已安裝但未全域選取，可用：

```bash
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
  ./scripts/build-preflight.sh --app
```
