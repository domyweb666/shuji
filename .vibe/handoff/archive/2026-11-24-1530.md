# Handoff: 今天頁拿字、田改報表、四問自動跳（分支 done-shape）

> 產出時間：2026-11-24 15:30
> repo：`E:\習慣地瓜\shuji`（外層 `E:\習慣地瓜` 不是 git repo）
> 分支：`done-shape`（從 main 60a97ea 開，已 push，沒開 PR、沒併）

## ✅ 這次完成了什麼

- 今天頁記好後只剩開關句；地瓜上只有打勾。
- 田改成「月曆｜分析」（`Shuji/Views/FieldView.swift`，數字在 `Shuji/Core/FieldReport.swift`）；竹籃＋排隊收在右上角。
- 開始四問、壓力週、放手、挖地瓜改成打開 app 自動問（`AppState.autoAsk`、`Store.nextAsk`、`RootView`、`AskSheet`）。
- 選項畫布：https://claude.ai/artifact/YGYgSPzPEMFESfPjbvrJYD （完成樣子 A–E、田 A／B、兩張跳出）。

## 🚧 還沒做完 / 待決定

- 多米選完成的樣子（A 打勾形是推薦），選了才寫變形。A 的變形做法：外框在極座標上從橢圓內插到打勾形，按住和記好用同一個 view 才不會有殘影；根要改連到打勾的長邊尖端（VineView 的 potatoTop 加 x）。
- 田 A 已經做進程式；多米若選 B 再改。
- `tools/limrun/test.mjs` 還是舊流程（四問的按鈕、田的字），要改寫才能跑；看畫面用 `states.mjs`。
- AnalyticsCopy 裡 D-1 到 D-9 大多沒人用了，還沒清。
- 舊的待辦：Anthropic 金鑰（多米自己跑 `npx wrangler secret put ANTHROPIC_API_KEY`）、ShujiAIBaseURL、內購商品、Apple ID、隱私權政策網址、iCloud 同步、真機手感。

## 📌 關鍵決策

- 四問的時機沿用週回顧日：過了那天第一次打開就問，按「晚點再說」隔天再問。
- 月曆推翻了舊的「田不做月曆」；完成率、連續天數照舊不做。

## ⏭️ 下一步從哪繼續

1. 多米選完成的樣子 → 在 done-shape 寫變形 → `gh workflow run ios.yml --ref done-shape` → `node tools/limrun/states.mjs` → 問要不要併 main 出 TestFlight。

## 🧩 剩下的工作（工作包）

- [ ] 完成的樣子變形（等多米選）
- [ ] AI 打開與四個 AI 新用途（等多米選與金鑰）
