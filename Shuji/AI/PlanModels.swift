import Foundation

// 任務 8 規劃習慣的輸入與輸出，欄位名跟 server/src/tasks.ts 一字不差。
// 一步問一次：最小一步 → 時機 → 難度。天數不問 AI，HabitDifficulty 填。

struct PlanInput: Encodable, Equatable {
    enum Step: String, Encodable { case floor, trigger, estimate }

    var step: Step
    var goal: String
    var floor: String
    var trigger: String
    /// 給過、他不要的選項
    var exclude: [String]

    static let goalLimit = 60
    static let floorLimit = 40
    static let triggerLimit = 30
    static let excludeLimit = 12
}

struct PlanOutput: Decodable, Equatable {
    var type: String          // options | estimate | off_topic | unfit（unfit 在 AIClient 就攔下來了）
    var lead: String
    var options: [String]
    var difficulty: HabitDifficulty?

    enum CodingKeys: String, CodingKey { case type, lead, options, difficulty }

    init(type: String, lead: String = "", options: [String] = [], difficulty: HabitDifficulty? = nil) {
        self.type = type
        self.lead = lead
        self.options = options
        self.difficulty = difficulty
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        lead = try c.decodeIfPresent(String.self, forKey: .lead) ?? ""
        options = try c.decodeIfPresent([String].self, forKey: .options) ?? []
        difficulty = (try c.decodeIfPresent(String.self, forKey: .difficulty)).flatMap { HabitDifficulty(rawValue: $0) }
    }
}
