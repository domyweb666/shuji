# Handoff: 全部介面改用 Domy Design System（梅紫），PR #7 草稿；順手修掉伺服器測試的日期定時炸彈

> 產出時間：2026-11-15 04:48
> repo：`E:\習慣地瓜\shuji`（github.com/domyweb666/shuji，gh 已登入 domyweb666）
> 分支：`domy-ui`（PR #7，草稿，base 是 `ai-v2`）。`ai-v2` 是 PR #6（AI 版，草稿，還沒合併），上一份 AI 版交接在 `.vibe/handoff/archive/2026-11-08-1500-ai.md`

## ✅ 這次完成了什麼

- 把 `E:\domy-design\swift\DomyTokens.swift`（v1.1.0）原樣複製到 `Shared/DomyTokens.swift`，app 跟小工具共用。
- 新增 `Shuji/Design/DomyKit.swift`：照 domy-design `src/components` 的規格，在本地寫 SwiftUI 元件，包括 DomyButton、DomyScreen、DomyHeader、DomySection、DomyToggleRow、DomyPickerRow、DomyStatGrid、DomyInfoStrip、DomyEmptyState、DomyTabBar、ScalePicker，另有 `domyType`、`domyShadow`、`domyField` 三個修飾器。
- `Theme.swift` 改成只對應 Domy 代號，也加了 `Sp`、`Ty`、`Sz`、`Rd` 四個縮寫。田園插畫色（Garden）保留，花色改成梅紫系。
- 重寫 Components、RootView、HoldButton、TodayView、FieldView、SettingsView、OnboardingView、Sheets、AIViews、小工具的畫面。文案、流程、資料都沒動，只有田的「回來／漏掉」拆成兩格統計。
- 新增 `tools/check-ui-tokens.mjs` 擋寫死的數值，CI 多了一個「畫面只用 Domy 代號」工作。
- 修掉伺服器測試的日期定時炸彈：`server/test/fakeApple.ts` 的假憑證開始日期往前推十年。修在 `ai-v2`（5d125c9），所以 PR #6 也一起修好，再合併進 `domy-ui`。
- CI 第一輪：iOS 建置與測試過、代號檢查過，只有伺服器測試掛（就是上面那個炸彈）。修完後第二輪：伺服器過、代號過、iOS 還在跑。

## 🚧 還沒做完 / 待決定

- **第二輪的 iOS 建置**（run 43639369221）交接當下還在跑。第一輪同樣的 Swift 已經過了，合併進來的只有 server 測試檔，理論上不會壞，但要親眼看到綠燈。
- **畫面沒人看過。** 這台是 Windows，多米選了「只要 CI 編譯＋單元測試」，沒加 UI 截圖測試。深色模式、大字級、iPhone SE 寬度、分頁列浮在今天頁的土上這幾點都要真機看一次。
- **Auto-fix 沒開成。** 當時工作資料夾在 `E:\習慣地瓜`，app 對不到這個 repo。多米可以自己在 PR 列打開。
- **Limrun 腳本**（`tools/limrun/test.mjs`）沒跟著改。開始四問的分數改成一排按鈕，`review-q1..4` 識別碼還在，但腳本如果是點分段控制就會失效。帳號沒點數，暫時跑不了。
- PR #6、#7 都還是草稿；#7 要等 #6 先併進 main，或改 base。

## 📌 關鍵決策（這次定下來的，下次別再爭論）

- 產品色用**梅紫 plum**：跟原本紫色地瓜、紫花最接近，對比 domy-design 已經驗過，不用改共用套件。
- 導覽用**底部懸浮膠囊分頁列＋保留左右滑**（田／今天／設定，圖示 leaf／sun.max／gearshape，選中換 .fill）。
- 驗證只要 **CI 編譯＋單元測試**，不加 XCUITest 截圖（多米選的）。
- 按住鈕照 Domy 核心大鈕規格：外圈 216、鈕 180，待機用 bright 底配 onBright 字，按著變 accent。進度圈寬度是 heroRingWidth×2。
- 「記好了／請假／放手中」改成狀態章，跟大鈕同位置同尺寸，換狀態版面不跳。
- Swift 元件先放 app 本地（domy-design README 規則 2）。第二款原生 App 也要用時，再搬進 domy-design 的 `swift/`。
- 插畫（VineView、PotatoView）不走代號、不在檢查範圍；一次性數值在那一行加 `// domy-ignore: 原因`。
- 今天頁的藤畫布高度是 230＋分頁列讓位高度，讓分頁列浮在土上、不蓋到葉子。

## 📂 下個會話最重要的檔案

- `Shuji/Design/DomyKit.swift` ← 新元件全在這
- `Shuji/App/Theme.swift` ← 代號對應與縮寫
- `Shuji/Views/Components.swift`、`TodayView.swift`、`FieldView.swift`、`SettingsView.swift`
- `Shared/DomyTokens.swift` ← 從 domy-design 產生，不要手改；套件升版就重新複製
- `tools/check-ui-tokens.mjs`、`.github/workflows/ios.yml`（ui-tokens 工作）
- `server/test/fakeApple.ts` ← 憑證日期修正

## ⏭️ 下一步從哪繼續

1. 在 repo 跑 `gh pr checks 7`，確認 build-and-test 是綠的。紅的話 `gh run view <run id> --log-failed` 看 Swift 編譯錯誤，修在 `domy-ui`。
2. 綠了就從 Actions artifacts 下載 `Shuji-unsigned-ipa`，交給多米用 Sideloadly 裝真機。照「還沒做完」第二條的清單逐項看，要改的列成清單再動手。
3. 多米看過沒問題，再處理合併順序：先 PR #6（ai-v2）進 main，再把 PR #7 的 base 改成 main 後合併。

## 🗑️ 這次會話的雜訊（下次別重新討論）

- 有一段回覆用了英文，多米要求說中文。一律繁體中文。
- 伺服器 401 跟介面改動無關，是測試把日期釘在 11-08 造成的，已經修掉。
