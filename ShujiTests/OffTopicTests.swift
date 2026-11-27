import XCTest
@testable import Shuji

/// 偏題防線（docs/正式接AI-規劃與防偏題-2026-11-27.md）：任務 1、2、3、4、6 回 off_topic 時，app 顯示寫死的一句，不顯示模型的字
@MainActor
final class OffTopicTests: XCTestCase {
    func testOffTopicBecomesFailureExceptPlan() {
        for task in [AITask.plant, .obstacle, .rival, .diagnose, .audit] {
            XCTAssertTrue(AIClient.treatsOffTopicAsFailure(task, type: "off_topic"), "\(task)")
        }
        XCTAssertFalse(AIClient.treatsOffTopicAsFailure(.plan, type: "off_topic"), "任務 8 由 TalkModel 自己處理")
        XCTAssertFalse(AIClient.treatsOffTopicAsFailure(.rival, type: "ok"))
    }

    /// 伺服器 checks.ts 的 OFF_TOPIC_BLANK 長這樣；就算哪天 app 直接解它，也不能壞
    func testOffTopicBlankDecodesForEveryTask() throws {
        func decode<T: Decodable>(_ json: String, _ type: T.Type) throws {
            _ = try JSONDecoder().decode(type, from: Data(json.utf8))
        }
        try decode(#"{"type":"off_topic","floors":[],"triggers":[],"example":"","note":"","category":null,"message":null}"#, PlantOutput.self)
        try decode(#"{"type":"off_topic","obstacles":[],"backup":null,"travel":null,"note":"","category":null,"message":null}"#, ObstacleOutput.self)
        try decode(#"{"type":"off_topic","rival_type":null,"block":"","clear":"","note":"","category":null,"message":null}"#, RivalOutput.self)
        try decode(#"{"type":"off_topic","layer":0,"field":null,"suggestion":"","why":"","closing":"","category":null,"message":null}"#, DiagnoseOutput.self)
        try decode(#"{"type":"off_topic","path":"keep","change":"","why":"","warn":"","category":null,"message":null}"#, AuditOutput.self)
    }
}
