import XCTest
@testable import Shuji

@MainActor
final class CreditsTests: XCTestCase {
    /// 伺服器只收這個樣子的帳號（server/src/credits.ts 的 isAccount）
    func testAccountLooksLikeWhatServerAccepts() {
        let id = CreditAccount.id
        XCTAssertNotNil(id.range(of: "^[A-Fa-f0-9-]{32,40}$", options: .regularExpression))
        XCTAssertEqual(CreditAccount.id, id, "同一次執行要拿到同一個帳號")
    }

    /// 跟 server/src/credits.ts 的 CREDIT_PRODUCTS 對得上
    func testPacksMatchServer() {
        XCTAssertEqual(Credits.packs["org.domyweb.shuji.credits30"], 30)
        XCTAssertEqual(Credits.packs["org.domyweb.shuji.credits100"], 100)
        XCTAssertEqual(Credits.packs.count, 2)
    }

    func testBalanceKeepsLastKnownAndNeverNegative() {
        let c = Credits.shared
        c.update(7)
        XCTAssertEqual(c.balanceText, "剩 7 點")
        c.update(nil)
        XCTAssertEqual(c.balance, 7, "回應沒帶點數就不動")
        c.update(-3)
        XCTAssertEqual(c.balance, 0)
    }
}
