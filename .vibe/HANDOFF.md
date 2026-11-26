# Handoff: 芹查 QC-0011 改完在 qc-0011，沒推、沒編譯

> 2026-11-26。repo `E:\習慣地瓜\shuji`，分支 `qc-0011`（從 main e36c78f 開），兩個 commit：9c52045（八筆程式）、下一個（地瓜造型 D）。上一份見 `.vibe/handoff/archive/2026-11-25-week-prompt.md`

## ✅ 現況
- QC-0011 十一筆都處理了。#76 出 HTML（`E:\習慣地瓜\QC-0011\長好的習慣.html`）；#78 #79 造型五款在 https://claude.ai/artifact/MUmNyyL7iPguYGoD1oQyoc ，多米選 D，已做進 `Shuji/Views/HoldButton.swift`（PotatoBody 改畫直立的 D，版位 264×196 不變，外圈改直的橢圓；TodayView ringInset 20→8；VineView 記好後根不再移到左端）。
- 其他：#77 設定拿掉不適合那列；#80 AI 頁只管連線，三個幫忙改在回來卡選理由後／連漏兩天／放手中出現；#81 送自己電腦不跳同意頁（伺服器照問）；#82 進度條照答完幾題；#83 預估頁文案加年份；#84 #85 VineView 看 habit.id 換習慣就清；#86 竹籃「種到一半的」（`AppState.unfinished`）。
- 2026-11-26 子代理盲審過全部 Swift 改動：沒找到確定會編不過的；唯一風險（HoldButton bottom 長串 tuple 推導）已拆成 bottomTail（2a5eff5）。專案是 Swift 5.0、沒開嚴格並行。
- 只跑過 `node tools/check-ui-tokens.mjs`（過）。Swift 是盲寫，**沒編譯、沒跑測試、沒拍圖**。新測試在 `ShujiTests/HabitEstimateTests.swift`（五個）與 BridgeTests。

- 2026-11-26 效能審查（docs/效能審查-2026-11-26.md）與第一批修正也在 qc-0011：473b5dc 聲音預熱／震動／藤限速、f5d383c AI 離開就取消＋bridge 殺 CLI、6953589 捷徑 makeLive。同樣沒編譯；真機要看的點寫在報告「第一批已改」。第二批（tick、formatter、小工具比對）與存檔移背景還沒做。

## ⏭️ 下一步
1. 問多米可不可以 push（repo 是 PUBLIC，單子只說 commit）。點頭後 `git push -u origin qc-0011`，看 CI；編不過就修。
2. CI 綠之後用 Limrun 拍今天頁（淺深、按住中、記好、回來那天寫字、跳過、放手），特別看 D 的煙有沒有被切、「你回來了」有沒有壓在剝開的肉上、根有沒有接到頂。`tools/limrun/states.mjs` 的 unfit 那張已拿掉。
3. 多米看圖後併 main、出 TestFlight。

## 📌 定了的（別再問）
- 地瓜造型 D。送到自己的電腦不問同意。AI 幫忙不放選單，照時機出現。
- 提交要指定檔名；不開 worktree。

## ⚠️ 已知沒處理
- 竹籃裡的小地瓜（PotatoView）、挖出來那頁、付費頁還是舊造型，這次只換土裡那顆。
- 「種到一半的」只能看，不能種回來或排進排隊。
- 送自己電腦不問同意，上架前要再對 Apple 5.1.2 的第三方 AI 條文。
