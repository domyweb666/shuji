# Handoff: 地瓜全換 D、種到一半的可以種回來，已併 main，TestFlight 1.0（13）

> 2026-11-26 晚上。repo `E:\習慣地瓜\shuji`，main cb0d48b（併 overnight-20261126-1104）。上一份見 `.vibe/handoff/archive/`。整晚模式的完整紀錄在 `OVERNIGHT.md`。

## ✅ 現況
- 所有地瓜都是 D 了：土裡那顆（HoldButton 的 PotatoBody）、竹籃／挖出來／付費頁的 PotatoView、回來卡／對話／這週的田／田的「還太少」的有眼睛地瓜（PotatoFace，TalkPotato 與 WeekPotato 都包它）。畫法全在 `Shuji/Views/HoldButton.swift` 的 PotatoArt，改 D 只改那裡。
- PotatoView 的位子從 寬×0.68 變 寬×0.9（變高）；TalkPotato、WeekPotato 位子沒變。
- 竹籃「種到一半的」點進去有「現在種回來」「排進排隊」。種回來＝同一句同一時機重種一輪（新 id，藤從頭長，旅行版那句沒帶）；有種著的會先問。`Store.queueUnfinished / replantUnfinished`，`AppState.unfinished` 不列跟現在同一句的。
- 「你回來了」往上 30 點，放在黃色肉心（多米選 C，比較圖 `E:\習慣地瓜\你回來了位置比較.html`）。
- `docs/上架檢查-5.1.2-第三方AI.md`：送審前一定要補隱私權政策連結（`VeggieSetup.swift` 的 privacyURL 是 nil）；「連電腦加說明」「AI 設定加不再送到伺服器」多米說不做。
- main CI 全綠（run 45819707510）；TestFlight 1.0（13）已上傳（run 45821021131），等多米真機。

## ⏭️ 下一步
1. 等多米真機回饋，特別看：挖出來那頁、付費頁、竹籃的小地瓜大小；回來卡和這週的田的 D 加眼睛；「你回來了」位置；種回來流程。
2. Limrun `tools/limrun/states.mjs` 的存檔是舊格式（logs），記好、跳過狀態拍不出來；要用就改成 records 格式。
3. 上架前寫隱私權政策並填網址。

## 📌 定了的（別再問）
- 地瓜一律 D。「你回來了」用 C。5.1.2 那兩件不做。
- 提交要指定檔名；不開 worktree；repo 是 PUBLIC，推之前問。
