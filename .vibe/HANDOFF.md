# Handoff: 薯記從網頁原型移植成原生 SwiftUI app，兩個 PR 都已併進 main，下一步是真機

> 產出時間：2026-11-07 16:59
> 前一會話的最後狀態，給下一個會話接續用
> repo：`E:\習慣地瓜\shuji`（github.com/domyweb666/shuji，gh 已登入 domyweb666）

## ✅ 這次完成了什麼

- 下載 domyweb666/shuji（只有 `index.html` 的 PWA 原型），整個讀完
- 移植成 iOS 17 以上的原生 SwiftUI app，Xcode 16 格式專案；流程、文案、數字照原型，JSON 格式一字不差，原型備份貼進來就能用
- 做了原型標「原生版才有」的收工檢查通知；測試區只留 Debug；「全部清除」搬到資料區並加確認
- 修了原型兩個 bug：放手測試那兩週被算成漏掉、「卡住」第三列捲錯地方
- 寫 41 個單元測試，標準答案是用 Node 跑原型的 JS 算出來的；GitHub Actions 在 macOS 建置、測試、打包未簽名 IPA
- 第一批修補：露出「為了什麼」與「不順的時候」、回顧連結留三天、挖地瓜前自動備份到 Documents、砍聲音開關、障礙版併入備用開關、「讓開始更容易」改成卡住頁的 TipsSheet、四點換日說明
- PR #1（ios-app）與 PR #2（batch-1）都併進 main，CI 綠，IPA 拆開驗過 Info.plist
- 記憶寫在 `~/.claude/projects/E------/memory/shuji-ios-port-2026-11.md`

## 🚧 還沒做完 / 待決定

- **真機從沒跑過。** 四樣只有手機看得出來：按住一秒半會不會被左右滑頁搶走、藤長出來的動畫與傾斜搖葉、收工檢查通知有沒有在對的時間跳、挖地瓜後「檔案」app 看不看得到備份。卡在使用者沒有 Mac，要走 Sideloadly 自己簽或 Limrun 雲端模擬器，使用者還沒說走哪條。
- **四個跟原型不同的決定等使用者拍板**（`docs/功能增刪建議.md` 最後一節）：全部清除留在正式版、收工檢查文案是我寫的、放手 14 天從漏掉排除、聲音開關拿掉。
- **第二批候選，使用者還沒點頭**：iCloud 同步（NSUbiquitousKeyValueStore，要等 TestFlight 簽章路線通）、小工具、App Intent 與動作按鈕；要改的：開始四問預設 4 分、放手測試「提早結束」的天數基準。
- `ios-app`、`batch-1` 兩條分支留著沒刪。

## 📌 關鍵決策（這次定下來的，下次別再爭論）

- 原生 SwiftUI，不是 Capacitor 包殼。原型本身就是照 iOS 介面寫的規格，而且自己標了原生版要做的事。
- `index.html` 不動也不搬，使用者可能用 GitHub Pages 把它裝在手機上。
- 資料格式跟原型一字不差；`logs` 的 key 留字串，不用 DayKey 當字典 key（Codable 會變成陣列）。
- 三頁橫排用 TabView 的 page 樣式；主畫面整頁 ScrollView，藤固定 230pt 高貼底。
- 聲音跟手機側邊靜音鍵走，app 裡沒開關；震動三種（按下、按滿、開花）。
- 放手測試結束時把 start／end 存進 letgoResult（原型沒有），用來排除漏掉與「停了一陣子」。
- 沒 Mac 的裝機三條路跟洋蔥地圖一樣：Actions 未簽 IPA → Sideloadly／AltStore；Codemagic → TestFlight；Actions 自備 p12。使用者有付費開發者帳號。
- 特殊 Info.plist key 走 `Shuji/Info.plist` 合併，不走 `INFOPLIST_KEY_`（UIFileSharingEnabled 塞不進去）；同步資料夾要用 PBXFileSystemSynchronizedBuildFileExceptionSet 把它排除在資源外。
- 原型刻意不做的守住：多習慣、連續天數、社群、激勵語、點數徽章。

## 📂 下個會話最重要的檔案

- `docs/功能增刪建議.md` ← 待拍板的四個決定、第二批候選、別碰清單
- `README.md` ← 跑法、沒 Mac 的三條路、原生版跟原型不同的地方
- `Shuji/Core/Logic.swift`、`Shuji/Core/Store.swift` ← 所有計算與動作，純 Foundation
- `Shuji/Views/TodayView.swift` ← 主畫面狀態機，順序照原型 renderMain
- `ShujiTests/CoreTests.swift` ← 標準答案在這，改邏輯先改這
- `.github/workflows/ios.yml` ← CI；模擬器用最新 runtime 的 UDID，別改回名稱
- `Shuji.xcodeproj/project.pbxproj` ← 手寫的 Xcode 16 格式；ID 都是 5A000…；加檔案不用改它，同步資料夾自動收

## ⏭️ 下一步從哪繼續

1. 先讀這份。
2. 問使用者真機測試走哪條：A. 從 Actions 最新 run 下載 `Shuji-unsigned-ipa`，用 Sideloadly 簽了裝；B. Limrun 雲端模擬器（人蔘修煉那邊他指定用這個，AI 能自己看畫面）。
3. 裝好先在設定頁測試區「載入示範資料」，照上面四個真機項目逐一看。壞的直接修，開分支走 PR，CI 綠再合併，跟前兩次一樣。
4. 使用者拍板 `docs/功能增刪建議.md` 最後一節之後，才動第二批。第二批第一個是 iCloud 同步，但要先有 TestFlight 那條簽章路線。

## 🗑️ 這次會話的雜訊（下次別重新討論）

- 本機 Windows 沒 Swift 工具鏈，也不要去裝；全靠 CI，一次約五分鐘。
- Edit 工具會吃掉行尾空格，插程式碼時 `= [` 會變 `=[`，編譯失敗。插入後 grep 一下。
- CI 第一次失敗是模擬器名稱配上預設 OS:latest 對不上，已改 UDID，不會再發生。
- Bash heredoc 寫大檔會被 shell 吃掉（指令長度上限），大檔用 Write。
- 洋蔥地圖、人蔘修煉是另外兩個 iOS 專案，記憶裡各有一條，別混在一起。
