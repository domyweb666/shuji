# Handoff: 第二批做完併進 main（四問沒預設、拿掉提早結束、記一節捷徑、小工具），剩 iCloud 與真機

> 產出時間：2026-11-07 18:15
> 前一會話的最後狀態，給下一個會話接續用
> repo：`E:\習慣地瓜\shuji`（github.com/domyweb666/shuji，gh 已登入 domyweb666）

## ✅ 這次完成了什麼

- 四個決定拍板後，PR #3（全部清除改回原型、CI 產模擬器版、Limrun 腳本）併進 main，Limrun 第二趟 18 條全過。
- 使用者點頭開第二批，選「三小＋小工具」，提早結束拿掉。
- PR #4 batch-2a 併進 main（e20b91e）：開始四問沒預設分數、四題都點過才能記；放手測試拿掉「提早結束」，兩週就是兩週；「記一節」App Intent（`Shuji/App/Intents.swift`）接 Siri、捷徑、動作按鈕，沒種／剛挖／放手中／今天記過或請假各回一句，`Store.live` 讓畫面馬上更新。42 測試。
- PR #5 batch-2b 併進 main（36c8e91）：小工具 target `ShujiWidgetExtension`（桌面小、中，鎖定畫面長方與一行），內容開關句＋今天記了沒；資料是 App Group `group.org.domyweb.shuji` 裡的 `widget.json` 快照，app 存檔時由 `WidgetBridge` 寫、叫 WidgetKit 重畫，換日自動變回「還沒記」；`DayKey.swift` 搬到 `Shared/`。CI 綠 44 測試，IPA 的 PlugIns 裡有 appex。
- 文件同步：`docs/功能增刪建議.md` 多了「第二批（已做）」表，README 多三條。

## 🚧 還沒做完 / 待決定

- **Limrun 點數用完了**（2026-11-07 傍晚 create 回 400 no remaining credits）。PR #4、#5 都沒跑模擬器回歸，只靠 CI 與單元測試。補點數後先跑一次 `node tools/limrun/test.mjs <zip>`（四問那段已改成逐題點 5）。
- **真機沒驗的東西更多了**：原本五樣（震動、藤動畫、傾斜、收工通知時間、檔案 app 備份）加上捷徑（捷徑 app 找「記一節」、Siri「薯記記一節」、動作按鈕）與小工具畫面。小工具靠 App Group，Sideloadly 自己簽要把 group 一起簽，不然永遠顯示「還沒種東西」。
- **第二批剩一項沒做**：iCloud 同步（NSUbiquitousKeyValueStore），要等 TestFlight 簽章路線通。
- 小瑕疵沒修：示範資料週回顧最後一筆落在今天之後三天；「收工檢查」toggle 的 AXLabel 在樹裡出現兩次，腳本點不到，通知授權那步跳過。
- 分支 `ios-app`、`batch-1`、`sim-test`、`batch-2a`、`batch-2b` 都留著沒刪。

## 📌 關鍵決策（這次定下來的，下次別再爭論）

- 小工具沒有按鈕，記一節只能進 app 按住或走捷徑（動作按鈕要按住才觸發）。這是原型「開關要在生活裡」的延伸。
- 小工具資料不碰 `state.json`，只讀快照；快照內容沒變就不重寫、不重畫。
- 快照的狀態順序照主畫面狀態機：剛挖 → 放手 → 記了／請假 → 還沒記；旅行中顯示旅行版最小一步。
- pbxproj 的 widget target ID 全是 `5A000…E` 開頭；`Shared/` 同步資料夾同時掛在 Shuji 與 ShujiWidgetExtension 兩個 target；Info.plist 與 .entitlements 用 membershipExceptions 排除在資源外。
- 開始四問的分數在畫面上是 `[Int]`，0 代表沒點；存進去還是 `[Double]`，JSON 跟原型一樣。
- Limrun 帳號跟人蔘修煉、蒜數共用，點數是共用的；別刪不是自己開的 instance。

## 📂 下個會話最重要的檔案

- `Shuji/App/Intents.swift` ← 記一節捷徑；`Shuji/App/WidgetBridge.swift` ← 寫快照
- `Shared/WidgetSnapshot.swift`、`Shared/DayKey.swift` ← 兩個 target 共用
- `ShujiWidget/ShujiWidget.swift` ← 小工具畫面；`ShujiWidget/Info.plist`、兩份 `.entitlements`
- `Shuji.xcodeproj/project.pbxproj` ← 三個 target；加 Swift 檔不用改它
- `tools/limrun/test.mjs` ← 模擬器走流程，等點數
- `docs/功能增刪建議.md` ← 已做清單、剩 iCloud、別碰清單
- `ShujiTests/CoreTests.swift` ← 44 測試，改邏輯先改這

## ⏭️ 下一步從哪繼續

1. 先讀這份。
2. 問使用者：Limrun 要不要補點數跑回歸；真機要不要走 Sideloadly（Actions 下載 `Shuji-unsigned-ipa`，簽的時候帶 App Group）；iCloud 要不要現在做（要先有 TestFlight 路線）。
3. 改功能照舊：開分支 → PR → CI 綠 →（有點數就）Limrun → 合併。新功能往腳本加檢查。

## 🗑️ 這次會話的雜訊（下次別重新討論）

- 本機 `python3` 是 Store 空殼，用 `python`。Bash heredoc 裡的 `\\` 會被折成一個，路徑用正斜線。
- 模擬器腳本三個坑（英文鍵盤打不了中文、鍵盤蓋按鈕、小點不在無障礙樹）都已經在腳本裡繞掉。
- `Color(uiColor:)` 在 widget 裡補了 `import UIKit`，CI 過了，別再猜要不要。
- CI 一次約 5 到 6 分鐘；macOS runner 偶爾排隊。
