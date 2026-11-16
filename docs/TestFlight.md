# 沒有 Mac 也能上 TestFlight

簽章和上傳都在 GitHub Actions 的 macOS 機器上做。憑證和 API 金鑰沿用人蔘修煉那一套，同一個 Apple 帳號不用重新申請。

設定只做一次，共三步。之後每次要出新版，到 Actions 按一下就好。

## 第一步：設六個 Secrets

GitHub 不能跨 repo 複製 Secret，設過的值也讀不回來，所以要用原始檔再設一次。名稱跟人蔘修煉一樣。

在終端機（Git Bash）執行。每一行都帶了 `-R domyweb666/shuji`，在哪個資料夾跑都可以。

Team ID 和 Key ID 不是秘密，已經設好了：

| Secret | 值 |
|---|---|
| `APPLE_TEAM_ID` | `3ZT74P4WM2` |
| `ASC_KEY_ID` | `F3286X6SY3` |

剩下四個要你來。

API 金鑰檔，直接把檔案內容送進去（這個 Secret 叫 `ASC_PRIVATE_KEY` 也可以，流程兩個名稱都收）：

```bash
gh secret set ASC_KEY_P8_BASE64 -R domyweb666/shuji < "E:/人篸修煉/AuthKey_F3286X6SY3.p8"
```

Issuer ID，執行後會請你貼上。它在 App Store Connect 的「使用者與存取權限 → 整合 → App Store Connect API」頁面最上面，是一串有連字號的英數字：

```bash
gh secret set ASC_ISSUER_ID -R domyweb666/shuji
```

發行憑證 `.p12`，把路徑換成你那個檔案的位置：

```bash
base64 -w0 "這裡換成 .p12 的完整路徑" | gh secret set APPLE_DIST_P12_BASE64 -R domyweb666/shuji
```

`.p12` 的密碼，執行後會請你貼上：

```bash
gh secret set APPLE_DIST_P12_PASSWORD -R domyweb666/shuji
```

設完可以檢查，應該列出六個名稱：

```bash
gh secret list -R domyweb666/shuji
```

找不到 `.p12` 的話，到 developer.apple.com 的 Certificates 頁重新申請一張 Apple Distribution 憑證。申請檔和私鑰已經在 `E:\習慣地瓜\簽章\`（`shuji-dist.csr`、`shuji-dist.key`），下載回來的 `.cer` 放進同一個資料夾，再請 Claude 合成 `.p12`。

## 第二步：在 Apple 後台登記 App ID

到 https://developer.apple.com/account/resources/identifiers/list

先建 App Group（左上角下拉選 App Groups → 加號）：

- Identifier：`group.org.domyweb.shuji`

再建兩個 App ID（下拉選 App IDs → 加號 → App）：

| Bundle ID | 要勾的能力 |
|---|---|
| `org.domyweb.shuji` | App Groups、App Attest |
| `org.domyweb.shuji.widget` | App Groups |

兩個 App ID 勾完 App Groups 之後，都要按旁邊的 Configure，把 `group.org.domyweb.shuji` 選進去。漏了這一步，小工具會一直顯示「還沒種東西」。

## 第三步：在 App Store Connect 建 app

到 https://appstoreconnect.apple.com/apps → 加號 → 新 App

- 平台：iOS
- 名稱：薯記
- 主要語言：繁體中文
- Bundle ID：選 `org.domyweb.shuji`
- SKU：`shuji`

## 出新版

GitHub → Actions → 左邊選「上 TestFlight」→ Run workflow → 選 main → Run。

大約十到十五分鐘跑完。之後 Apple 還要處理幾分鐘到半小時，好了會出現在 App Store Connect 的 TestFlight 頁。

建置編號用的是這個流程的執行序號，每跑一次自動加一，不用手動改。

## 裝到手機

1. App Store Connect → 薯記 → TestFlight → 內部測試 → 加號建一個群組，把自己加進去。
2. iPhone 裝 TestFlight，用同一個 Apple ID 登入，就會看到薯記。
3. 之後每個新版 TestFlight 會推通知，點一下更新。

## 跑紅了怎麼看

| 紅在哪一步 | 多半是什麼 |
|---|---|
| 檢查六個 Secrets 都設了 | 訊息會列出還沒設的名稱，回第一步補 |
| 還原發佈憑證 | `.p12` 或密碼不對 |
| 還原 App Store Connect API 金鑰 | `.p8` 內容放錯，重跑第一步那一行 |
| 向 Apple 申請上架用描述檔 | App ID 還沒登記（第二步），或這張憑證已經被撤銷 |
| archive | 描述檔沒帶到 App Group，回第二步檢查 Configure 有沒有選 |
| 上傳 App Store Connect | 第三步的 app 還沒建，或同一個建置編號已經傳過 |

## 還沒驗證的地方

- 這套流程在薯記還沒實際跑過。人蔘修煉跑通的是同一套，但薯記多了 App Attest，第一次跑有可能要調整。
- AI 的裝置驗證（App Attest）只有 TestFlight 或 App Store 版才是正式環境，要裝到真機按過 AI 入口才知道通不通。
