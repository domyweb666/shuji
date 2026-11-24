import XCTest
@testable import Shuji

final class BridgeTests: XCTestCase {
    private let token = "0123456789abcdef0123456789abcdef"

    func testParsesQRCode() throws {
        let link = try XCTUnwrap(BridgeLink.parse(" http://192.168.0.173:8791/shuji?t=\(token)\n"))
        XCTAssertEqual(link.base.absoluteString, "http://192.168.0.173:8791")
        XCTAssertEqual(link.token, token)
        XCTAssertEqual(link.name, "192.168.0.173")
        XCTAssertEqual(link.url("ping").absoluteString, "http://192.168.0.173:8791/ping?t=\(token)")
        XCTAssertEqual(link.url("v1/task/7").absoluteString, "http://192.168.0.173:8791/v1/task/7?t=\(token)")
    }

    func testRejectsOtherURLs() {
        for s in [
            "", "hello",
            "https://example.com/shuji?t=\(token)",
            "http://example.com/shuji?t=\(token)",
            "http://8.8.8.8:8791/shuji?t=\(token)",
            "http://172.32.0.1/shuji?t=\(token)",
            "http://192.168.0.1.evil.com/shuji?t=\(token)",
            "http://user@192.168.0.1/shuji?t=\(token)",
            "http://192.168.0.173:8787/ask?t=\(token)",
            "http://192.168.0.173:8791/shuji",
            "http://192.168.0.173:8791/shuji?t=short",
            "http://192.168.0.173:8791/shuji?t=zzzz456789abcdef0123456789abcdef",
        ] {
            XCTAssertNil(BridgeLink.parse(s), s)
        }
    }

    func testLocalHosts() {
        for h in ["10.0.0.5", "172.16.0.1", "172.31.255.1", "192.168.1.1", "100.64.0.1", "my-pc.local", "localhost"] {
            XCTAssertTrue(BridgeLink.isLocal(h), h)
        }
        for h in ["172.15.0.1", "100.128.0.1", "192.169.0.1", "256.1.1.1", "10.0.0", "10.0.0.x", "local"] {
            XCTAssertFalse(BridgeLink.isLocal(h), h)
        }
    }

    func testComputerGoesFirst() throws {
        let link = try XCTUnwrap(BridgeLink.parse("http://192.168.0.173:8791/shuji?t=\(token)"))
        let server = URL(string: "https://shuji.example.com")!
        XCTAssertEqual(AIDestination.pick(bridge: link, server: server), .computer(name: "192.168.0.173"))
        XCTAssertEqual(AIDestination.pick(bridge: nil, server: server), .server(host: "shuji.example.com"))
        XCTAssertNil(AIDestination.pick(bridge: nil, server: nil))
    }

    /// 換一台電腦、換成伺服器，都是另一把 key，要再問一次
    func testConsentKeyFollowsDestination() {
        let keys = [AIDestination.computer(name: "多米"), .computer(name: "另一台"), .server(host: "a.com"), .server(host: "多米")].map(\.consentKey)
        XCTAssertEqual(Set(keys).count, 4)
        XCTAssertFalse(keys.contains("shuji.ai.consent"), "舊的單一旗標不再算數")
    }

    func testLinkSurvivesKeychainCoding() throws {
        var link = try XCTUnwrap(BridgeLink.parse("http://10.0.0.2:8791/shuji?t=\(token)"))
        link.name = "多米"
        XCTAssertEqual(try JSONDecoder().decode(BridgeLink.self, from: JSONEncoder().encode(link)), link)
    }

    /// 2026-11-25 電腦轉接真的跑 claude CLI 回來的 result
    func testDecodesRealBridgeAnswers() throws {
        let guide = #"{"type":"propose","say":"滑手機是那個時刻的對手，前兩組讓球鞋先於手機出現。","question":"","options":[],"plans":[{"trigger":"下班進門，放下包包時","floor":"換上球鞋，走到門口"},{"trigger":"脫下上班的鞋時","floor":"換上球鞋，走到門口"}],"difficulty":"hard","weeks_min":10,"weeks_max":20,"reason":"要換裝、走到門口，身體還要出力，步驟比較多，所以週數拉長。","category":null,"message":null}"#
        XCTAssertEqual(try JSONDecoder().decode(GuideOutput.self, from: Data(guide.utf8)).plans.count, 2)
        let obstacle = #"{"type":"ok","obstacles":[{"if":"早上要趕出門","then":"在出門的路上用手機寫一句"}],"backup":"如果中午前還沒打開檔案寫一句，就在第一餐吃完時做。","travel":{"portable":true,"floor":"打開檔案寫一個字","alt":""},"note":"週末把杯子先放在床邊，醒來就看得到。","category":null,"message":null}"#
        let o = try JSONDecoder().decode(ObstacleOutput.self, from: Data(obstacle.utf8))
        XCTAssertEqual(o.obstacles.first?.then, "在出門的路上用手機寫一句")
        XCTAssertEqual(o.travel?.portable, true)
    }
}
