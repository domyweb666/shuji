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

    // 任務 5「這週看什麼」已拿掉（.analytics/00 閘門 0）：週回顧改由程式照字串表寫「這週的田」。

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
        let l = ledger(today: t)
        let returns = done.filter { l.isReturn($0) }.count
        return AuditInput(floor: h.floor, trigger: h.trigger, why: h.why, status: "growing",
                          quarter: .init(done_rate: min(1, Double(done.count) / Double(span)),
                                         weekly_avg: weekly.suffix(13).map(\.avg),
                                         leaves: leaveCount, returns: returns),
                          user: .init(satisfied: satisfied, context_change: contextChange))
    }
}
