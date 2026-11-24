# Handoff: 今天頁烤好剝開、田改報表、四問自動跳（已併 main，TestFlight 已上傳）

> 產出時間：2026-11-24
> repo：`E:\習慣地瓜\shuji`（外層 `E:\習慣地瓜` 不是 git repo）
> 分支：`main`（bf7e76f 併進 done-shape，CI 全綠）；TestFlight run 45417876090 上傳成功

## ✅ 這次完成了什麼

- 今天頁記好後只剩開關句；多米選 C：地瓜烤好剝開（`HoldButton.swift` 的 `done`、`BakedFlesh`、`Steam`；`VineView` 的 `baked`／`linkP` 把根移到左端）。按住、完成、撤銷、再按，淺深色都在模擬器看過。
- 田改成「月曆｜分析」（`FieldView.swift`，數字在 `Core/FieldReport.swift`）；竹籃＋排隊收在右上角。
- 開始四問、壓力週、放手、挖地瓜改成打開 app 自動問（`AppState.autoAsk`、`Store.nextAsk`、`RootView`、`AskSheet`）。四問四題走完在模擬器看過。
- 選項畫布：https://claude.ai/artifact/YGYgSPzPEMFESfPjbvrJYD ；截圖在 `E:\習慣地瓜\完成形狀`。

## 🚧 還沒做完 / 待決定

- 等多米真機回饋（裂開那一下、四問自動跳、田報表）。
- 沒在模擬器走過：挖地瓜那張、放手那張（只有單元測試）；比 402×874 小的手機、放大字級。裂開那一下順不順要真機看。
- 田 A 已做；多米若選 B 再改。「這週的田」兩行字還在，設定可關。
- `tools/limrun/test.mjs` 還是舊流程，要改寫；看畫面用 `states.mjs`。AnalyticsCopy 的 D-1 到 D-9 大多沒人用，還沒清。
- AI 四個新用途（講一句話請假補記、請假原因歸類、下一個該種哪個、挖出來的回顧）等多米選。
- 舊待辦：Anthropic 金鑰（多米自己跑 `npx wrangler secret put ANTHROPIC_API_KEY`）、ShujiAIBaseURL、內購商品、Apple ID、隱私權政策網址、iCloud 同步、鎖定畫面一按就記、真機手感。

## 📌 關鍵決策

- 四問沿用週回顧日：過了那天第一次打開就問，「晚點再說」隔天再問；長好了嗎的三張跳過隔 14 天。
- 月曆推翻舊的「田不做月曆」；完成率、連續天數照舊不做。
- 按住與記好用同一個 view，變形才沒有殘影。

## ⏭️ 下一步從哪繼續

1. 真機回饋 → 從 main 開新分支照改，出版 `gh workflow run testflight.yml --ref main`（排不到 Mac 機器就 `gh run rerun`）。

## 🧩 剩下的工作（工作包）

- [x] 完成的樣子變形
- [x] 併 main 出 TestFlight
- [ ] AI 打開與新用途（等多米選與金鑰）
