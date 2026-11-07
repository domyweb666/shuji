# 沒有 Mac 也能上 TestFlight

簽章和上傳都在 GitHub Actions 的 macOS 機器上做，你只要在 Apple 網站點幾下、把三個檔案交給電腦這邊。做一次就好，之後每次按一下 Actions 就會有新版進 TestFlight。

## 你要做的（都在瀏覽器）

### 1. 申請發行憑證

1. 電腦上已經有申請檔：`E:\習慣地瓜\簽章\shuji-dist.csr`（私鑰 `shuji-dist.key` 在旁邊，只留在這台電腦，別上傳）。
2. 到 https://developer.apple.com/account/resources/certificates/add
3. 選 **Apple Distribution** → Continue → Choose File 選 `shuji-dist.csr` → Continue → Download。
4. 下載的 `distribution.cer` 放進 `E:\習慣地瓜\簽章\`。

### 2. 建 App Store Connect API 金鑰

1. 到 https://appstoreconnect.apple.com/access/integrations/api
2. 第一次會要你「Request Access」，按了就好。
3. Team Keys → 加號 → 名稱隨便（例如 shuji-ci）→ Access 選 **App Manager** → Generate。
4. 記下畫面上的 **Issuer ID**（上面那串）和這把 key 的 **Key ID**。
5. 按 Download API Key，拿到 `AuthKey_XXXXXXXXXX.p8`，放進 `E:\習慣地瓜\簽章\`。**只能下載一次**，弄丟就重建一把。

### 3. 找 Team ID

https://developer.apple.com/account → 往下捲到 Membership details → **Team ID**（十個英數字）。

### 4. 把這些交回來

跟 Claude 說：`.cer` 和 `.p8` 放好了，Key ID 是 XXX、Issuer ID 是 XXX、Team ID 是 XXX。接下來打包 p12、設 GitHub Secrets、跑第一次都是電腦這邊做。

### 5. 第一次跑完之後

第一次跑 Actions 會把 App ID（org.domyweb.shuji、org.domyweb.shuji.widget）和 App Group 自動登記到你的帳號，但 App Store Connect 上還沒有「薯記」這個 app，所以上傳那步會失敗一次。這時：

1. 到 https://appstoreconnect.apple.com/apps → 加號 → New App
2. 平台 iOS、名稱 **薯記**、主要語言 繁體中文、Bundle ID 選 **org.domyweb.shuji**、SKU 填 shuji → Create
3. 再跑一次 Actions，這次會進 TestFlight。

### 6. 裝到手機

1. App Store Connect → 薯記 → TestFlight → Internal Testing → 加號建一個群組（例如 自己）→ 把自己加進去。
2. iPhone 裝 TestFlight app，用同一個 Apple ID 登入，就會看到薯記。
3. 之後每個新版本 TestFlight 會推通知，點一下更新。

## 電腦這邊做的（Claude 來）

- `distribution.cer` ＋ `shuji-dist.key` → `shuji-dist.p12`（openssl）
- 六個 GitHub Secrets：`APPLE_TEAM_ID`、`APPLE_DIST_P12_BASE64`、`APPLE_DIST_P12_PASSWORD`、`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8_BASE64`
- Actions 的「上 TestFlight」流程：裝憑證 → Xcode 自動簽章 archive（會自己建描述檔）→ 匯出直接上傳
- 建置編號用 Actions 的執行序號，所以每次都會往上加，不用手動改

## 常見狀況

- **上傳說找不到 app record**：第 5 步還沒做，去 App Store Connect 建 app。
- **憑證說已經有一張但私鑰不在**：帳號裡本來就有別的 Apple Distribution 憑證，沒關係，這裡用的是自己這張；真的擋住就到 Certificates 頁把舊的撤銷。
- **小工具顯示「還沒種東西」**：App Group 沒簽進去。走這條路 Xcode 會自動處理，Sideloadly 那條才會碰到。
- **TestFlight 問加密**：Info.plist 已經寫了沒用到非豁免加密，不會問。
