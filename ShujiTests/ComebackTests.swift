import XCTest
@testable import Shuji

// docs/回來與放手-規格.md 的自動測試。2026-11-22 是星期日（預設回顧日）

private let T = DayKey("2026-11-22")!

private struct Garden {
    var s = AppState()
    let hid = "hab-test"

    init(planted: DayKey) {
        s.habit = Habit(floor: "坐上蒲團", trigger: "刷完牙", planted: planted, id: hid)
    }

    mutating func done(_ d: DayKey, at: String? = nil, source: RecordSource = .hold) {
        s.records.append(DayRecord(id: "rec-\(s.records.count)", habit: hid, kind: .done, day: d,
                                   at: at, tz: "Asia/Taipei", source: source))
    }

    mutating func fill(to last: DayKey, except: [DayKey] = []) {
        var d = s.habit!.planted
        while d <= last {
            if !except.contains(d) { done(d) }
            d = d.adding(1)
        }
    }

    mutating func reviews(_ values: [Double], last: DayKey) {
        for (i, v) in values.enumerated() {
            s.reviews.append(WeeklyReview(date: last.adding(-7 * (values.count - 1 - i)), scores: [v, v, v, v],
                                          id: "rev-\(i)", habit: hid))
        }
    }

    mutating func mark(_ kind: Mark.Kind, _ d: DayKey) {
        s.marks.append(Mark(id: "mark-\(s.marks.count)", habit: hid, kind: kind, day: d, at: nil, tz: nil))
    }

    mutating func gap(_ from: DayKey, _ to: DayKey, _ reason: String) {
        s.gaps.append(Gap(id: "gap-\(s.gaps.count)", habit: hid, from: from, to: to, reason: reason))
    }
}

final class PendingGapTests: XCTestCase {
    func testYesterdayOnly() {
        var g = Garden(planted: T.adding(-20))
        g.fill(to: T.adding(-2))
        XCTAssertEqual(g.s.pendingGap(today: T), PendingGap(from: T.adding(-1), to: T.adding(-1)))
        XCTAssertEqual(g.s.pendingGap(today: T)?.onlyYesterday, true)
        XCTAssertEqual(g.s.autoAsk(today: T), .back, "四問也要問，但先問這個")
    }

    func testNothingMissed() {
        var g = Garden(planted: T.adding(-20))
        g.fill(to: T.adding(-1))
        XCTAssertNil(g.s.pendingGap(today: T), "今天還沒過完不算")
    }

    func testSeveralDaysAndAlreadyAsked() {
        var g = Garden(planted: T.adding(-20))
        g.fill(to: T.adding(-5))
        XCTAssertEqual(g.s.pendingGap(today: T), PendingGap(from: T.adding(-4), to: T.adding(-1)))
        g.gap(T.adding(-4), T.adding(-3), "")
        XCTAssertNil(g.s.pendingGap(today: T), "同一段問過就不再問，一直漏也不會每天問")
        g.done(T)
        XCTAssertEqual(g.s.pendingGap(today: T.adding(2)), PendingGap(from: T.adding(1), to: T.adding(1)), "接上之後是新的一段")
    }

    func testLongAbsenceHasNoCard() {
        var g = Garden(planted: T.adding(-40))
        g.fill(to: T.adding(-14))
        XCTAssertEqual(g.s.pendingGap(today: T)?.days, 13)
        var h = Garden(planted: T.adding(-40))
        h.fill(to: T.adding(-15))
        XCTAssertNil(h.s.pendingGap(today: T), "十四天以上由今天頁自己說")
        XCTAssertTrue(h.s.longAbsence(today: T))
        XCTAssertFalse(h.s.returnedFromLong(today: T))
        h.done(T)
        XCTAssertTrue(h.s.returnedFromLong(today: T))
        XCTAssertNil(h.s.pendingGap(today: T))
    }

    func testLetGoIsQuiet() {
        var g = Garden(planted: T.adding(-40))
        g.fill(to: T.adding(-4))
        g.mark(.letgoStart, T.adding(-3))
        XCTAssertNil(g.s.pendingGap(today: T))
    }

    func testReasonKeepsTheReturn() {
        var g = Garden(planted: T.adding(-20))
        g.fill(to: T.adding(-4))
        g.gap(T.adding(-3), T.adding(-1), "旅行")
        g.done(T)
        XCTAssertTrue(g.s.isReturn(T), "寫了理由照樣算漏掉，回來照樣開花")
        XCTAssertEqual(g.s.stats(today: T).missed, 3)
        XCTAssertEqual(g.s.topGapReasons(today: T), [.init(reason: "旅行", count: 1)])
    }

    func testReasonDisappearsWhenBackfilled() {
        var g = Garden(planted: T.adding(-20))
        g.fill(to: T.adding(-2))
        g.gap(T.adding(-1), T.adding(-1), "太累")
        XCTAssertEqual(g.s.topGapReasons(today: T).count, 1)
        g.done(T.adding(-1), source: .backfill)
        XCTAssertEqual(g.s.topGapReasons(today: T), [])
    }

    @MainActor
    func testStoreClosesOnceAndSurvivesCoding() throws {
        let s = Store(fileURL: nil, backupDir: nil)
        s.plant(floor: "坐上蒲團", trigger: "刷完牙")
        let gap = PendingGap(from: s.today.adding(-2), to: s.today.adding(-1))
        s.closeGap(gap, reason: " 太忙 ")
        s.closeGap(gap, reason: "")
        XCTAssertEqual(s.state.gaps.map(\.reason), ["太忙"])
        s.answerBasket(Potato(floor: "a", trigger: "b", nodes: 1, ret: 0, days: 1, planted: T, dug: T, id: "pot"), still: true)
        let back = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(s.state))
        XCTAssertEqual(back.gaps, s.state.gaps)
        XCTAssertEqual(back.checks, s.state.checks)
    }
}

final class ReminderTests: XCTestCase {
    private func calm() -> Garden {
        var g = Garden(planted: T.adding(-60))
        g.s.settings.check = true
        g.fill(to: T.adding(-1))
        g.reviews([4, 4.5, 5], last: T)
        return g
    }

    func testShiftsToAfterMiss() {
        XCTAssertEqual(calm().s.reminderShift(today: T), .remindAfterMiss)
        var low = calm()
        low.s.reviews = []
        low.reviews([2, 2.5, 3], last: T)
        XCTAssertNil(low.s.reminderShift(today: T), "還要逼自己，照舊每天提醒")
        var off = calm()
        off.s.settings.check = false
        XCTAssertNil(off.s.reminderShift(today: T))
        var fresh = calm()
        fresh.mark(.remindDaily, T.adding(-3))
        XCTAssertNil(fresh.s.reminderShift(today: T), "剛自己打開的，先待滿兩週")
    }

    func testAfterMissOnlyRingsAfterAMiss() {
        var g = calm()
        g.mark(.remindAfterMiss, T.adding(-5))
        XCTAssertEqual(g.s.reminderDays(today: T), [T.adding(1), T.adding(2)], "昨天有做，今天不響")
        g.done(T)
        XCTAssertEqual(g.s.reminderDays(today: T), [T.adding(2)])
        g.s.records.removeAll { $0.day >= T.adding(-1) }
        XCTAssertEqual(g.s.reminderDays(today: T).first, T, "昨天漏了，今天響")
        g.s.records.removeAll { $0.day >= T.adding(-2) }
        XCTAssertEqual(g.s.reminderShift(today: T), .remindDaily, "連漏兩天，調回每天")
    }

    func testDailyDays() {
        var g = calm()
        XCTAssertEqual(g.s.reminderDays(today: T), [T, T.adding(1)])
        g.done(T)
        XCTAssertEqual(g.s.reminderDays(today: T), [T.adding(1)])
        XCTAssertEqual(g.s.reminderText, "刷完牙，坐上蒲團。做完回來按住一下。")
    }

    func testStopThenReturn() {
        var g = calm()
        g.mark(.remindAfterMiss, T.adding(-13))
        XCTAssertFalse(g.s.reminderCanStop(today: T))
        g.done(T)
        XCTAssertTrue(g.s.reminderCanStop(today: T.adding(1)))
        XCTAssertEqual(g.s.autoAsk(today: T.adding(1)), .remindOff)

        var h = Garden(planted: T.adding(-60))
        h.fill(to: T.adding(-4))
        h.done(T.adding(-1))
        h.mark(.remindOff, T.adding(-10))
        XCTAssertTrue(h.s.reminderMayReturn(today: T), "T-3、T-2 連漏")
        for i in 0...2 { h.done(T.adding(i)) }
        XCTAssertFalse(h.s.reminderMayReturn(today: T.adding(3)), "過了就不追")
    }

    @MainActor
    func testNewHabitStartsRemindingAgain() {
        let s = Store(fileURL: nil, backupDir: nil)
        s.plant(floor: "坐上蒲團", trigger: "刷完牙")
        s.setReminder(true)
        s.stopReminder()
        XCTAssertFalse(s.state.settings.check)
        s.plant(floor: "讀一頁書", trigger: "上床前")
        XCTAssertTrue(s.state.settings.check)
        XCTAssertEqual(s.state.reminderStage, .daily)
    }
}

final class GrownTests: XCTestCase {
    func testNeedsEaseAndOneMore() {
        var g = Garden(planted: T.adding(-60))
        g.reviews([3.5, 3.5, 3.5, 3.5, 3.5, 3.5], last: T)
        g.mark(.pressureYes, T.adding(-3))
        XCTAssertFalse(g.s.signals(today: T).grown, "停在 3 點多還不算")
        XCTAssertFalse(g.s.signals(today: T).flatLow)
        g.s.reviews = []
        g.reviews([4, 4, 4, 4, 4, 4], last: T)
        XCTAssertTrue(g.s.signals(today: T).grown)
    }

    /// 放手兩週不問四問，回來問一次就看得出來
    func testLetGoDaysDoNotMakeItStale() {
        var g = Garden(planted: T.adding(-90))
        g.reviews([5, 5, 5, 5, 5, 5], last: T.adding(-15))
        g.s.marks.append(Mark(id: "a", habit: g.hid, kind: .letgoStart, day: T.adding(-14), at: nil, tz: nil, prior: 13))
        g.s.marks.append(Mark(id: "b", habit: g.hid, kind: .letgoEnd, day: T, at: nil, tz: nil, prior: 13, recalled: 13, pass: true))
        XCTAssertTrue(g.s.signals(today: T).s1)
        g.s.reviews.append(WeeklyReview(date: T, scores: [5, 5, 5, 5], id: "rev-x", habit: g.hid))
        XCTAssertFalse(g.s.signals(today: T).spread)
        XCTAssertTrue(g.s.signals(today: T).grown)
    }
}

final class UsualTimeTests: XCTestCase {
    func testMorningCluster() {
        var g = Garden(planted: T.adding(-20))
        // 台北早上 7:10 到 7:50；兩筆在晚上
        for i in 1...8 { g.done(T.adding(-i), at: "2026-11-\(i + 9)T23:\(10 + i * 5):00Z") }
        for i in 9...10 { g.done(T.adding(-i), at: "2026-11-10T13:00:00Z") }
        let u = g.s.usualTime(today: T)
        XCTAssertEqual(u?.points.count, 10)
        XCTAssertEqual(u?.text, "早上 7 點多")
        XCTAssertEqual(u?.start, 152, "7:15 到 7:50 排在兩小時的正中間")
        XCTAssertEqual(g.s.fieldCards(today: T).time?.answer, "多半早上 7 點多")
    }

    func testNotEnoughOrScattered() {
        XCTAssertNil(UsualTime(points: Array(repeating: 100, count: 9)))
        XCTAssertNil(UsualTime(points: (0..<12).map { $0 * 110 }))
        XCTAssertEqual(UsualTime(points: Array(repeating: 1230, count: 10))?.text, "半夜 12 點多")
        XCTAssertEqual(UsualTime(points: Array(repeating: 0, count: 10))?.text, "清晨 4 點多")
        XCTAssertEqual(UsualTime(points: Array(repeating: 510, count: 10))?.text, "中午 12 點多")
    }

    func testBackfillAndImportedDoNotCount() {
        var g = Garden(planted: T.adding(-20))
        for i in 1...10 { g.done(T.adding(-i), at: "2026-11-10T23:10:00Z", source: i % 2 == 0 ? .backfill : .imported) }
        XCTAssertNil(g.s.usualTime(today: T))
    }

    func testWeekReviewInputCarriesThem() throws {
        var g = Garden(planted: T.adding(-40))
        g.fill(to: T.adding(-2))
        g.gap(T.adding(-1), T.adding(-1), "太累")
        let i = try XCTUnwrap(g.s.weekReviewInput(end: T, today: T))
        XCTAssertEqual(i.ease, "few")
        XCTAssertEqual(i.usual_time, "")
        XCTAssertEqual(i.gap_reasons, [.init(reason: "太累", count: 1)])
    }
}

final class BasketAskTests: XCTestCase {
    private func potato(_ id: String, dug: DayKey) -> Potato {
        Potato(floor: "地瓜\(id)", trigger: "刷完牙", nodes: 60, ret: 2, days: 80, planted: dug.adding(-80), dug: dug, id: id)
    }

    private func garden() -> Garden {
        var g = Garden(planted: T.adding(-30))
        g.fill(to: T)
        g.reviews([3, 5, 3], last: T)
        g.s.basket = [potato("a", dug: T.adding(-14)), potato("b", dug: T.adding(-40)), potato("c", dug: T.adding(-5))]
        return g
    }

    func testPicksTheOneNotAskedForLongest() {
        var g = garden()
        XCTAssertEqual(g.s.basketAsk(today: T)?.id, "b")
        XCTAssertEqual(g.s.autoAsk(today: T), .basket)
        g.s.checks = [BasketCheck(id: "x", potato: "b", day: T, still: true)]
        XCTAssertNil(g.s.basketAsk(today: T), "這週問過了")
        g.s.checks = [BasketCheck(id: "x", potato: "b", day: T.adding(-7), still: true)]
        XCTAssertEqual(g.s.basketAsk(today: T)?.id, "a")
        g.s.reviews = []
        XCTAssertNil(g.s.basketAsk(today: T), "四問還沒做就不問")
    }

    @MainActor
    func testTwiceFadedGoesToTheFrontOfTheQueue() {
        let s = Store(fileURL: nil, backupDir: nil)
        s.plant(floor: "坐上蒲團", trigger: "刷完牙")
        s.addQueue("讀一頁書")
        let p = potato("a", dug: s.today.adding(-30))
        s.state.basket = [p]
        s.answerBasket(p, still: false)
        XCTAssertEqual(s.state.queue, ["讀一頁書"])
        s.answerBasket(p, still: false)
        XCTAssertEqual(s.state.queue, ["地瓜a", "讀一頁書"])
        XCTAssertEqual(s.state.basket.count, 1, "地瓜留在竹籃")
        XCTAssertTrue(s.state.faded(p))
        XCTAssertEqual(s.state.habit?.floor, "坐上蒲團")
    }
}
