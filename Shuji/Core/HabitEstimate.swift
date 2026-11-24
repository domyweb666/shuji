import Foundation

// 預估幾天養成。AI 只判難度，天數由這裡填；日期照他自己的紀錄重算。
// 純計算，today 由外面傳進來，測試在 ShujiTests/HabitEstimateTests.swift。

/// 難度 → 天數。數字只放這裡
enum HabitDifficulty: String, Codable {
    case easy, medium, hard

    var days: Int {
        switch self {
        case .easy: return 60
        case .medium: return 66
        case .hard: return 90
        }
    }
}

extension AppState {
    /// 記錄率最低算多少：再少的話日期會跑到很遠，看了只會放棄
    private static let estimateMinRate = 0.4
    private static let estimateWindow = 14

    /// 走到哪：記了幾天／預估幾天。沒有預估天數（舊的習慣）是 nil
    func estimateProgress(today: DayKey) -> (done: Int, total: Int)? {
        guard let total = habit?.estimatedDays else { return nil }
        return (doneKeys.filter { $0 <= today }.count, total)
    }

    /// 照最近的記錄率，大概哪一天走完。走完了回 today
    func estimateDate(today: DayKey) -> DayKey? {
        guard let h = habit, let p = estimateProgress(today: today) else { return nil }
        let left = p.total - p.done
        guard left > 0 else { return today }
        // 看今天以前的 14 天（今天還沒過完，不算進來，日期才不會早晚不一樣）
        let window = min(AppState.estimateWindow, max(0, DayKey.days(from: h.planted, to: today)))
        var rate = 1.0
        if window > 0 {
            let start = today.adding(-window)
            let done = doneKeys.filter { $0 >= start && $0 < today }.count
            rate = min(1, max(AppState.estimateMinRate, Double(done) / Double(window)))
        }
        // 減一點點，除得盡的時候不會因為小數誤差多算一天
        return today.adding(Int((Double(left) / rate - 1e-9).rounded(.up)))
    }
}
