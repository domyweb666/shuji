import CryptoKit
import DeviceCheck
import Foundation

/// 薯記的 AI 中繼伺服器用戶端。
/// - 金鑰不在 app 裡：app 只跟自己的伺服器說話，伺服器才去叫 Claude。
/// - 這台裝置第一次用時跟伺服器做一次 App Attest 註冊；之後每個請求都帶 assertion，簽的是整個 body。
/// - 模擬器沒有 App Attest：Debug 建置可以在設定頁測試區貼開發用通行碼。
/// - 任何失敗都回一句給人看的話，畫面接著回到手動流程。手動流程永遠可用。
@MainActor
final class AIClient {
    static let shared = AIClient()

    enum Outcome<T> {
        case result(T)
        /// 護欄包第六節：不適合用這個 app，顯示固定轉介文字
        case unfit(category: String?, referral: String)
    }

    struct Failure: Error {
        var message: String
        var rateLimited = false
    }

    static let fallbackMessage = "現在想不出來，你先自己填，等一下再試。"

    // MARK: 設定

    private enum Keys {
        static let keyId = "shuji.ai.keyId"
        static let registered = "shuji.ai.registered"
        static let consent = "shuji.ai.consent"
        static let device = "shuji.ai.devDevice"
        static let devToken = "shuji.ai.devToken"
        static let baseOverride = "shuji.ai.baseURL"
    }

    private let defaults = UserDefaults.standard

    /// 伺服器網址：Info.plist 的 ShujiAIBaseURL；Debug 建置可以在測試區蓋掉。空的就代表 AI 沒接上，按鈕都不出現。
    var baseURL: URL? {
        #if DEBUG
        if let s = defaults.string(forKey: Keys.baseOverride), !s.isEmpty, let u = URL(string: s) { return u }
        #endif
        guard let s = Bundle.main.object(forInfoDictionaryKey: "ShujiAIBaseURL") as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var isAvailable: Bool {
        guard baseURL != nil else { return false }
        return DCAppAttestService.shared.isSupported || devToken != nil
    }

    var hasConsented: Bool {
        get { defaults.bool(forKey: Keys.consent) }
        set { defaults.set(newValue, forKey: Keys.consent) }
    }

    #if DEBUG
    var devTokenSetting: String {
        get { defaults.string(forKey: Keys.devToken) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.devToken) }
    }
    var baseURLOverride: String {
        get { defaults.string(forKey: Keys.baseOverride) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.baseOverride) }
    }
    #endif

    private var devToken: String? {
        #if DEBUG
        let t = defaults.string(forKey: Keys.devToken) ?? ""
        return t.isEmpty ? nil : t
        #else
        return nil
        #endif
    }

    private var devDevice: String {
        if let d = defaults.string(forKey: Keys.device) { return d }
        let d = UUID().uuidString
        defaults.set(d, forKey: Keys.device)
        return d
    }

    // MARK: 呼叫任務

    func run<I: Encodable, O: Decodable>(_ task: AITask, input: I, habitId: String? = nil, as type: O.Type) async throws -> Outcome<O> {
        guard let base = baseURL else { throw Failure(message: Self.fallbackMessage) }
        let body = try JSONEncoder().encode(AIEnvelope(ts: Int(Date().timeIntervalSince1970), habit_id: habitId, input: input))
        let url = base.appendingPathComponent("v1/task/\(task.rawValue)")

        var lastError: Error = Failure(message: Self.fallbackMessage)
        // 網路斷掉重試一次；裝置沒註冊（伺服器資料被清掉）就重新註冊一次
        for attempt in 0..<2 {
            do {
                var req = URLRequest(url: url, timeoutInterval: 60)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "content-type")
                req.httpBody = body
                try await sign(&req, body: body, base: base)
                let (data, resp) = try await URLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 { return try decode(data, as: O.self) }
                let err = try? JSONDecoder().decode(ErrorBody.self, from: data)
                if err?.error == "not_registered", attempt == 0 {
                    defaults.removeObject(forKey: Keys.registered)
                    continue
                }
                throw Failure(message: err?.message ?? Self.fallbackMessage, rateLimited: status == 429)
            } catch let f as Failure {
                throw f
            } catch {
                lastError = error
                if attempt == 0 { continue }
            }
        }
        throw (lastError as? Failure) ?? Failure(message: Self.fallbackMessage)
    }

    private struct ErrorBody: Decodable {
        var error: String?
        var message: String?
    }

    private func decode<O: Decodable>(_ data: Data, as type: O.Type) throws -> Outcome<O> {
        let probe = try JSONDecoder().decode(AIProbe.self, from: data)
        if probe.result.type == "unfit" {
            return .unfit(category: probe.result.category, referral: probe.referral ?? Phrases.referralFallback)
        }
        return .result(try JSONDecoder().decode(AIResultBody<O>.self, from: data).result)
    }

    // MARK: App Attest

    private func sign(_ req: inout URLRequest, body: Data, base: URL) async throws {
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            guard let token = devToken else { throw Failure(message: "這台裝置不支援 App 驗證，AI 先不能用。") }
            req.setValue(token, forHTTPHeaderField: "x-shuji-dev-token")
            req.setValue(devDevice, forHTTPHeaderField: "x-shuji-device")
            return
        }
        let keyId = try await registeredKey(base: base)
        let hash = Data(SHA256.hash(data: body))
        let assertion: Data
        do {
            assertion = try await service.generateAssertion(keyId, clientDataHash: hash)
        } catch {
            // key 失效（重灌、換機還原）：丟掉重來
            forgetKey()
            let fresh = try await registeredKey(base: base)
            assertion = try await service.generateAssertion(fresh, clientDataHash: hash)
            req.setValue(fresh, forHTTPHeaderField: "x-shuji-key")
            req.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "x-shuji-assertion")
            return
        }
        req.setValue(keyId, forHTTPHeaderField: "x-shuji-key")
        req.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "x-shuji-assertion")
    }

    private func forgetKey() {
        defaults.removeObject(forKey: Keys.keyId)
        defaults.removeObject(forKey: Keys.registered)
    }

    /// 拿到一把已經在伺服器註冊過的 key；沒有就產生、跟伺服器要挑戰、做 attestation、註冊
    private func registeredKey(base: URL) async throws -> String {
        let service = DCAppAttestService.shared
        if let id = defaults.string(forKey: Keys.keyId), defaults.bool(forKey: Keys.registered) { return id }
        let keyId: String
        if let id = defaults.string(forKey: Keys.keyId) {
            keyId = id
        } else {
            keyId = try await service.generateKey()
            defaults.set(keyId, forKey: Keys.keyId)
        }

        struct Challenge: Decodable { var challenge: String }
        var creq = URLRequest(url: base.appendingPathComponent("v1/attest/challenge"), timeoutInterval: 30)
        creq.httpMethod = "POST"
        creq.httpBody = Data("{}".utf8)
        let (cdata, _) = try await URLSession.shared.data(for: creq)
        let challenge = try JSONDecoder().decode(Challenge.self, from: cdata).challenge

        let attestation: Data
        do {
            attestation = try await service.attestKey(keyId, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
        } catch {
            // 這把 key 已經 attest 過或壞了：換一把
            forgetKey()
            throw Failure(message: Self.fallbackMessage)
        }

        struct Register: Encodable { var keyId: String; var attestation: String; var challenge: String }
        var rreq = URLRequest(url: base.appendingPathComponent("v1/attest/register"), timeoutInterval: 30)
        rreq.httpMethod = "POST"
        rreq.setValue("application/json", forHTTPHeaderField: "content-type")
        rreq.httpBody = try JSONEncoder().encode(Register(keyId: keyId, attestation: attestation.base64EncodedString(), challenge: challenge))
        let (_, rresp) = try await URLSession.shared.data(for: rreq)
        guard (rresp as? HTTPURLResponse)?.statusCode == 200 else {
            forgetKey()
            throw Failure(message: "這台裝置驗證不過，AI 先不能用。")
        }
        defaults.set(true, forKey: Keys.registered)
        return keyId
    }
}


// 泛型函式裡不能宣告巢狀型別，放在檔案層級
private struct AIEnvelope<X: Encodable>: Encodable {
    var ts: Int
    var habit_id: String?
    var input: X
}

private struct AIProbe: Decodable {
    var result: UnfitProbe
    var referral: String?
}

private struct AIResultBody<X: Decodable>: Decodable {
    var result: X
}
