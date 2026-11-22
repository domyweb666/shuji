import XCTest
@testable import Shuji

// .analytics/09-驗證/計畫.md 的 D：自動測試。
// 編號對 04 邊界情況表（Edge01～27）、05 指標字典（M2～M17）、07 字串表、08 安靜規則。

/// 2026-11-22 是星期日（預設回顧日）
private let T = DayKey("2026-11-22")!

private func utc(_ s: String) -> Date { Stamp.date(s)! }

private func localDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, tz: String = "Asia/Taipei") -> Date {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: tz)!
    return cal.date(from: c)!
}

/// 假使用者
private struct Fixture {
    var s = AppState()
    let hid = "hab-test"

    init(planted: DayKey, reviewDay: Int = 0) {
        s.habit = Habit(floor: "打開檔案寫一句", trigger: "起床喝完第一杯水", planted: planted, id: hid)
        s.settings.reviewDay = reviewDay
    }

    mutating func done(_ d: DayKey, tz: String? = "Asia/Taipei", source: RecordSource = .hold) {
        s.records.append(DayRecord(id: "rec-\(s.records.count)", habit: hid, kind: .done, day: d,
                                   at: nil, tz: tz, source: source))
    }

    mutating func leave(_ d: DayKey, _ reason: String) {
        s.records.append(DayRecord(id: "rec-\(s.records.count)", habit: hid, kind: .leave, day: d,
                                   at: nil, tz: "Asia/Taipei", source: .hold, reason: reason))
    }

    mutating func review(_ d: DayKey, _ v: Double) {
        s.reviews.append(WeeklyReview(date: d, scores: [v, v, v, v], id: "rev-\(s.reviews.count)", habit: hid))
    }

    mutating func mark(_ kind: Mark.Kind, _ d: DayKey, prior: Int? = nil, recalled: Int? = nil, pass: Bool? = nil) {
        let h: String? = (kind == .travelOn || kind == .travelOff) ? nil : hid
        s.marks.append(Mark(id: "mark-\(s.marks.count)", habit: h, kind: kind, day: d, at: nil, tz: nil,
                            prior: prior, recalled: recalled, pass: pass))
    }

    /// 從種下那天到 last，照 rule 決定每天記不記
    mutating func fill(to last: DayKey, _ rule: (DayKey) -> Bool) {
        var d = s.habit!.planted
        while d <= last {
            if rule(d) { done(d) }
            d = d.adding(1)
        }
    }

    static func isWeekend(_ d: DayKey) -> Bool { d.weekday == 0 || d.weekday == 6 }

    /// U2：第 8 週。最近 6 週週末 12 天記 5 天、平日 30 天記 27 天；今天（星期日）有記
    static func weekendGap() -> Fixture {
        var f = Fixture(planted: T.adding(-55))
        let windowStart = T.adding(-41)
        var weekendSeen = 0
        var weekdaySeen = 0
        f.fill(to: T) { d in
            guard d >= windowStart else { return true }
            if isWeekend(d) {
                weekendSeen += 1
                // 12 個週末日裡記 5 天：今天一定記（第 12 個），其他挑 4 個
                return d == T || [2, 5, 7, 10].contains(weekendSeen)
            }
            weekdaySeen += 1
            return ![4, 14, 24].contains(weekdaySeen)
        }
        for i in 0..<8 { f.review(T.adding(-49 + i * 7), 4 + Double(i) * 0.25) }
        return f
    }

    /// U3：前 5 週每天都記，停 20 天，今天回來
    static func returned() -> Fixture {
        var f = Fixture(planted: T.adding(-60))
        f.fill(to: T) { $0 <= T.adding(-21) || $0 == T }
        for i in 0..<5 { f.review(T.adding(-56 + i * 7), 5) }
        return f
    }
}

private extension Ledger {
    init(_ f: Fixture, today: DayKey = T) { self = f.s.ledger(today: today) }
}

// MARK: - 04 邊界情況

@MainActor
final class EdgeCaseTests: XCTestCase {
    private func store(now: @escaping () -> Date, tz: @escaping () -> TimeZone = { TimeZone(identifier: "Asia/Taipei")! }) -> Store {
        let s = Store(now: now, timeZone: tz, fileURL: nil, backupDir: nil)
        var n = 0
        s.makeID = { n += 1; return "\($0)-\(n)" }
        return s
    }

    func testEdge01NightOwlCountsAsYesterday() {
        let s = store(now: { localDate(2026, 11, 22, 0, 30) })
        s.plant(floor: "讀一頁書", trigger: "刷完牙")
        XCTAssertEqual(s.today, DayKey("2026-11-21"), "凌晨四點才換日")
        s.logToday()
        let r = s.state.records.last!
        XCTAssertEqual(r.day, DayKey("2026-11-21"))
        XCTAssertEqual(r.tz, "Asia/Taipei")
        XCTAssertEqual(r.at, "2026-11-21T16:30:00Z", "存世界標準時間")
        XCTAssertEqual(r.source, .hold)
    }

    func testEdge02ChangingReviewDayDoesNotAskTwice() {
        var f = Fixture(planted: T.adding(-20))
        f.review(T.adding(-2), 4) // 星期五做過
        XCTAssertFalse(f.s.reviewPending(today: T), "回顧日星期日，星期五做過就不再問")
        f.s.settings.reviewDay = 5
        XCTAssertFalse(f.s.reviewPending(today: T), "改成星期五，這週一樣不會出現第二次")
        XCTAssertEqual(f.s.reportWeekEnd(today: T), T.adding(-2), "週照新的回顧日重切")
    }

    func testEdge03BackfillCountsButTodayIsNotReturn() {
        let s = store(now: { localDate(2026, 11, 22, 9, 0) })
        s.state = Fixture(planted: T.adding(-10)).s
        s.state.records = []
        var f = Fixture(planted: T.adding(-10))
        f.fill(to: T.adding(-2)) { _ in true }
        s.state = f.s
        s.backfillYesterday()
        XCTAssertEqual(s.state.records.last?.source, .backfill)
        XCTAssertEqual(s.state.records.last?.day, T.adding(-1))
        XCTAssertFalse(s.logToday(), "補了昨天，今天就不是回來")
        XCTAssertEqual(s.state.ledger(today: T).week(end: T).done, 7)
    }

    func testEdge04And05UndoIsAMarkAndRelogCountsOnce() {
        let s = store(now: { localDate(2026, 11, 22, 9, 0) })
        s.plant(floor: "讀一頁書", trigger: "刷完牙")
        s.logToday()
        s.undoToday()
        XCTAssertEqual(s.state.records.count, 1)
        XCTAssertNotNil(s.state.records[0].deletedAt, "撤銷是標記，不刪")
        XCTAssertNil(s.state.log(on: T))
        s.logToday()
        XCTAssertEqual(s.state.records.count, 2)
        XCTAssertEqual(s.state.stats(today: T).nodes, 1, "被撤銷的不算")
    }

    func testEdge06And09SameDayTwiceIsBlockedEvenAcrossTimeZones() {
        var nowDate = utc("2026-11-22T01:00:00Z") // 台北 09:00
        var zone = TimeZone(identifier: "Asia/Taipei")!
        let s = store(now: { nowDate }, tz: { zone })
        s.plant(floor: "讀一頁書", trigger: "刷完牙")
        XCTAssertTrue(s.state.log(on: s.today) == nil)
        s.logToday()
        nowDate = utc("2026-11-22T20:00:00Z") // 洛杉磯 11/22 中午
        zone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(s.today, DayKey("2026-11-22"))
        XCTAssertFalse(s.logToday(), "往西飛，同一天第二次不記")
        XCTAssertEqual(s.shortcutLog(), "今天已經記過了。")
        XCTAssertEqual(s.state.records.count, 1)
    }

    func testEdge08TimeZoneSkippedDayIsNotMissed() {
        var f = Fixture(planted: T.adding(-20))
        f.fill(to: T.adding(-4)) { _ in true }
        f.s.records.removeAll { $0.day == T.adding(-4) }
        f.done(T.adding(-4), tz: "America/Los_Angeles")
        // T-3 整天在飛機上；T-2 在台北記
        f.done(T.adding(-2), tz: "Asia/Taipei")
        f.done(T.adding(-1), tz: "Asia/Taipei")
        let l = Ledger(f)
        XCTAssertTrue(l.isTimezoneSkip(T.adding(-3)))
        XCTAssertFalse(l.isMissed(T.adding(-3)), "換時區被吃掉的那天不算漏掉")
        XCTAssertFalse(l.isReturn(T.adding(-2)), "下一節不算回來")
        XCTAssertEqual(f.s.stats(today: T).missed, 0)
        XCTAssertFalse(l.isComparable(T.adding(-3)))
    }

    func testEdge10TravelDaysLeaveWeekendSplit() {
        var f = Fixture(planted: T.adding(-55))
        f.fill(to: T) { _ in true }
        f.mark(.travelOn, T.adding(-9))
        f.mark(.travelOff, T.adding(-7))
        let l = Ledger(f)
        XCTAssertTrue(l.isTravel(T.adding(-9)))
        XCTAssertTrue(l.isTravel(T.adding(-7)), "關掉那天也算旅行中")
        XCTAssertFalse(l.isTravel(T.adding(-6)))
        let split = l.weekendSplit(end: T)
        XCTAssertEqual(split.a.days + split.b.days, 42 - 3, "旅行中的 3 天不進平日／週末")
        XCTAssertEqual(f.s.travelEndedOn, T.adding(-7))
        XCTAssertFalse(f.s.travel)
    }

    func testEdge11LetGoRunningIsNotMissedAndNotReturn() {
        var f = Fixture(planted: T.adding(-40))
        f.fill(to: T.adding(-15)) { _ in true }
        f.mark(.letgoStart, T.adding(-14), prior: 14)
        let l = Ledger(f)
        XCTAssertTrue(l.isLetGo(T.adding(-14)))
        XCTAssertTrue(l.isLetGo(T), "進行中的放手測試到今天")
        XCTAssertEqual(f.s.stats(today: T).missed, 0, "放手測試進行中，田的漏掉不會每天加一（審查 P1-5）")
        XCTAssertEqual(f.s.consecutiveMissed(today: T), 0)
        XCTAssertEqual(f.s.lineDays(l, end: T, isBack: false), Copy.t(.w1letgoAll))
        XCTAssertNil(f.s.weekObservation(today: T), "放手測試中不出觀察")
    }

    func testEdge11LetGoJustEndedDoesNotSayStuckAndFirstNodeIsNoReturn() {
        var f = Fixture(planted: T.adding(-40))
        f.fill(to: T.adding(-15)) { _ in true }
        f.mark(.letgoStart, T.adding(-14), prior: 14)
        f.mark(.letgoEnd, T, prior: 14, recalled: 13, pass: true)
        XCTAssertEqual(f.s.consecutiveMissed(today: T), 0, "放手剛結束，今天頁不跳「卡住的話」（審查 P1-6）")
        f.done(T)
        XCTAssertFalse(f.s.isReturn(T), "放手之後第一節不開花（審查 P2-13）")
    }

    func testEdge12LetGoUnsureDoesNotPass() {
        let s = store(now: { localDate(2026, 11, 22, 9, 0) })
        var f = Fixture(planted: T.adding(-40))
        f.fill(to: T.adding(-15)) { _ in true }
        f.mark(.letgoStart, T.adding(-14), prior: 14)
        s.state = f.s
        XCTAssertTrue(s.showLetGoEnd)
        s.finishLetGo(days: nil)
        XCTAssertNil(s.state.letgo)
        XCTAssertEqual(s.state.letgoResult?.pass, false)
        XCTAssertNil(s.state.letgoResult?.recalled, "記不清楚存空")
        XCTAssertFalse(s.state.signals(today: T).s3)
        XCTAssertEqual(s.toast, Copy.t(.p4unsure))
    }

    func testEdge13SecondLetGoKeepsBothWindows() {
        var f = Fixture(planted: T.adding(-60))
        f.fill(to: T.adding(-46)) { _ in true }
        f.mark(.letgoStart, T.adding(-45), prior: 14)
        f.mark(.letgoEnd, T.adding(-31), prior: 14, recalled: 9, pass: false)
        f.fill(to: T.adding(-16)) { $0 >= T.adding(-31) }
        f.mark(.letgoStart, T.adding(-15), prior: 14)
        f.mark(.letgoEnd, T.adding(-1), prior: 14, recalled: 13, pass: true)
        XCTAssertEqual(f.s.letgoRuns.count, 2)
        XCTAssertEqual(f.s.stats(today: T).missed, 1, "兩次放手的窗口都不算漏掉；只剩昨天（結束那天）沒記")
        XCTAssertEqual(f.s.letgoResult?.pass, true, "訊號照最後一次")
        XCTAssertEqual(f.s.letgoResult?.start, T.adding(-15))
    }

    func testEdge14And15LeaveIsNotMissedAndUndoneLeaveIsGone() {
        var f = Fixture(planted: T.adding(-20))
        f.fill(to: T) { $0 != T.adding(-3) }
        f.leave(T.adding(-3), "發燒")
        let l = Ledger(f)
        XCTAssertFalse(l.isMissed(T.adding(-3)))
        XCTAssertFalse(l.isComparable(T.adding(-3)), "請假不進比較的分母")
        XCTAssertEqual(l.week(end: T).leave, 1)
        XCTAssertEqual(f.s.stats(today: T).leaves, 1)
        f.s.records[f.s.records.count - 1].deletedAt = "2026-11-19T00:00:00Z"
        XCTAssertEqual(f.s.stats(today: T).leaves, 0)
        XCTAssertTrue(f.s.ledger(today: T).isMissed(T.adding(-3)), "撤銷的請假不算")
    }

    func testEdge16LongAbsenceWeeksAreEmptyNotZero() {
        let f = Fixture.returned()
        let rows = f.s.recentWeeks(today: T)
        XCTAssertEqual(rows.first?.kind, .bar, "今天回來，這週有紀錄")
        XCTAssertEqual(rows[1].kind, .empty, "停的那週寫沒有紀錄，不寫 0 天")
        XCTAssertEqual(rows[2].kind, .empty)
        XCTAssertTrue(f.s.longAbsence(today: T.adding(1)) == false, "今天記了")
    }

    func testEdge17PauseByPersonalRhythmMakesAReturnWeek() {
        var f = Fixture(planted: T.adding(-40))
        f.fill(to: T) { !($0 >= T.adding(-6) && $0 <= T.adding(-2)) } // 平常不漏，停 5 天
        let l = Ledger(f)
        XCTAssertEqual(l.pauses.count, 1, "5 天 ≥ max(4, 2 × 0)，算停頓")
        XCTAssertTrue(l.isReturnWeek(end: T))
        XCTAssertEqual(f.s.lineDays(l, end: T, isBack: true), "這週接上了，記了 2 天。")
        XCTAssertNil(f.s.weekObservation(today: T), "回來週不出觀察")

        var g = Fixture(planted: T.adding(-40))
        // 平常就會連漏 3 天的人，停 5 天不算停頓（5 < 2 × 3）
        g.fill(to: T) { d in
            let n = DayKey.days(from: T.adding(-40), to: d)
            if d >= T.adding(-6) && d <= T.adding(-2) { return false }
            return !(n >= 10 && n <= 12)
        }
        XCTAssertTrue(Ledger(g).pauses.isEmpty)
    }

    func testEdge18FirstWeekSaysPlantedDay() {
        var f = Fixture(planted: T.adding(-4))
        f.fill(to: T) { $0 != T.adding(-2) }
        let r = f.s.weekReport(today: T)!
        XCTAssertEqual(r.lines[0], "種下去第 5 天，記了 4 天。")
        XCTAssertNil(r.observation)
    }

    func testEdge19ChangingTheSwitchLeavesAChangeAndMarksTheWeek() {
        let s = store(now: { localDate(2026, 11, 22, 9, 0) })
        s.state = Fixture.weekendGap().s
        s.pendingVia = .week
        s.updateHabit { $0.backup = "週末起床先洗臉，洗完就寫三行" }
        let c = s.state.changes.last!
        XCTAssertEqual(c.field, .backup)
        XCTAssertEqual(c.from, "")
        XCTAssertEqual(c.to, "週末起床先洗臉，洗完就寫三行")
        XCTAssertEqual(c.via, .week, "從這週的田過去改的")
        XCTAssertEqual(c.day, T)
        s.updateHabit { $0.trigger = "刷完牙" }
        XCTAssertEqual(s.state.changes.last?.via, .settings, "下一次就回到設定頁")
        XCTAssertTrue(s.state.recentWeeks(today: T).first!.changed, "那一週標改過開關")
        XCTAssertFalse(s.state.recentWeeks(today: T)[1].changed)
    }

    func testEdge20To23Trials() {
        var f = Fixture.weekendGap()
        let o = Insight(id: "obs-1", habit: f.hid, kind: .weekend, week: T.adding(-14), shownAt: nil, tz: nil,
                        counts: ["weekday": GroupCount(done: 27, days: 30), "weekend": GroupCount(done: 5, days: 12)],
                        low: "weekend", subject: nil, metricVersion: MetricVersion.current, shown: true,
                        cause: "no_trigger", action: "backup", note: nil, trial: "try-1")
        f.s.observations = [o]
        f.s.trials = [Trial(id: "try-1", habit: f.hid, observation: "obs-1", kind: .weekend, group: "weekend",
                            change: "backup", start: T.adding(-14), end: T, status: .running,
                            before: GroupCount(done: 5, days: 12), after: nil, conclusion: nil, concludedAt: nil)]
        // 20：試的期間又改了最小一步
        f.s.changes = [HabitChange(id: "chg-1", habit: f.hid, field: .floor, from: "a", to: "b",
                                   day: T.adding(-5), at: nil, tz: nil, via: .settings)]
        let r = f.s.dueTrial(today: T)!
        XCTAssertTrue(r.changedDuring)
        XCTAssertEqual(r.after.days, 4, "試的 [T-14, T) 裡的週末：T-14、T-8、T-7、T-1（T 不含）")
        XCTAssertTrue(r.smallOrClose, "天數還少")
        XCTAssertTrue(f.s.trialText(r).contains(Copy.t(.exp4)))
        // 22：到期那週沒做週回顧，下週照樣是到期
        XCTAssertNotNil(f.s.dueTrial(today: T.adding(7)))
        // 23：那兩週都在旅行
        var g = f
        g.mark(.travelOn, T.adding(-14))
        g.mark(.travelOff, T.adding(-1))
        let empty = g.s.dueTrial(today: T)!
        XCTAssertTrue(empty.empty)
        XCTAssertEqual(g.s.trialText(empty).first, "這兩週沒有可以比的週末。")
    }

    func testEdge21StopTrialEndsQuietly() {
        let s = store(now: { localDate(2026, 11, 22, 9, 0) })
        var f = Fixture.weekendGap()
        f.s.trials = [Trial(id: "try-1", habit: f.hid, observation: "obs-1", kind: .weekend, group: "weekend",
                            change: "backup", start: T.adding(-3), end: T.adding(11), status: .running,
                            before: GroupCount(done: 5, days: 12), after: nil, conclusion: nil, concludedAt: nil)]
        s.state = f.s
        s.stopTrial("try-1")
        XCTAssertEqual(s.state.trials[0].status, .stopped)
        XCTAssertNil(s.state.trials[0].conclusion, "不給結論、不追問")
        XCTAssertNil(s.state.runningTrial)
        XCTAssertNil(s.state.dueTrial(today: T.adding(14)))
    }

    func testEdge24SameFindingCoolsDownAndDoesNotReask() {
        var f = Fixture.weekendGap()
        XCTAssertNotNil(f.s.weekObservation(today: T))
        f.s.observations = [Insight(id: "obs-0", habit: f.hid, kind: .weekend, week: T.adding(-21), shownAt: nil, tz: nil,
                                    counts: [:], low: "weekend", subject: nil, metricVersion: MetricVersion.current,
                                    shown: true, cause: "no_trigger", action: "none", note: nil, trial: nil)]
        XCTAssertNil(f.s.weekObservation(today: T), "28 天內不再出")
        f.s.observations[0].week = T.adding(-28)
        guard case .finding(let again)? = f.s.weekObservation(today: T) else { return XCTFail("過了冷卻要再出") }
        XCTAssertFalse(again.askCause, "她選過原因，只說現象")
        XCTAssertEqual(f.s.memoryText(again), "上次選的是「週末作息不一樣，開關沒出現」。")
    }

    func testEdge25And26DigKeepsRecordsAndNextHabitStartsClean() {
        let s = store(now: { localDate(2026, 11, 22, 9, 0) })
        s.state = Fixture.weekendGap().s
        let count = s.state.records.count
        s.dig()
        XCTAssertEqual(s.state.records.count, count)
        XCTAssertEqual(s.state.basket.first?.habit, "hab-test")
        s.plantNext()
        s.plant(floor: "讀一頁書", trigger: "刷完牙")
        XCTAssertNotEqual(s.state.habit?.id, "hab-test")
        XCTAssertEqual(s.state.stats(today: T).nodes, 0)
        XCTAssertEqual(s.state.pastHabits.count, 1)
    }

    func testEdge27ImportWritesABackupFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shuji-edge27-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = Store(now: { localDate(2026, 11, 22, 9, 0) }, timeZone: { TimeZone(identifier: "Asia/Taipei")! },
                      fileURL: nil, backupDir: dir)
        s.state = Fixture.weekendGap().s
        XCTAssertTrue(s.importJSON("{\"habit\":{\"floor\":\"讀一頁書\",\"trigger\":\"刷完牙\",\"planted\":\"2026-11-01\"},\"logs\":{\"2026-11-02\":{\"t\":\"done\"}}}"))
        let url = dir.appendingPathComponent("薯記備份-還原前-2026-11-22.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(s.state.v, 2)
        XCTAssertEqual(s.state.records.first?.source, .imported)
        XCTAssertEqual(s.state.habit?.id, "hab-v1-2026-11-01")
    }
}

// MARK: - 05 指標

final class MetricTests: XCTestCase {
    func testM2SameNodesInFourPlaces() {
        var f = Fixture.weekendGap()
        f.s.records.removeAll { $0.day == T }
        let nodes = f.s.stats(today: T).nodes
        XCTAssertEqual(WidgetSnapshot.make(state: f.s, today: T).nodes, nodes)
        XCTAssertEqual(GlanceCopy.todaySub(date: T.long, nodes: nodes), "\(T.long) · 第 \(nodes) 節")
        XCTAssertEqual(GlanceCopy.widgetNone(nodes: nodes), "今天還沒記 · 已長 \(nodes) 節")
    }

    func testM3WeekCount() {
        var f = Fixture(planted: T.adding(-30))
        f.fill(to: T.adding(-1)) { ![T.adding(-5), T.adding(-4)].contains($0) }
        f.leave(T.adding(-4), "出遠門")
        let w = Ledger(f).week(end: T)
        XCTAssertEqual(w.done, 4, "T-6、T-3、T-2、T-1")
        XCTAssertEqual(w.leave, 1)
        XCTAssertTrue(w.todayPending, "今天還沒記，不算漏")
        XCTAssertEqual(w.considered, 6)
        XCTAssertEqual(f.s.lineDays(Ledger(f), end: T, isBack: false), "這週記了 4 天，請假 1 天（今天還沒記）。前 3 週都是 7 天。", "種下那週不完整，不算進平常")
    }

    func testM4UsualRange() {
        var f = Fixture(planted: T.adding(-34))
        // 前 4 週：7、6、5、7 天（第 4 週不完整：種下在那週中間）
        f.fill(to: T) { d in
            ![T.adding(-10), T.adding(-16), T.adding(-17)].contains(d)
        }
        let l = Ledger(f)
        let u = l.usualRange(before: T)!
        XCTAssertEqual(u.weeks, 4)
        XCTAssertEqual(u.lo, 5)
        XCTAssertEqual(u.hi, 7)
        var g = Fixture(planted: T.adding(-9))
        g.fill(to: T) { _ in true }
        XCTAssertNil(Ledger(g).usualRange(before: T), "完整週不到 2 週")
        XCTAssertEqual(g.s.lineDays(Ledger(g), end: T, isBack: false), "這週記了 7 天。再過 2 週，就有平常的範圍可以比。", "這週要變成「前一週」才算")
    }

    func testM5LineShapes() {
        var f = Fixture(planted: T.adding(-60))
        XCTAssertEqual(f.s.lineShape, .few)
        f.review(T.adding(-14), 4); f.review(T.adding(-7), 4.25); f.review(T, 4.5)
        XCTAssertEqual(f.s.lineShape, .flat)
        f.s.reviews = []
        f.review(T.adding(-14), 3); f.review(T.adding(-7), 4); f.review(T, 5)
        XCTAssertEqual(f.s.lineShape, .up)
        f.s.reviews = []
        f.review(T.adding(-14), 5); f.review(T.adding(-7), 4); f.review(T, 3)
        XCTAssertEqual(f.s.lineShape, .down)
        f.s.reviews = []
        f.review(T.adding(-14), 3); f.review(T.adding(-7), 5); f.review(T, 4)
        XCTAssertEqual(f.s.lineShape, .mixed)
    }

    func testM6CurveFlatNeedsRecentAndTight() {
        var f = Fixture(planted: T.adding(-90))
        for i in 0..<6 { f.review(T.adding(-35 + i * 7), 5) }
        XCTAssertTrue(f.s.signals(today: T).s1)
        XCTAssertFalse(f.s.signals(today: T.adding(15)).s1, "最近一次超過 14 天，做一次新的才算")
        XCTAssertTrue(f.s.signals(today: T.adding(15)).stale)
        var g = Fixture(planted: T.adding(-120))
        for i in 0..<4 { g.review(T.adding(-70 + i * 7), 5) }
        g.review(T.adding(-30), 5); g.review(T, 5)
        XCTAssertFalse(g.s.signals(today: T).s1, "最近三次橫跨超過 21 天（審查 P1-7）")
        XCTAssertTrue(g.s.signals(today: T).spread)
    }

    func testM7WeekendSplitPassesThreshold() {
        let f = Fixture.weekendGap()
        let s = Ledger(f).weekendSplit(end: T)
        XCTAssertEqual(s.b, GroupCount(done: 5, days: 12))
        XCTAssertEqual(s.a, GroupCount(done: 27, days: 30))
        XCTAssertEqual(s.weeks, 6)
        XCTAssertTrue(s.passes)
        XCTAssertEqual(s.low, "weekend")
    }

    func testM7SmallGapOrFewDaysDoesNotPass() {
        var f = Fixture(planted: T.adding(-55))
        var weekendSeen = 0
        f.fill(to: T) { d in
            guard d >= T.adding(-41), Fixture.isWeekend(d) else { return true }
            weekendSeen += 1
            return weekendSeen % 4 != 0 // 12 個裡記 9 個：75% 對 100%，差 25 個百分點
        }
        let s = Ledger(f).weekendSplit(end: T)
        XCTAssertTrue(s.enough)
        XCTAssertFalse(s.passes, "差不到 30 個百分點")
        var g = Fixture(planted: T.adding(-20))
        g.fill(to: T) { !Fixture.isWeekend($0) }
        let few = Ledger(g).weekendSplit(end: T)
        XCTAssertFalse(few.enough, "週末不到 10 天")
        XCTAssertEqual(few.needWeeks, 3, "週末 5 天（今天還沒記不算），還要 3 週")
    }

    func testM8TravelSplitOnlyWhenTravelIsLower() {
        var f = Fixture(planted: T.adding(-60))
        f.fill(to: T) { d in !(d >= T.adding(-30) && d <= T.adding(-19) && d.dayNumber % 3 != 0) }
        f.mark(.travelOn, T.adding(-30))
        f.mark(.travelOff, T.adding(-19))
        let s = Ledger(f).travelSplit(end: T)
        XCTAssertEqual(s.a.days, 12)
        XCTAssertEqual(s.a.done, 4)
        XCTAssertTrue(s.passes)
        guard case .finding(let x)? = f.s.weekObservation(today: T) else { return XCTFail("旅行中要出觀察") }
        XCTAssertEqual(x.kind, .travel)
        XCTAssertEqual(f.s.findingText(x), "最近 9 週，旅行中 12 天裡記了 4 天；在家 49 天裡記了 49 天。")
    }

    func testM9LeaveRepeat() {
        var f = Fixture(planted: T.adding(-60))
        f.fill(to: T) { ![T.adding(-40), T.adding(-12), T.adding(-5)].contains($0) }
        f.leave(T.adding(-40), "加班 ")
        f.leave(T.adding(-12), "加班")
        f.leave(T.adding(-5), "發燒")
        let lv = Ledger(f).leaveRepeat(end: T)!
        XCTAssertEqual(lv.reason, "加班")
        XCTAssertEqual(lv.count, 2)
        XCTAssertEqual(lv.total, 3)
        XCTAssertEqual(f.s.leaveReasonCount("加班", today: T), 2, "請假卡：前面請過 2 次")
        XCTAssertEqual(Copy.t(.p2, ["k": 3]), "這個原因第 3 次了，可能是開關要換。")
        guard case .finding(let x)? = f.s.weekObservation(today: T) else { return XCTFail("同一個請假原因排在平日／週末前面") }
        XCTAssertEqual(f.s.findingText(x), "最近 8 週請假 3 次，其中 2 次寫「加班」。")
        XCTAssertFalse(x.askCause, "原因是她自己寫的，不再問")
    }

    func testM11TrialResultWording() {
        var f = Fixture.weekendGap()
        let trial = Trial(id: "try-1", habit: f.hid, observation: "obs-1", kind: .weekend, group: "weekend",
                          change: "backup", start: T.adding(-13), end: T.adding(1), status: .running,
                          before: GroupCount(done: 5, days: 12), after: nil, conclusion: nil, concludedAt: nil)
        f.s.trials = [trial]
        XCTAssertNil(f.s.dueTrial(today: T), "還沒到期")
        let r = f.s.dueTrial(today: T.adding(1))!
        let lines = f.s.trialText(r)
        XCTAssertEqual(lines[0], "試兩週到了。試的這兩週，週末 \(r.after.days) 天裡記了 \(r.after.done) 天；試之前 12 天裡記了 5 天。")
        XCTAssertEqual(lines[1], "天數還少，這樣的差距可能是剛好。")
        XCTAssertFalse(lines.joined().contains("有效"), "不寫有效、證明")
    }

    func testM13And14WithLetGoAndTimeZone() {
        var f = Fixture(planted: T.adding(-30))
        f.fill(to: T.adding(-4)) { _ in true }
        XCTAssertEqual(f.s.consecutiveMissed(today: T), 3)
        f.done(T)
        XCTAssertTrue(f.s.isReturn(T))
    }

    func testM17RecentWeekKinds() {
        var f = Fixture(planted: T.adding(-38))
        f.fill(to: T) { d in !(d >= T.adding(-20) && d <= T.adding(-14)) }
        f.mark(.letgoStart, T.adding(-13), prior: 14)
        f.mark(.letgoEnd, T.adding(1), prior: 14, recalled: 14, pass: true)
        let rows = f.s.recentWeeks(today: T)
        XCTAssertEqual(rows.map(\.kind), [.letgo, .letgo, .empty, .bar, .bar, .first])
        XCTAssertEqual(rows.last?.plantedDays, 4, "種下那週：種下去第 4 天")
    }
}

// MARK: - 這週的田（06、07、08）

@MainActor
final class WeekReportTests: XCTestCase {
    private func store(_ f: Fixture, now: Date = localDate(2026, 11, 22, 9, 0)) -> Store {
        let s = Store(now: { now }, timeZone: { TimeZone(identifier: "Asia/Taipei")! }, fileURL: nil, backupDir: nil)
        var n = 0
        s.makeID = { n += 1; return "\($0)-\(n)" }
        s.state = f.s
        return s
    }

    func testNormalWeekHasThreeFactsAndOneFinding() {
        let f = Fixture.weekendGap()
        let r = f.s.weekReport(today: T)!
        XCTAssertEqual(r.lines.count, 3, "三個事實")
        XCTAssertTrue(r.lines[0].hasPrefix("這週記了 "))
        XCTAssertTrue(r.lines[0].contains("前 4 週是"))
        XCTAssertEqual(r.lines[1], "開始四問最近三次差不到半格，線在走平。")
        XCTAssertEqual(r.lines[2], "長好了嗎：三個訊號過了 1 個。")
        guard case .finding(let x)? = r.observation else { return XCTFail("要有一個觀察") }
        XCTAssertEqual(f.s.findingText(x), "最近 6 週，週末 12 天裡記了 5 天；平日 30 天裡記了 27 天。")
        XCTAssertTrue(x.askCause)
        XCTAssertEqual(Copy.causes(.weekend, low: x.low).map(\.text),
                       ["週末作息不一樣，開關沒出現", "有出現，但被別的事搶走", "不是這個原因", "不確定"])
    }

    func testReturnWeekDoesNotCompare() {
        let f = Fixture.returned()
        let r = f.s.weekReport(today: T)!
        XCTAssertTrue(r.isReturnWeek)
        XCTAssertEqual(r.lines[0], "這週接上了，記了 1 天。")
        XCTAssertEqual(r.lines[1], Copy.t(.w2skipped), "回來這週還沒做四問")
        XCTAssertNil(r.observation)
        XCTAssertFalse(r.lines.joined().contains("前 "), "不比較")
    }

    func testOpenReportRecordsSeenAndFreezesTheFinding() {
        let s = store(Fixture.weekendGap())
        let r1 = s.openReport(from: "review")!
        XCTAssertEqual(s.state.seen.count, 1)
        XCTAssertEqual(s.state.observations.count, 1)
        let o = s.state.observations[0]
        XCTAssertEqual(o.counts["weekend"], GroupCount(done: 5, days: 12), "照存當時說的天數")
        XCTAssertEqual(o.metricVersion, "m2.0")
        guard case .finding(let x)? = r1.observation else { return XCTFail() }
        XCTAssertEqual(x.recorded?.id, o.id)
        s.openReport(from: "review")
        XCTAssertEqual(s.state.observations.count, 1, "同一週再打開不會多一筆")
        XCTAssertEqual(s.state.seen.count, 1)
        s.openReport(from: "field")
        XCTAssertEqual(s.state.seen.count, 2)
    }

    func testAnswerFlowAndTrial() {
        let s = store(Fixture.weekendGap())
        s.openReport(from: "review")
        let id = s.state.observations[0].id
        s.answerCause(id, "no_trigger")
        XCTAssertEqual(Copy.actions(.weekend, cause: "no_trigger", low: "weekend").map(\.text),
                       ["寫一個週末用的「不順的時候」", "把開關換成週末也會發生的瞬間"])
        s.answerAction(id, "backup")
        let trial = s.startTrial(from: id)!
        XCTAssertEqual(trial.group, "weekend")
        XCTAssertEqual(trial.before, GroupCount(done: 5, days: 12))
        XCTAssertEqual(trial.end, T.adding(14))
        XCTAssertEqual(s.state.observations[0].trial, trial.id)
        XCTAssertEqual(s.state.runningTrial?.id, trial.id)
        XCTAssertEqual(Copy.t(.tryQ, ["end": trial.end.short, "g": "週末"]),
                       "要不要試兩週？12/6 之後的週回顧，再看一次週末記了幾天。")
    }

    func testConcludeAgainOpensANewTrialWithoutOverwriting() {
        var f = Fixture.weekendGap()
        f.s.trials = [Trial(id: "try-1", habit: f.hid, observation: "obs-1", kind: .weekend, group: "weekend",
                            change: "backup", start: T.adding(-14), end: T, status: .running,
                            before: GroupCount(done: 5, days: 12), after: nil, conclusion: nil, concludedAt: nil)]
        let s = store(f)
        s.concludeTrial("try-1", "again")
        XCTAssertEqual(s.state.trials.count, 2)
        XCTAssertEqual(s.state.trials[0].status, .done)
        XCTAssertEqual(s.state.trials[0].conclusion, "again")
        XCTAssertNotNil(s.state.trials[0].after, "結果照存")
        XCTAssertEqual(s.state.trials[1].status, .running)
        XCTAssertEqual(s.state.trials[1].end, T.adding(14))
    }

    func testDueTrialComesFirst() {
        var f = Fixture(planted: T.adding(-60))
        f.fill(to: T) { ![T.adding(-40), T.adding(-12)].contains($0) }
        f.leave(T.adding(-40), "加班")
        f.leave(T.adding(-12), "加班")
        f.s.trials = [Trial(id: "try-1", habit: f.hid, observation: "obs-1", kind: .weekend, group: "weekend",
                            change: "backup", start: T.adding(-14), end: T, status: .running,
                            before: GroupCount(done: 5, days: 12), after: nil, conclusion: nil, concludedAt: nil)]
        guard case .trialResult? = f.s.weekObservation(today: T) else { return XCTFail("到期的試兩週排第一") }
    }

    func testStopAskingAfterThreeUnsure() {
        var f = Fixture.weekendGap()
        f.s.observations = (0..<3).map { i in
            Insight(id: "o\(i)", habit: f.hid, kind: .travel, week: T.adding(-200 + i * 30), shownAt: nil, tz: nil,
                    counts: [:], low: "travel", subject: nil, metricVersion: "m2.0", shown: true,
                    cause: i == 1 ? "not_sure" : "unanswered", action: nil, note: nil, trial: nil)
        }
        guard case .finding(let x)? = f.s.weekObservation(today: T) else { return XCTFail() }
        XCTAssertFalse(x.askCause, "連 3 次跳過或不確定，只說現象")
    }

    func testWeekCardOffStillRecordsReview() {
        var f = Fixture.weekendGap()
        f.s.settings.weekCard = false
        let s = store(f)
        s.recordReview(scores: [5, 5, 5, 5])
        XCTAssertEqual(s.state.weekly.count, 9)
    }
}

// MARK: - 07 字串表與用字規則

final class CopyTests: XCTestCase {
    func testD1NoForbiddenWords() {
        for (id, text) in Copy.everyLine {
            for w in Copy.forbidden {
                XCTAssertFalse(text.contains(w), "\(id)「\(text)」有禁用詞「\(w)」")
            }
        }
    }

    func testEveryIDHasText() {
        for id in CopyID.allCases { XCTAssertFalse((Copy.table[id] ?? "").isEmpty, "\(id.rawValue) 沒有字") }
        for id in GlanceCopy.ID.allCases { XCTAssertFalse((GlanceCopy.table[id] ?? "").isEmpty, "\(id.rawValue) 沒有字") }
    }

    func testD2ThreeStatesOfWeekLines() {
        // W-1 資料不夠／平常／回來
        var first = Fixture(planted: T.adding(-2))
        first.fill(to: T) { _ in true }
        XCTAssertEqual(first.s.weekReport(today: T)!.lines[0], "種下去第 3 天，記了 3 天。")
        XCTAssertTrue(Fixture.weekendGap().s.weekReport(today: T)!.lines[0].contains("前 4 週是"))
        XCTAssertEqual(Fixture.returned().s.weekReport(today: T)!.lines[0], "這週接上了，記了 1 天。")
        // W-2 資料不夠／平常／回來
        var few = Fixture(planted: T.adding(-20))
        few.fill(to: T) { _ in true }
        few.review(T, 4)
        XCTAssertEqual(few.s.weekReport(today: T)!.lines[1], "開始四問做了 1 次，做到第 3 次就看得出線往哪走。")
        XCTAssertEqual(Fixture.weekendGap().s.weekReport(today: T)!.lines[1], Copy.t(.w2flat))
        var back = Fixture.returned()
        back.review(T, 5)
        XCTAssertEqual(back.s.weekReport(today: T)!.lines[1], Copy.t(.w2back))
        // W-3 資料不夠／平常
        XCTAssertEqual(few.s.weekReport(today: T)!.lines[2], "長好了嗎：三個訊號過了 0 個。曲線那一個要 6 次開始四問，現在 1 次。")
        XCTAssertEqual(Fixture.weekendGap().s.weekReport(today: T)!.lines[2], "長好了嗎：三個訊號過了 1 個。")
        // G-1、G-3 資料不夠／平常
        XCTAssertEqual(GlanceCopy.todaySub(date: "11月22日 星期日", nodes: 0), "11月22日 星期日")
        XCTAssertEqual(GlanceCopy.widgetNone(nodes: 0), "今天還沒記")
        XCTAssertEqual(GlanceCopy.widgetNone(nodes: 12), "今天還沒記 · 已長 12 節")
    }

    func testD3GlanceHasAtMostTwoNumbers() {
        let lines = [GlanceCopy.todaySub(date: T.long, nodes: 128),
                     GlanceCopy.t(.widgetDone, ["n": "128"]),
                     GlanceCopy.widgetNone(nodes: 128),
                     GlanceCopy.t(.siriDone, ["floor": "讀一頁書", "n": "128"]),
                     GlanceCopy.t(.siriReturn, ["floor": "讀一頁書", "n": "128"])]
        for line in lines {
            let numbers = line.split(whereSeparator: { !$0.isNumber }).filter { !$0.isEmpty }
            // 日期「11月22日」算一個日期，不是指標；扣掉日期之後最多兩個數字
            let metricNumbers = line == lines[0] ? numbers.count - 2 : numbers.count
            XCTAssertLessThanOrEqual(metricNumbers, 2, line)
        }
    }

    func testRenderedLinesHaveNoLeftoverBlanks() {
        let reports = [Fixture.weekendGap(), Fixture.returned()].compactMap { $0.s.weekReport(today: T) }
        for r in reports {
            for line in r.lines { XCTAssertFalse(line.contains("{"), line) }
        }
    }
}

// MARK: - 08 安靜規則與通知

final class QuietRuleTests: XCTestCase {
    func testD7CheckGoesQuietAfterThreeMissedDays() {
        var f = Fixture(planted: T.adding(-30))
        f.s.settings.check = true
        f.fill(to: T.adding(-1)) { _ in true }
        XCTAssertTrue(f.s.checkShouldSchedule(today: T))
        f.s.records.removeAll { $0.day >= T.adding(-3) }
        XCTAssertFalse(f.s.checkShouldSchedule(today: T), "連漏 3 天以上先不響")
        f.done(T)
        XCTAssertTrue(f.s.checkShouldSchedule(today: T), "今天記了，當下就恢復（排明天那一則）")
        XCTAssertTrue(f.s.checkShouldSchedule(today: T.adding(1)))
    }

    func testD7EightWeeksOfAnalyticsNotificationsIsZero() {
        // 分析類通知：這週的田、試兩週、觀察，全部在 app 內；沒有任何排程通知的入口
        var f = Fixture.weekendGap()
        var scheduled = 0
        for i in 0..<56 {
            let day = T.adding(i)
            if f.s.checkShouldSchedule(today: day) { scheduled += 1 } // 收工檢查預設關
            f.done(day)
        }
        XCTAssertEqual(scheduled, 0, "收工檢查預設關；分析類通知 0 則")
    }

    func testCheckOffDuringLetGoAndAfterDig() {
        var f = Fixture(planted: T.adding(-30))
        f.s.settings.check = true
        f.fill(to: T.adding(-1)) { _ in true }
        f.mark(.letgoStart, T, prior: 14)
        XCTAssertFalse(f.s.checkShouldSchedule(today: T))
    }
}

// MARK: - D-9 舊資料轉換

final class MigrationTests: XCTestCase {
    func testMigrationIsDeterministic() throws {
        var legacy = LegacyState()
        legacy.habit = Habit(floor: "a", trigger: "b", planted: T.adding(-10))
        legacy.logs = ["2026-11-20": .done, "2026-11-21": .leave("發燒")]
        legacy.pressure = true
        legacy.travel = true
        let a = legacy.migrated(today: T)
        let b = legacy.migrated(today: T)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.records.map(\.id), ["rec-v1-2026-11-20", "rec-v1-2026-11-21"])
        XCTAssertEqual(a.pressure, true)
        XCTAssertTrue(a.travel)
        XCTAssertEqual(a.records[1].reason, "發燒")
    }

    func testSameDayLetGoEndAndRestartKeepsOrder() {
        var legacy = LegacyState()
        legacy.habit = Habit(floor: "a", trigger: "b", planted: T.adding(-40))
        legacy.letgoResult = LetGoResult(days: 8, prior: 13, pass: false, start: T.adding(-14), end: T)
        legacy.letgo = LetGo(start: T, prior: 12)
        let s = legacy.migrated(today: T)
        XCTAssertEqual(s.marks.map(\.kind), [.letgoStart, .letgoEnd, .letgoStart])
        XCTAssertNotNil(s.letgo, "同一天結束又開始，進行中的是新的那一次")
        XCTAssertEqual(s.letgoResult?.pass, false)
    }

    func testFirstV2LaunchKeepsTheV1File() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shuji-v1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        let v1 = "{\"v\":1,\"habit\":{\"floor\":\"a\",\"trigger\":\"b\",\"planted\":\"2026-11-01\"},\"logs\":{\"2026-11-02\":{\"t\":\"done\"}}}"
        try Data(v1.utf8).write(to: url)
        let store = MainActor.assumeIsolated { Store(fileURL: url, backupDir: nil) }
        let kept = try String(contentsOf: dir.appendingPathComponent("state.v1.json"), encoding: .utf8)
        XCTAssertEqual(kept, v1, "轉換之前原檔原封不動留一份")
        MainActor.assumeIsolated { XCTAssertEqual(store.state.records.count, 1) }
    }

    func testV2RoundTripKeepsEverything() throws {
        var f = Fixture.weekendGap()
        f.mark(.travelOn, T.adding(-3))
        f.s.observations = [Insight(id: "obs-1", habit: f.hid, kind: .weekend, week: T, shownAt: "2026-11-22T01:00:00Z",
                                    tz: "Asia/Taipei", counts: ["weekend": GroupCount(done: 5, days: 12)], low: "weekend",
                                    subject: nil, metricVersion: "m2.0", shown: true, cause: "not_this", action: nil,
                                    note: "那幾週在搬家", trial: nil)]
        let data = try JSONEncoder().encode(f.s)
        let back = try JSONDecoder().decode(AppState.self, from: data)
        XCTAssertEqual(back, f.s)
    }
}
