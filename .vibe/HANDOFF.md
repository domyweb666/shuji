# Handoff: 薯記原生版在 Limrun 模擬器跑過一輪全過，四個決定拍板了，下一步是真機手感與第二批

> 產出時間：2026-11-07 17:45
> 前一會話的最後狀態，給下一個會話接續用
> repo：`E:\習慣地瓜\shuji`（github.com/domyweb666/shuji，gh 已登入 domyweb666）

## ✅ 這次完成了什麼

- 使用者拍板四個跟原型不同的決定：只有「全部清除」要改回原型（正式版不給清，只留 Debug 測試區），其他三個維持（收工檢查文案、放手 14 天不算漏掉、聲音開關拿掉）。`docs/功能增刪建議.md` 最後一節已改成「已拍板」。
- 真機路線選了 B：Limrun 雲端模擬器。CI 多打包一份通用架構的模擬器版 `Shuji-simulator.app.zip`（artifact `Shuji-simulator-app`），`tools/limrun/test.mjs` 上傳到 Limrun、開 iPhone 模擬器走完整流程、截圖、印過／沒過清單。
- 第二趟實跑 18 條全過（132 秒）：首次設定、按住一秒半記一節、短按不記、手指滑開 15 點仍記得到（沒被 TabView 翻頁搶走）、撤銷、三頁翻頁、示範資料、往後一天、開始四問、重開資料還在、深色模式、全部清除回首次設定。結果貼在 PR #3 底下。
- PR #3（sim-test）CI 綠後併進 main，merge commit e2fa5bf。本機 main 跟 origin 同步。

## 🚧 還沒做完 / 待決定

- **真機手感還是沒驗**，模擬器抓不到這五樣：按住時的震動、藤長出來的動畫順不順、傾斜搖葉、收工檢查通知有沒有準時跳、「檔案」app 看不看得到備份。要驗得走 Sideloadly（Actions 下載 `Shuji-unsigned-ipa` 自己簽）。使用者這次選了模擬器，沒說要不要再走真機。
- **第二批候選，使用者還沒點頭**：iCloud 同步（NSUbiquitousKeyValueStore，要等 TestFlight 簽章路線通）、小工具、App Intent 與動作按鈕；要改的：放手測試「提早結束」的天數基準。（開始四問預設 4 分已經是 4，不用改。）
- 小瑕疵，沒修：示範資料的週回顧最後一筆日期是 today+3（9/23 起每 7 天七筆，落到 11/10），田頁曲線 x 軸會出現未來日期。跟原型同一套算法，只影響示範資料。
- 腳本沒測到的一條：設定頁「收工檢查」toggle 的 AXLabel 在樹裡出現兩次，`tapElement` 拒絕；所以通知授權彈窗那一步被跳過。要測就改用 frame 點。
- `ios-app`、`batch-1`、`sim-test` 三條分支都留著沒刪。

## 📌 關鍵決策（這次定下來的，下次別再爭論）

- 全部清除：正式版沒有，照原型；要重來就刪 app 重裝。README 與功能建議檔都改了。
- Limrun 這台的用法：`tools/limrun/` 用 `@limrun/api` 不用 CLI；金鑰讀 `~/.lim/config.yaml`；帳號 2026-11-07 下午起有點數（同帳號下另有人蔘修煉的模擬器在跑，別刪不是自己開的 instance）。一趟約 2 分鐘、扣約 5 點。
- 模擬器腳本三個坑（都不是 app 的 bug）：模擬器英文鍵盤，`typeText` 中文會打成亂碼，所以只點範例片不打字；鍵盤會蓋住「種下去」，改按 `pressKey('enter')`（欄位 onSubmit 會種）；上面那排小點在無障礙樹只露出容器「頁面」，點座標三等分。
- 按住用 `performActions` 的 touchDown → wait 1800 → touchUp，座標取「按住一秒半，記一節」的 frame 中心，座標空間是 points。
- 前幾次定的照舊：原生 SwiftUI 不包殼、`index.html` 不動、JSON 格式一字不差、`logs` key 留字串、Info.plist 合併法、沒 Mac 三條裝機路。

## 📂 下個會話最重要的檔案

- `tools/limrun/test.mjs`、`tools/limrun/README.md` ← 模擬器走流程腳本與跑法；`shots/` 是截圖（gitignore）
- `docs/功能增刪建議.md` ← 已拍板的四個決定、第二批候選、別碰清單
- `README.md` ← 跑法、沒 Mac 的三條路、原生版跟原型不同的地方
- `Shuji/Core/Logic.swift`、`Shuji/Core/Store.swift` ← 所有計算與動作
- `Shuji/Views/TodayView.swift`、`Shuji/Views/HoldButton.swift` ← 主畫面狀態機與按住
- `ShujiTests/CoreTests.swift` ← 標準答案；改邏輯先改這
- `.github/workflows/ios.yml` ← CI：測試、模擬器版 .app、未簽名 IPA

## ⏭️ 下一步從哪繼續

1. 先讀這份。
2. 問使用者兩件事：要不要走 Sideloadly 驗真機那五樣（給他 Actions 下載 IPA 的步驟就好）；第二批要不要開工、從哪個開始（建議小工具或 App Intent 先，iCloud 要等簽章路線）。
3. 改功能照舊：開分支 → PR → CI 綠 → 下載 `Shuji-simulator-app` 跑 `node tools/limrun/test.mjs <zip>` 看 18 條還過不過 → 合併。新功能記得往腳本加檢查。
4. 想順手修的小事：示範資料未來日期、收工檢查 toggle 的測試步。

## 🗑️ 這次會話的雜訊（下次別重新討論）

- 本機 Windows：`python3` 是 Microsoft Store 的空殼，什麼都不印；用 `python`（3.10）。
- Bash heredoc 跑 python 改檔沒問題，但要用 `python` 不是 `python3`。
- CI 每次約 5 到 6 分鐘，macOS runner 偶爾排隊。
- Limrun 第一趟 11 條沒過全是腳本問題（鍵盤蓋按鈕、中文打不進去、小點點不到），第二趟改完全過；不用再懷疑 app。
- 洋蔥地圖、人蔘修煉、蒜數是另外三個 iOS 專案，記憶裡各有一條，別混。蒜數的 `tools/limrun/test.mjs` 是這份腳本的底。
