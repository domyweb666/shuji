import Foundation

// 七個 AI 任務的輸入與輸出，欄位名跟 server/src/tasks.ts 一字不差（snake_case）。
// 輸出裡「有時候沒有」的欄位伺服器一律給 null，這裡用 Optional 接。

enum AITask: Int {
    case plant = 1      // 種下去助手（免費）
    case obstacle = 2   // 障礙版與旅行版（免費）
    case rival = 3      // 對手偵測（免費）
    case diagnose = 4   // 三問診斷（免費）
    case weekly = 5     // 週回顧建議（完整版）
    case audit = 6      // 季稽核（完整版）
    case guide = 7      // 對話引導：首次設定用問答的方式拆出「如果…我就…」（免費）

    var paid: Bool { self == .weekly || self == .audit }
}

/// 伺服器回的欄位代碼 → 設定頁哪一格。obstacle 跟 backup 在原生版是同一格「不順的時候」。
enum HabitField: String, Codable {
    case trigger, floor, backup, obstacle, travelFloor

    var label: String {
        switch self {
        case .trigger: return "如果（時機）"
        case .floor: return "我就（最小一步）"
        case .backup, .obstacle: return "不順的時候"
        case .travelFloor: return "旅行版最小一步"
        }
    }

    func apply(_ text: String, to h: inout Habit) {
        switch self {
        case .trigger: h.trigger = text
        case .floor: h.floor = text
        case .backup, .obstacle: h.backup = text
        case .travelFloor: h.travelFloor = text
        }
    }
}

// MARK: 輸入

struct PlantInput: Encodable {
    var goal: String
    var queue: [String]
}

struct ObstacleInput: Encodable {
    var trigger: String
    var floor: String
    var interruptions: String
    var travels: Bool
}

struct RivalInput: Encodable {
    var trigger: String
    var floor: String
    var rival: String
    var feel: String
}

struct DiagnoseInput: Encodable {
    struct Answers: Encodable {
        var q1_trigger_appeared: String
        var q2_floor_too_big: String
        var q3_rival: String
    }
    var trigger: String
    var floor: String
    var answers: Answers
    var gap_days: Int
}

// 任務 5 週回顧建議的輸入輸出拿掉了：週回顧改由程式寫（.analytics/00）。伺服器的任務 5 留著不動。

struct AuditInput: Encodable {
    struct Quarter: Encodable {
        var done_rate: Double
        var weekly_avg: [Double]
        var leaves: Int
        var returns: Int
    }
    struct User: Encodable {
        var satisfied: String
        var context_change: String
    }
    var floor: String
    var trigger: String
    var why: String
    var status: String
    var quarter: Quarter
    var user: User
}

/// 對話引導：每一輪把到目前為止的問答整份送出去，伺服器不存對話
struct GuideTurn: Codable, Equatable {
    var q: String
    var a: String
}

struct GuideInput: Encodable {
    var turns: [GuideTurn]
    var queue: [String]
}

// MARK: 輸出

struct GuideOutput: Decodable, Equatable {
    struct Plan: Decodable, Equatable {
        var trigger: String
        var floor: String
    }
    var type: String          // ask | propose | unfit
    var say: String
    var question: String
    var options: [String]
    var plans: [Plan]
    var difficulty: String?   // easy | medium | hard
    var weeks_min: Int
    var weeks_max: Int
    var reason: String

    var difficultyLabel: String {
        switch difficulty {
        case "easy": return "好上手"
        case "hard": return "比較吃力"
        default: return "中等"
        }
    }
}

struct PlantOutput: Decodable {
    var type: String          // ok | needs_rewrite | too_rare | unfit
    var floors: [String]
    var triggers: [String]
    var example: String
    var note: String
    var message: String?
}

struct ObstacleOutput: Decodable {
    struct Pair: Decodable { var `if`: String; var then: String }
    struct Travel: Decodable { var portable: Bool; var floor: String; var alt: String }
    var type: String
    var obstacles: [Pair]
    var backup: String?
    var travel: Travel?
    var note: String
}

struct RivalOutput: Decodable {
    var type: String
    var rival_type: String?
    var block: String
    var clear: String
    var note: String

    var rivalLabel: String {
        switch rival_type {
        case "temptation": return "誘惑：有想要的拉扯感"
        case "autopilot": return "手自己動：回過神已經在做"
        case "internal": return "內在線索：焦慮、無聊或累"
        case "social": return "人或場合"
        default: return "對手"
        }
    }
}

struct DiagnoseOutput: Decodable {
    var type: String
    var layer: Int
    var field: HabitField?
    var suggestion: String
    var why: String
    var closing: String
}

struct AuditOutput: Decodable {
    var type: String
    var path: String          // keep | scale | relocate | retire
    var change: String
    var why: String
    var warn: String

    var pathLabel: String {
        switch path {
        case "keep": return "維持"
        case "scale": return "加量"
        case "relocate": return "換情境"
        case "retire": return "退場"
        default: return path
        }
    }
}

/// 任何任務都可能回 unfit：只讀 type 與 category
struct UnfitProbe: Decodable {
    var type: String
    var category: String?
}
