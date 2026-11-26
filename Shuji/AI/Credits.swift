import Foundation
import Observation
import Security
import StoreKit

// AI 點數（多米 2026-11-26 定：習慣格子買斷＋AI 點數，docs/規劃-點數收費-多習慣-AI對手與犒賞-2026-11-26.md 第一節）。
// 點數記在伺服器（server/src/credits.ts），對到這裡產生的匿名帳號。
// 走自己電腦的 Claude 不經過伺服器，不扣點，也不送帳號。

/// 匿名帳號：一個 UUID。存在 iCloud 鑰匙圈，換手機、重裝 app 都還在，點數才不會不見
enum CreditAccount {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "org.domyweb.shuji.credits",
        kSecAttrAccount as String: "account",
        kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
    ]
    /// 鑰匙圈存不進去時的退路：只在這支手機
    private static let fallbackKey = "shuji.credits.account"

    @MainActor private static var cached: String?

    @MainActor static var id: String {
        if let cached { return cached }
        let found = load() ?? UserDefaults.standard.string(forKey: fallbackKey)
        let id = found ?? UUID().uuidString
        if found == nil, !save(id) { UserDefaults.standard.set(id, forKey: fallbackKey) }
        cached = id
        return id
    }

    private static func load() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    private static func save(_ id: String) -> Bool {
        var item = base
        item[kSecValueData as String] = Data(id.utf8)
        // 要跟著 iCloud 走就不能用 ThisDeviceOnly
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

@MainActor
@Observable
final class Credits {
    static let shared = Credits()

    /// 跟 server/src/credits.ts 的 CREDIT_PRODUCTS 一樣。App Store Connect 要建成消耗型
    static let packs: [String: Int] = [
        "org.domyweb.shuji.credits30": 30,
        "org.domyweb.shuji.credits100": 100,
    ]
    static let freeCredits = 20

    /// 伺服器上剩幾點。nil 是還沒問過
    private(set) var balance: Int?
    private(set) var products: [Product] = []
    private(set) var busy = false
    var message: String?

    private init() {}

    /// 伺服器回應裡帶的 credits 都記下來
    func update(_ n: Int?) {
        if let n { balance = max(0, n) }
    }

    var balanceText: String? {
        balance.map { "剩 \($0) 點" }
    }

    // MARK: 跟伺服器

    private struct Ask: Encodable { var ts: Int; var account: String }
    private struct Redeem: Encodable { var ts: Int; var account: String; var jws: String }
    private struct Answer: Decodable { var balance: Int?; var added: Int?; var message: String? }

    private var ts: Int { Int(Date().timeIntervalSince1970) }

    func refresh() async {
        guard AIClient.shared.serverReady else { return }
        guard let body = try? JSONEncoder().encode(Ask(ts: ts, account: CreditAccount.id)),
              let r = try? await AIClient.shared.serverPost("v1/credits/balance", body: body, timeout: 20),
              r.status == 200, let a = try? JSONDecoder().decode(Answer.self, from: r.data) else { return }
        update(a.balance)
    }

    /// 把一筆點數交易送去加點。加成功（或伺服器說這筆已經加過）才 finish；失敗留著，下次打開再送
    @discardableResult
    func redeem(_ t: Transaction, jws: String) async -> Bool {
        guard AIClient.shared.serverReady,
              let body = try? JSONEncoder().encode(Redeem(ts: ts, account: CreditAccount.id, jws: jws)),
              let r = try? await AIClient.shared.serverPost("v1/credits/redeem", body: body, timeout: 30) else {
            return false
        }
        let a = try? JSONDecoder().decode(Answer.self, from: r.data)
        guard r.status == 200 else {
            message = a?.message ?? "點數還沒加上去，下次打開薯記會再試一次。"
            return false
        }
        update(a?.balance)
        await t.finish()
        return true
    }

    /// 打開 app 時：買了但還沒加上去的（上次斷線、閃退）再送一次
    func redeemUnfinished() async {
        for await result in Transaction.unfinished {
            guard case .verified(let t) = result, Self.packs[t.productID] != nil else { continue }
            await redeem(t, jws: result.jwsRepresentation)
        }
    }

    // MARK: 買

    func loadProducts() async {
        guard products.isEmpty else { return }
        let found = (try? await Product.products(for: Array(Self.packs.keys))) ?? []
        products = found.sorted { (Self.packs[$0.id] ?? 0) < (Self.packs[$1.id] ?? 0) }
    }

    func buy(_ product: Product) async {
        message = nil
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let t) = verification else {
                    message = "這筆購買驗證不過，沒有加點。"
                    return
                }
                if !(await redeem(t, jws: verification.jwsRepresentation)) {
                    message = message ?? "點數還沒加上去，下次打開薯記會再試一次。"
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            message = "沒買成，等一下再試。"
        }
    }
}
