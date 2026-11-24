# 讓手機上的薯記用這台電腦的 Claude

薯記的 AI 送出去之後，會到這台電腦，交給你登入的 `claude` 想，再把結果送回手機。不用 API 金鑰，用的是你的 Claude 訂閱額度。

## 怎麼開

電腦要裝好 Claude Code，而且登入過（終端機打 `claude --version` 有版本號）。

```powershell
cd E:\習慣地瓜\shuji\server
```

第一次用要先裝套件：

```powershell
npm install
```

之後每次開：

```powershell
npm run bridge
```

終端機會印一個 QR code。手機打開薯記 → 設定 → AI → 連電腦的 Claude，掃它。

iPhone 第一次會問要不要讓薯記找區域網路上的裝置，按允許。Windows 防火牆第一次也會問要不要讓 Node.js 連線，勾私人網路再按允許。

用完按 Ctrl+C。密碼每次開都會換，重開之後手機要再掃一次。

電腦有好幾張網卡時會印好幾行網址，QR code 只畫第一個。第一個連不上，就把別行貼進手機。

要換埠號或模型：

```powershell
$env:PORT=8792; npm run bridge
```

```powershell
$env:CLAUDE_MODEL="sonnet"; npm run bridge
```

## 連不上的時候

1. 這支程式還開著嗎。
2. 手機和電腦是不是同一個 Wi-Fi。
3. iPhone 設定 → 隱私權與安全性 → 區域網路，薯記有沒有打開。
4. Windows 安全性 → 防火牆與網路保護 → 允許應用程式通過防火牆，Node.js 有沒有打勾。

## 擋了什麼

拿到網址的人可以用你的額度跑薯記的七個任務，拿不到電腦上的檔案：

- 半形 `@` 換成全形，CLI 不會把檔案附進去；CLI 自己的附檔功能也關掉。
- 沒有工具、沒有 MCP、不讀 `~/.claude` 的設定和 `CLAUDE.md`、不存對話。
- 在一個空的暫存資料夾裡跑，結束時刪掉。
- 環境變數只帶跑得起來要的那幾個，各家金鑰都不帶。
- 只收薯記的輸入格式，一次最多 8 KB。同時跑一句，後面最多排兩句，一句最多 170 秒。
- 回給手機的錯誤是固定的幾句，不帶電腦上的路徑。你寫的字不會印在終端機上。

## 沒擋的、沒驗的

- 區網走明碼 http。同一個 Wi-Fi 上有人監聽的話，看得到密碼和你寫的字。在自己家裡開，用完就關。
- CLI 用你的帳號跑，沒有另外隔離。
- 關掉附檔那幾個環境變數在 `claude --help` 裡查不到，CLI 升級之後要重驗（蘿蔔旅行 2026-11-24 在 2.1.81 攔下來看過）。
- Mac 和 Linux 沒跑過。
- 訂閱能不能這樣用，沒有查過 Anthropic 的條款。只給自己用。

## 協定

每個請求都帶 `?t=<密碼>`，不對就 401 `bad_token`。

- `GET /ping`：`{"ok":true,"name":"<電腦名>","cli":"2.1.81 (Claude Code)"}`
- `POST /v1/task/{1-7}`：body 和回傳跟正式伺服器一樣（`src/app.ts`），不用 App Attest，也不數次數。

出錯一律 `{"ok":false,"error":"…","message":"給人看的一句"}`：`bad_request`（400、404、405、413）、`rate_limited`（429）、`cli_login`、`bad_output`（502）、`timeout`（504）、`unavailable`（500）。

`npm test` 裡的 `test/bridge.test.ts` 用一支假的 CLI 檢查上面這些，不花額度。
