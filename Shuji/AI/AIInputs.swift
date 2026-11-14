import Foundation

/// 從紀錄組出每個 AI 任務要送的輸入。只送該任務需要的欄位，不送整份紀錄（ai/AI交接.md 第五節）。
/// 純計算，測試在 ShujiTests。
extension AppState {
    func plantedDays(today t: DayKey) -> Int {
        guard let h = habit else { return 0 }
        return max(0, DayKey.days(from: h.planted, to: t))
    }

    /// 最後一次記一節到今天隔了幾天；從沒記過就從種下去那天算
    func gapDays(today t: DayKey) -> Int {
        let last = doneKeys.last ?? habit?.planted ?? t
        return max(0, DayKey.days(from: last, to: t))
    }

    /// 種下去滿 7 天、「不順的時候」還空著：今天記好之後浮出「這週有被打斷過嗎？」
    func obstaclePromptReady(today t: DayKey) -> Bool {
        guard let h = habit, letgo == nil else { return false }
        return plantedDays(today: t) >= 7 && h.backup.isEmpty
    }

    /// 週回顧建議：這週（七天內）做過開始四問、種了兩週以上、不在放手測試中
    func weeklyAdviceReady(today t: DayKey) -> Bool {
        guard habit != nil, letgo == nil, let last = weekly.last else { return false }
        return plantedDays(today: t) >= 14 && DayKey.days(from: last.date, to: t) <= 7
    }

    /// 季稽核：種了一季（12 週）以上
    func auditReady(today t: DayKey) -> Bool {
        habit != nil && plantedDays(today: t) >= 84
    }

    func diagnoseInput(today t: DayKey, q1: String, q2: String, q3: String) -> DiagnoseInput? {
        guard let h = habit else { return nil }
        return DiagnoseInput(trigger: h.trigger, floor: h.floor,
                             answers: .init(q1_trigger_appeared: q1, q2_floor_too_big: q2, q3_rival: q3),
                             gap_days: gapDays(today: t))
    }

    /// 昨天往回 14 天（今天還沒過完，不算）
    func weeklyInput(today t: DayKey) -> WeeklyInput? {
        guard let h = habit else { return nil }
        let days = (1...14).reversed().map { t.adding(-$0) }
        let last14: [String] = days.map { k in
            guard let l = log(on: k) else { return "miss" }
            return l.t == .done ? "done" : "leave"
        }
        let since = t.adding(-60)
        let leaves: [WeeklyInput.Leave] = logs
            .filter { $0.value.t == .leave }
            .compactMap { key, log in
                guard let k = DayKey(key), k >= since, k < t else { return nil }
                return WeeklyInput.Leave(date: key, reason: log.reason ?? "")
            }
            .sorted { $0.date < $1.date }
        return WeeklyInput(trigger: h.trigger, floor: activeFloor,
                           planted_days: plantedDays(today: t),
                           weeks: weekly.suffix(8).map { .init(date: $0.date.string, avg: $0.avg) },
                           last14: last14,
                           last14_weekdays: days.map(\.weekday),
                           leaves: Array(leaves.suffix(20)),
                           travel: travel)
    }

    /// 最近一季（91 天，種下去不到一季就從種下去那天）的數字
    func auditInput(today t: DayKey, satisfied: String, contextChange: String) -> AuditInput? {
        guard let h = habit else { return nil }
        let start = max(h.planted, t.adding(-91))
        let span = max(1, DayKey.days(from: start, to: t))
        let inWindow: (DayKey) -> Bool = { $0 >= start && $0 < t }
        let done = doneKeys.filter(inWindow)
        let leaveCount = logs.filter { key, log in
            guard log.t == .leave, let k = DayKey(key) else { return false }
            return inWindow(k)
        }.count
        let returns = done.filter { isReturn($0) }.count
        return AuditInput(floor: h.floor, trigger: h.trigger, why: h.why, status: "growing",
                          quarter: .init(done_rate: min(1, Double(done.count) / Double(span)),
                                         weekly_avg: weekly.suffix(13).map(\.avg),
                                         leaves: leaveCount, returns: returns),
                          user: .init(satisfied: satisfied, context_change: contextChange))
    }
}
