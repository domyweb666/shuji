import Foundation
import Security

// 電腦的 Claude：電腦上跑 server/bridge，手機掃它印的 QR code，AI 任務就交給那台電腦的 claude CLI。
// 網址含密碼，存鑰匙圈，不進備份的 JSON。

struct BridgeLink: Codable, Equatable {
    /// http://192.168.0.173:8791（不含路徑和密碼）
    var base: URL
    var token: String
    /// 電腦名（連上時電腦回的）
    var name: String

    /// 認 QR code 或貼上的網址：http://<區網位址>:<埠>/shuji?t=<32 個 16 進位字>。不是就回 nil
    static func parse(_ raw: String) -> BridgeLink? {
        guard let u = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              u.scheme == "http", u.user == nil, u.password == nil,
              let host = u.host, isLocal(host), u.path == "/shuji",
              let token = u.queryItems?.first(where: { $0.name == "t" })?.value,
              token.count == 32, token.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        var b = URLComponents()
        b.scheme = "http"
        b.host = host
        b.port = u.port
        guard let base = b.url else { return nil }
        return BridgeLink(base: base, token: token, name: host)
    }

    /// 只連同一個區網裡的電腦，別的網址不收
    static func isLocal(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".local") { return true }
        let p = h.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard p.count == 4, h.split(separator: ".", omittingEmptySubsequences: false).count == 4,
              p.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (p[0], p[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        case (100, 64...127): return true
        default: return false
        }
    }

    func url(_ path: String) -> URL {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        c.path = "/" + path
        c.queryItems = [URLQueryItem(name: "t", value: token)]
        return c.url ?? base
    }
}

/// 字要送去哪裡。換了去處就要再問一次同意
enum AIDestination: Equatable {
    case computer(name: String)
    case server(host: String)

    /// 電腦優先，沒有才用薯記的伺服器
    static func pick(bridge: BridgeLink?, server: URL?) -> AIDestination? {
        if let bridge { return .computer(name: bridge.name) }
        if let server { return .server(host: server.host ?? server.absoluteString) }
        return nil
    }

    var consentKey: String {
        switch self {
        case .computer(let name): return "shuji.ai.consent.computer.\(name)"
        case .server(let host): return "shuji.ai.consent.server.\(host)"
        }
    }
}

/// 鑰匙圈裡那一格。只在這支手機、開機解鎖過後讀得到，不跟著 iCloud 走
enum BridgeStore {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "org.domyweb.shuji.claude-bridge",
        kSecAttrAccount as String: "default",
    ]

    static func load() -> BridgeLink? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(BridgeLink.self, from: data)
    }

    /// 先改舊的，沒有舊的才新增；失敗時舊的還在
    static func save(_ link: BridgeLink) -> Bool {
        guard let data = try? JSONEncoder().encode(link) else { return false }
        let fields: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(base as CFDictionary, fields as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        return SecItemAdd(base.merging(fields) { $1 } as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(base as CFDictionary)
    }
}
