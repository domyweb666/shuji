# Handoff: 地瓜換 B、規劃加對手與犒賞；多習慣與點數收費排隊中

> 2026-11-26 深夜。repo `E:\習慣地瓜\shuji`，分支 `potato-b`（從 main cb0d48b 開出，已 push，沒併 main）。上一份見 `.vibe/handoff/archive/2026-11-26-all-D.md`。

## ✅ 現況
- 地瓜一律換成 B（多米給的圖 1）：橫躺長條彎身、一根細根，記好了縱切攤開冒煙。畫法只在 `Shuji/Views/HoldButton.swift` 的 PotatoArt／BShape；小地瓜用 `PotatoArt.fit` 照位子塞滿。預覽 `E:\習慣地瓜\地瓜B-1126\預覽.html`。
- 任務 8 規劃習慣多三步：對手 → 擋對手 → 犒賞（三選一，可「先不用」；對手跳過就不問擋對手）。知識包搭建第八節、提示詞、伺服器檢查、Habit 三欄（rival／block／reward）、種下去那頁、今天頁「給自己：…」、我的習慣頁可改。
- 伺服器測試 128 個全過；Swift 沒本機編譯，CI 結果看 `gh run list --branch potato-b`。
- **伺服器要重新部署**新步驟才會通（舊伺服器收到 step=rival 會回 400）；電腦 Claude 那條重開 `npm run bridge` 就好。中文路徑下 wrangler deploy 會靜默失敗，記得。

## ⏭️ 下一步（多米已點頭）
1. 多習慣：首頁加切換選單（多米要能同時養健身、冥想、看書），免費同時 2 個、買斷最多 5 個。資料 `state.habit` 改成清單，紀錄本來就有 habit id。設計在 `docs/規劃-點數收費-多習慣-AI對手與犒賞-2026-11-26.md` 第二節（「一排小地瓜」作廢，改選單）。
2. 點數收費：習慣格子買斷＋AI 點數（新裝 20 點、30 點 NT$60、100 點 NT$150、用電腦 Claude 不扣）。伺服器記帳、驗 StoreKit 交易。App Store Connect 建商品要先問多米。
3. 多米真機看 B 地瓜大小與三步規劃的手感。

## 📌 定了的（別再問）
- 地瓜一律 B。收費照規劃文件第一節。多習慣用切換選單。
- 提交要指定檔名；不開 worktree；repo 是 PUBLIC，推之前問（這次多米說了 push）。
