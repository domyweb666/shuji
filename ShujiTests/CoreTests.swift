import XCTest
@testable import Shuji

// 標準答案是用 Node 跑原型 index.html 裡同一段 JS 算出來的（today 固定 2026-11-07），
// 這裡只比對 Swift 版算出來的是不是一模一樣。

private let T = DayKey("2026-11-07")!

/// 原型「載入示範資料」後「匯出備份」會得到的那段 JSON，一字不改
private let prototypeBackup = """
{"v":1,"habit":{"floor":"打開檔案寫一句","trigger":"起床喝完第一杯水","travelFloor":"在手機上寫三行","obstacle":"如果早上要出門，就在捷運上用手機寫三行","backup":"如果中午前還沒打開過檔案，就在第一餐吃完時打開","why":"把複雜的事想清楚、寫下來","planted":"2026-09-23"},"logs":{"2026-09-23":{"t":"done"},"2026-09-24":{"t":"done"},"2026-09-25":{"t":"done"},"2026-09-26":{"t":"done"},"2026-09-27":{"t":"done"},"2026-09-30":{"t":"done"},"2026-10-01":{"t":"done"},"2026-10-02":{"t":"done"},"2026-10-03":{"t":"done"},"2026-10-04":{"t":"done"},"2026-10-05":{"t":"done"},"2026-10-07":{"t":"done"},"2026-10-08":{"t":"done"},"2026-10-09":{"t":"done"},"2026-10-10":{"t":"leave","reason":"出遠門"},"2026-10-11":{"t":"done"},"2026-10-12":{"t":"done"},"2026-10-13":{"t":"done"},"2026-10-16":{"t":"done"},"2026-10-17":{"t":"done"},"2026-10-18":{"t":"done"},"2026-10-19":{"t":"done"},"2026-10-20":{"t":"done"},"2026-10-21":{"t":"done"},"2026-10-22":{"t":"done"},"2026-10-24":{"t":"done"},"2026-10-25":{"t":"done"},"2026-10-26":{"t":"done"},"2026-10-27":{"t":"done"},"2026-10-28":{"t":"done"},"2026-10-29":{"t":"done"},"2026-10-30":{"t":"done"},"2026-11-01":{"t":"done"},"2026-11-02":{"t":"done"},"2026-11-03":{"t":"done"},"2026-11-04":{"t":"done"},"2026-11-05":{"t":"done"},"2026-11-06":{"t":"done"}},"weekly":[{"date":"2026-09-29","scores":[2.25,2.25,2.25,2.25],"avg":2.25},{"date":"2026-10-06","scores":[3,3,3,3],"avg":3},{"date":"2026-10-13","scores":[3.75,3.75,3.75,3.75],"avg":3.75},{"date":"2026-10-20","scores":[4.25,4.25,4.25,4.25],"avg":4.25},{"date":"2026-10-27","scores":[4.75,4.75,4.75,4.75],"avg":4.75},{"date":"2026-11-03","scores":[5,5,5,5],"avg":5},{"date":"2026-11-10","scores":[5,5,5,5],"avg":5}],"basket":[{"floor":"刷完牙做一下伸展","trigger":"刷完牙","nodes":71,"ret":9,"days":84,"planted":"2026-06-25","dug":"2026-09-17"}],"queue":["坐上蒲團按計時器","換上球鞋拿球出門"],"pressure":null,"letgo":null,"letgoResult":null,"justDug":null,"travelEndedOn":null,"settings":{"sound":true,"reviewDay":0,"leave":2},"dayOffset":0}
"""

private func localDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
    return Calendar.current.date(from: c)!
}


// 測試用：v2 的紀錄只能加、不能直接改字典，這幾個小工具讓舊測試照原本的意思寫
extension AppState {
    /// 拿掉某一天目前習慣的紀錄（模擬那天沒記）
    mutating func drop(_ day: String) {
        guard let id = habit?.id else { return }
        records.removeAll { $0.habit == id && $0.day.string == day }
    }

    /// 放一筆某天的紀錄（同一天原本的先拿掉）
    mutating func put(_ day: String, _ log: DayLog, tz: String? = nil) {
        guard let id = habit?.id, let k = DayKey(day) else { return }
        drop(day)
        records.append(DayRecord(id: "test-\(day)", habit: id, kind: log.t, day: k, at: nil, tz: tz,
                                 source: .hold, reason: log.reason))
    }

    /// 只留這幾天的紀錄
    mutating func keepOnly(_ days: [String: DayLog]) {
        guard let id = habit?.id else { return }
        records.removeAll { $0.habit == id }
        for (d, l) in days { put(d, l) }
    }

    /// 換掉目前習慣的開始四問
    mutating func setWeekly(_ w: [WeeklyReview]) {
        guard let id = habit?.id else { return }
        reviews.removeAll { $0.habit == id }
        reviews.append(contentsOf: w.map { var r = $0; r.habit = id; return r })
    }

    mutating func mark(_ kind: Mark.Kind, _ day: DayKey, prior: Int? = nil, recalled: Int? = nil, pass: Bool? = nil) {
        let habitID: String? = (kind == .travelOn || kind == .travelOff) ? nil : habit?.id
        marks.append(Mark(id: "test-mark-\(marks.count)", habit: habitID, kind: kind, day: day, at: nil, tz: nil,
                          prior: prior, recalled: recalled, pass: pass))
    }
}

// MARK: - 日期

final class DayKeyTests: XCTestCase {
    func testParseAndFormat() {
        XCTAssertEqual(DayKey("2026-11-07")?.string, "2026-11-07")
        XCTAssertEqual(DayKey("2026-01-05")?.string, "2026-01-05")
        XCTAssertNil(DayKey("2026-13-01"))
        XCTAssertNil(DayKey("abc"))
        XCTAssertNil(DayKey("2026-11"))
    }

    func testDayNumberMatchesPrototypeDayNo() {
        XCTAssertEqual(DayKey("1970-01-01")!.dayNumber, 0)
        XCTAssertEqual(DayKey("2000-02-29")!.dayNumber, 11016)
        XCTAssertEqual(DayKey("2026-11-07")!.dayNumber, 20764)
    }

    func testWeekdayMatchesJSGetDay() {
        XCTAssertEqual(DayKey("2026-11-07")!.weekday, 6)
        XCTAssertEqual(DayKey("2026-01-01")!.weekday, 4)
        XCTAssertEqual(DayKey("2000-01-01")!.weekday, 6)
        XCTAssertEqual(DayKey("1970-01-01")!.weekday, 4)
    }

    func testAddingAcrossBoundaries() {
        XCTAssertEqual(DayKey("2024-02-28")!.adding(1).string, "2024-02-29")
        XCTAssertEqual(DayKey("2025-12-31")!.adding(1).string, "2026-01-01")
        XCTAssertEqual(DayKey("2026-03-01")!.adding(-1).string, "2026-02-28")
        XCTAssertEqual(DayKey("2026-11-07")!.adding(-45).string, "2026-09-23")
    }

    func testDaysBetween() {
        XCTAssertEqual(DayKey.days(from: DayKey("2026-09-23")!, to: T), 45)
        XCTAssertEqual(DayKey.days(from: T, to: DayKey("2026-09-23")!), -45)
    }

    func testRoundTripOverWideRange() {
        for n in stride(from: -200_000, through: 200_000, by: 997) {
            XCTAssertEqual(DayKey(dayNumber: n).dayNumber, n)
        }
    }

    func testComparableFollowsCalendar() {
        XCTAssertTrue(DayKey("2026-09-30")! < DayKey("2026-10-01")!)
        XCTAssertTrue(DayKey("2025-12-31")! < DayKey("2026-01-01")!)
    }

    func testFourAMBoundary() {
        XCTAssertEqual(DayKey.today(now: localDate(2026, 11, 7, 3, 59)).string, "2026-11-06")
        XCTAssertEqual(DayKey.today(now: localDate(2026, 11, 7, 4, 0)).string, "2026-11-07")
        XCTAssertEqual(DayKey.today(now: localDate(2026, 11, 7, 23, 30)).string, "2026-11-07")
    }

    func testOffset() {
        XCTAssertEqual(DayKey.today(now: localDate(2026, 11, 7, 12, 0), offset: 7).string, "2026-11-14")
    }

    func testDisplay() {
        XCTAssertEqual(T.long, "11月7日 星期六")
        XCTAssertEqual(T.short, "11/7")
        XCTAssertEqual(T.monthPrefix, "2026-11")
    }
}

// MARK: - 計算

final class LogicTests: XCTestCase {
    private var demo: AppState { AppState.demo(today: T) }

    func testDemoStatsMatchPrototype() {
        let s = demo.stats(today: T)
        XCTAssertEqual(s, AppState.Stats(nodes: 37, ret: 5, missed: 7, leaves: 0, leaveLeft: 2))
    }

    func testReturnsMatchPrototype() {
        let d = demo
        let ds = d.doneKeys
        let returns = ds.filter { d.isReturn($0) }.map(\.string)
        XCTAssertEqual(returns, ["2026-09-30", "2026-10-07", "2026-10-16", "2026-10-24", "2026-11-01"])
        // 請假隔天不算回來（請假有紀錄）
        XCTAssertFalse(d.isReturn(DayKey("2026-10-11")!))
        // 第一節不算回來
        XCTAssertFalse(d.isReturn(DayKey("2026-09-23")!))
    }

    func testLastDoneAndConsecutiveMissed() {
        var d = demo
        XCTAssertEqual(d.lastDone?.string, "2026-11-06")
        XCTAssertEqual(d.consecutiveMissed(today: T), 0)
        d.drop("2026-11-06")
        d.drop("2026-11-05")
        XCTAssertEqual(d.consecutiveMissed(today: T), 2)
        XCTAssertEqual(d.lastDone?.string, "2026-11-04")
    }

    func testNeedReview() {
        for rd in 0..<7 {
            var d = demo
            d.settings.reviewDay = rd
            XCTAssertFalse(d.needReview(today: T), "示範資料最後一次四問在未來，任何回顧日都不該再問")
        }
        var d = demo
        d.settings.reviewDay = 6
        d.setWeekly([])
        XCTAssertTrue(d.needReview(today: T))
        d.setWeekly([WeeklyReview(date: T.adding(-6), scores: [4, 4, 4, 4])])
        XCTAssertTrue(d.needReview(today: T))
        d.setWeekly([WeeklyReview(date: T.adding(-5), scores: [4, 4, 4, 4])])
        XCTAssertFalse(d.needReview(today: T))
        d.settings.reviewDay = 5
        d.setWeekly([])
        XCTAssertFalse(d.needReview(today: T), "今天星期六，回顧日是星期五")
    }

    func testReviewPendingStaysThreeDays() {
        var d = demo
        d.settings.reviewDay = 6   // 2026-11-07 是星期六
        d.setWeekly([])
        XCTAssertEqual(d.lastReviewDay(today: T), T)
        XCTAssertTrue(d.reviewPending(today: T))
        XCTAssertTrue(d.reviewPending(today: T.adding(1)))
        XCTAssertTrue(d.reviewPending(today: T.adding(3)))
        XCTAssertFalse(d.reviewPending(today: T.adding(4)), "回顧日過了三天就不留了")
        XCTAssertEqual(d.lastReviewDay(today: T.adding(4)), T)
        XCTAssertEqual(d.lastReviewDay(today: T.adding(7)), T.adding(7))

        d.setWeekly([WeeklyReview(date: T.adding(-6), scores: [4, 4, 4, 4])])
        XCTAssertTrue(d.reviewPending(today: T), "回顧日當天的判斷跟 needReview 相同")
        XCTAssertEqual(d.reviewPending(today: T), d.needReview(today: T))
        d.setWeekly([WeeklyReview(date: T.adding(-5), scores: [4, 4, 4, 4])])
        XCTAssertFalse(d.reviewPending(today: T))
        XCTAssertEqual(d.reviewPending(today: T), d.needReview(today: T))

        d.setWeekly([WeeklyReview(date: T.adding(1), scores: [4, 4, 4, 4])])
        XCTAssertFalse(d.reviewPending(today: T.adding(2)), "回顧日隔天做了，之後就不再提")

        d.habit = nil
        XCTAssertFalse(d.reviewPending(today: T))
    }

    /// 四問與長好了嗎：打開 app 自動問（AutoAsk）
    func testAutoAsk() {
        var d = demo
        d.settings.reviewDay = 6
        d.setWeekly([])
        d.marks = []
        XCTAssertEqual(d.autoAsk(today: T), .review)
        // 這一段不看停了多久：補一筆最近的紀錄
        for i in 0...5 { d.put(T.adding(i).string, .done) }
        XCTAssertEqual(d.autoAsk(today: T.adding(5)), .review, "過了三天也照樣問")

        func weeks(_ v: Double) -> [WeeklyReview] {
            (0..<6).map { WeeklyReview(date: T.adding(-7 * (5 - $0)), scores: [v, v, v, v]) }
        }
        d.setWeekly(weeks(5))
        XCTAssertEqual(d.autoAsk(today: T), .pressure, "曲線走平，先問壓力週")
        d.mark(.pressureNotYet, T)
        XCTAssertEqual(d.autoAsk(today: T), .letgo)
        d.mark(.pressureYes, T)
        XCTAssertEqual(d.autoAsk(today: T), .dig, "兩個訊號過了")
        d.marks = []
        d.mark(.letgoStart, T, prior: 12)
        XCTAssertNil(d.autoAsk(today: T), "放手中不問")
        XCTAssertTrue(d.autoAsks(today: T).contains(.dig))
        d.marks = []
        d.setWeekly(weeks(2))
        XCTAssertNil(d.autoAsk(today: T), "走平在低處，不問長好了嗎")
        d.habit?.planted = T.adding(-6)
        d.setWeekly([])
        XCTAssertNil(d.autoAsk(today: T), "種不到一週不問")
        d.habit = nil
        XCTAssertNil(d.autoAsk(today: T))
    }

    /// 田的報表
    func testFieldReport() {
        var d = demo
        d.settings.reviewDay = 0
        d.marks = []
        d.habit?.planted = DayKey("2026-10-20")!
        d.keepOnly(["2026-10-20": .done, "2026-11-01": .done, "2026-11-02": .done,
                    "2026-11-03": .leave("出門"), "2026-11-04": .done])
        let m = d.monthReport(today: T, back: 0)
        XCTAssertEqual(m?.days.count, 30)
        XCTAssertEqual(m?.lead, 0, "2026-11-01 是星期日")
        XCTAssertEqual(m?.done, 3)
        XCTAssertEqual(m?.back, 1, "11/1 是漏了之後回來；請假隔天不算回來")
        XCTAssertEqual(m?.leave, 1)
        XCTAssertEqual(m?.days[0].kind, .back)
        XCTAssertEqual(m?.days[2].kind, .leave)
        XCTAssertEqual(d.monthReport(today: T, back: 1)?.days.count, 31)
        XCTAssertNil(d.monthReport(today: T, back: 2), "種下去之前")

        let bars = d.weekBars(today: T)
        XCTAssertEqual(bars.map(\.done), [1, 1, 2], "週回顧日是星期日：10/19、10/26、11/2 起")
        XCTAssertEqual(bars.last?.current, true)
    }

    func testObstacleMigratesIntoBackup() {
        var d = demo
        d.habit?.backup = ""
        d.habit?.obstacle = "如果早上要出門，就在捷運上用手機寫三行"
        d.migrateFields()
        XCTAssertEqual(d.habit?.backup, "如果早上要出門，就在捷運上用手機寫三行")
        XCTAssertEqual(d.habit?.obstacle, "如果早上要出門，就在捷運上用手機寫三行", "obstacle 留著，原型還讀得到")

        var e = demo
        e.habit?.backup = "已經有備案"
        e.habit?.obstacle = "舊的障礙版"
        e.migrateFields()
        XCTAssertEqual(e.habit?.backup, "已經有備案", "backup 有值就不蓋")
    }

    func testSignals() {
        let sg = demo.signals(today: T)
        XCTAssertEqual(sg, AppState.Signals(s1: true, flatLow: false, s2: false, s3: false, n: 7))
        XCTAssertEqual(sg.passCount, 1)

        var d = demo
        d.mark(.pressureYes, T)
        XCTAssertEqual(d.signals(today: T).passCount, 2)

        d.setWeekly((0..<6).map { WeeklyReview(date: T.adding(-42 + $0 * 7), scores: [2, 2, 2, 2]) })
        let low = d.signals(today: T)
        XCTAssertFalse(low.s1, "平均要 4 以上")
        XCTAssertTrue(low.flatLow)

        d.setWeekly((0..<5).map { WeeklyReview(date: T.adding(-35 + $0 * 7), scores: [5, 5, 5, 5]) })
        XCTAssertFalse(d.signals(today: T).s1, "不到六週不算走平")
    }

    func testLetGoPriorAndRule() {
        XCTAssertEqual(demo.doneInLast14Days(today: T), 13)
    }

    func testMissedExcludesFinishedLetGoWindow() {
        var d = demo
        d.drop("2026-11-01")
        d.drop("2026-11-02")
        XCTAssertEqual(d.stats(today: T).missed, 9)
        var a = d
        a.mark(.letgoStart, DayKey("2026-11-01")!, prior: 13)
        a.mark(.letgoEnd, DayKey("2026-11-07")!, prior: 13, recalled: 12, pass: true)
        XCTAssertEqual(a.stats(today: T).missed, 7, "放手那幾天不算漏掉")
        var b = d
        b.mark(.letgoStart, DayKey("2026-10-31")!, prior: 13)
        b.mark(.letgoEnd, DayKey("2026-11-07")!, prior: 13, recalled: 12, pass: true)
        XCTAssertEqual(b.stats(today: T).missed, 6, "10/31 本來就漏掉，被放手窗口蓋住也不算")
    }

    func testLongAbsence() {
        var d = demo
        d.keepOnly(["2026-10-01": .done])
        XCTAssertTrue(d.longAbsence(today: T))
        d.mark(.letgoStart, DayKey("2026-10-20")!, prior: 10)
        d.mark(.letgoEnd, DayKey("2026-11-03")!, prior: 10, recalled: 10, pass: true)
        XCTAssertFalse(d.longAbsence(today: T), "放手測試剛結束，不算停了一陣子")
        d.put(T.string, .done)
        XCTAssertFalse(d.longAbsence(today: T))
        d.keepOnly([:])
        XCTAssertFalse(d.longAbsence(today: T), "一節都沒有的時候不算停")
    }

    func testActiveFloor() {
        var d = demo
        XCTAssertEqual(d.activeFloor, "打開檔案寫一句")
        d.mark(.travelOn, T)
        XCTAssertEqual(d.activeFloor, "在手機上寫三行")
        d.habit?.travelFloor = ""
        XCTAssertEqual(d.activeFloor, "打開檔案寫一句")
    }

    func testPhrasesAreStablePerDay() {
        XCTAssertEqual(Phrases.phrase(for: T, isReturn: false), Phrases.done[18])
        XCTAssertEqual(Phrases.phrase(for: T, isReturn: true), Phrases.returns[4])
        XCTAssertEqual(Phrases.done.count, 22)
        XCTAssertEqual(Phrases.returns.count, 10)
    }

    func testWordingRules() {
        XCTAssertTrue(Wording.isNegative("不滑手機"))
        XCTAssertTrue(Wording.isNegative("少吃甜食"))
        XCTAssertTrue(Wording.isNegative("戒菸"))
        XCTAssertTrue(Wording.isNegative("避免熬夜"))
        XCTAssertFalse(Wording.isNegative("打開檔案寫一句"))
        XCTAssertFalse(Wording.isNegative("讀一頁書"))
        XCTAssertTrue(Wording.isFood("減重五公斤"))
        XCTAssertTrue(Wording.isFood("記錄熱量"))
        XCTAssertFalse(Wording.isFood("坐上蒲團按計時器"))
    }
}

// MARK: - JSON 跟原型互通

final class CodableTests: XCTestCase {
    func testDecodesPrototypeBackup() throws {
        let s = try JSONDecoder().decode(AppState.self, from: Data(prototypeBackup.utf8))
        XCTAssertEqual(s.habit?.floor, "打開檔案寫一句")
        XCTAssertEqual(s.habit?.planted.string, "2026-09-23")
        XCTAssertEqual(s.logs.count, 38)
        XCTAssertEqual(s.logs["2026-10-10"]?.t, .leave)
        XCTAssertEqual(s.logs["2026-10-10"]?.reason, "出遠門")
        XCTAssertEqual(s.weekly.count, 7)
        XCTAssertEqual(s.weekly[0].avg, 2.25)
        XCTAssertEqual(s.basket.count, 1)
        XCTAssertEqual(s.basket[0].nodes, 71)
        XCTAssertEqual(s.queue, ["坐上蒲團按計時器", "換上球鞋拿球出門"])
        XCTAssertNil(s.pressure)
        XCTAssertNil(s.letgo)
        XCTAssertNil(s.letgoResult)
        XCTAssertEqual(s.settings.leave, 2)
        XCTAssertEqual(s.settings.reviewDay, 0)
        XCTAssertTrue(s.settings.sound)
        XCTAssertFalse(s.settings.check)
        XCTAssertEqual(s.dayOffset, 0)
        XCTAssertFalse(s.travel)
        XCTAssertEqual(s.stats(today: T), AppState.Stats(nodes: 37, ret: 5, missed: 7, leaves: 0, leaveLeft: 2))
    }

    func testPrototypeBackupEqualsBuiltInDemo() throws {
        let s = try JSONDecoder().decode(AppState.self, from: Data(prototypeBackup.utf8))
        XCTAssertEqual(s, AppState.demo(today: T))
    }

    func testRoundTrip() throws {
        let a = try JSONDecoder().decode(AppState.self, from: Data(prototypeBackup.utf8))
        let data = try JSONEncoder().encode(a)
        let b = try JSONDecoder().decode(AppState.self, from: data)
        XCTAssertEqual(a, b)
    }

    func testEncodedShapeIsV2() throws {
        let data = try JSONEncoder().encode(AppState.demo(today: T))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["v"] as? Int, 2)
        for key in ["habit", "records", "reviews", "marks", "basket", "queue", "settings", "dayOffset"] {
            XCTAssertNotNil(obj[key], "缺 \(key)")
        }
        XCTAssertNil(obj["logs"], "v2 不再存每天一格的字典")
        let records = try XCTUnwrap(obj["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 38)
        let first = try XCTUnwrap(records.first)
        XCTAssertEqual(first["day"] as? String, "2026-09-23")
        XCTAssertEqual(first["kind"] as? String, "done")
        XCTAssertEqual(first["source"] as? String, "imported")
        XCTAssertEqual(first["id"] as? String, "rec-v1-2026-09-23")
        let leave = try XCTUnwrap(records.first { ($0["day"] as? String) == "2026-10-10" })
        XCTAssertEqual(leave["reason"] as? String, "出遠門")
        let habit = try XCTUnwrap(obj["habit"] as? [String: Any])
        XCTAssertEqual(habit["planted"] as? String, "2026-09-23")
        XCTAssertEqual(habit["id"] as? String, "hab-v1-2026-09-23")
        let reviews = try XCTUnwrap(obj["reviews"] as? [[String: Any]])
        XCTAssertNil(reviews.first?["avg"], "平均不存，用的時候算")
    }

    func testToleratesMissingKeysAndNulls() throws {
        let s = try JSONDecoder().decode(AppState.self, from: Data("{\"logs\":{}}".utf8))
        XCTAssertNil(s.habit)
        XCTAssertEqual(s.settings.leave, 2)
        let t = try JSONDecoder().decode(AppState.self, from: Data(
            "{\"v\":1,\"habit\":null,\"logs\":{\"2026-11-01\":{\"t\":\"done\"},\"bad\":{\"t\":\"done\"}},\"pressure\":null,\"travel\":true}".utf8))
        XCTAssertNil(t.pressure)
        XCTAssertEqual(t.records.count, 1, "不合法的日期 key 要丟掉")
        XCTAssertTrue(t.travel)
    }
}

// MARK: - 動作

@MainActor
final class StoreTests: XCTestCase {
    private func makeStore(backupDir: URL? = nil) -> Store {
        Store(now: { localDate(2026, 11, 7, 12, 0) }, fileURL: nil, backupDir: backupDir)
    }

    func testDigWritesBackupFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shuji-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = makeStore(backupDir: dir)
        s.state = AppState.demo(today: T)
        s.dig()
        let url = dir.appendingPathComponent("薯記備份-挖地瓜-2026-11-07.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let saved = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: url))
        XCTAssertEqual(saved.logs.count, 38, "備份是挖之前的狀態")
        XCTAssertEqual(saved.habit?.floor, "打開檔案寫一句")
        XCTAssertEqual(s.state.records.count, 38, "v2 挖地瓜不清紀錄")
    }

    func testImportMigratesObstacle() {
        let s = makeStore()
        let json = "{\"habit\":{\"floor\":\"讀一頁書\",\"trigger\":\"刷完牙\",\"obstacle\":\"出門的話在車上讀\",\"planted\":\"2026-11-01\"},\"logs\":{}}"
        XCTAssertTrue(s.importJSON(json))
        XCTAssertEqual(s.state.habit?.backup, "出門的話在車上讀")
    }

    func testTodayAndOffset() {
        let s = makeStore()
        XCTAssertEqual(s.today, T)
        s.advance(days: 1)
        XCTAssertEqual(s.today, T.adding(1))
        s.resetOffset()
        XCTAssertEqual(s.today, T)
    }

    func testPlantThenLog() {
        let s = makeStore()
        s.addQueue("讀一頁書")
        s.plant(floor: "讀一頁書", trigger: "刷完牙")
        XCTAssertEqual(s.state.habit?.planted, T)
        XCTAssertEqual(s.state.queue, [], "種下去的那個要從排隊裡拿掉")
        XCTAssertFalse(s.logToday(), "第一節不是回來")
        XCTAssertEqual(s.state.log(on: T)?.t, .done)
        XCTAssertTrue(s.vineGrow)
        let before = s.state
        s.logToday()
        XCTAssertEqual(s.state, before, "同一天記兩次不會變")
    }

    func testReturnFlower() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.state.drop("2026-11-06")
        XCTAssertTrue(s.logToday(), "昨天沒紀錄，今天這一節是回來")
    }

    func testBackfillYesterday() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.state.drop("2026-11-06")
        XCTAssertTrue(s.canBackfillYesterday)
        s.backfillYesterday()
        XCTAssertEqual(s.state.log(on: T.adding(-1))?.t, .done)
        XCTAssertFalse(s.canBackfillYesterday)
        XCTAssertFalse(s.vineGrow)
    }

    func testLeaveLimitAndUndo() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.leaveToday(reason: "發燒")
        XCTAssertEqual(s.state.log(on: T)?.t, .leave)
        XCTAssertEqual(s.lastLeaveReason, "發燒")
        s.undoToday()
        XCTAssertNil(s.state.log(on: T))
        s.updateSettings { $0.leave = 0 }
        s.leaveToday(reason: " 旅行 ")
        XCTAssertEqual(s.state.log(on: T)?.reason, "旅行", "沒有每月次數限制")
        s.undoToday()
        s.skip(day: T, reason: "")
        XCTAssertEqual(s.state.log(on: T)?.t, .leave, "可以不選理由")
    }

    func testSkipReasons() throws {
        let s = makeStore()
        XCTAssertEqual(s.state.settings.skipReasons, ["旅行", "生病", "太累", "太忙"])
        XCTAssertFalse(s.addSkipReason("  "))
        XCTAssertFalse(s.addSkipReason("旅行"), "不重複")
        XCTAssertTrue(s.addSkipReason("一二三四五六七八九"))
        XCTAssertEqual(s.state.settings.skipReasons.last, "一二三四五六七八")
        for r in ["甲", "乙", "丙"] { XCTAssertTrue(s.addSkipReason(r)) }
        XCTAssertFalse(s.addSkipReason("丁"), "最多 8 個")
        s.removeSkipReason("生病")
        XCTAssertEqual(s.state.settings.skipReasons.count, 7)

        let back = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(s.state))
        XCTAssertEqual(back.settings, s.state.settings, "存檔讀得回來")
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"leave":1}"#.utf8))
        XCTAssertEqual(old.skipReasons, Settings.defaultSkipReasons, "舊檔沒有這一欄")
        let odd = try JSONDecoder().decode(Settings.self, from: Data(#"{"skipReasons":3}"#.utf8))
        XCTAssertEqual(odd.skipReasons, Settings.defaultSkipReasons, "形狀不對就用預設")
        let dup = try JSONDecoder().decode(Settings.self, from: Data(#"{"skipReasons":["累","累",""]}"#.utf8))
        XCTAssertEqual(dup.skipReasons, ["累"])
    }

    /// 月曆點一天：今天和昨天改得到，更早的看得到、改不到
    func testEditDayFromCalendar() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        let y = T.adding(-1), old = T.adding(-2)
        XCTAssertTrue(s.canEdit(day: T))
        XCTAssertTrue(s.canEdit(day: y))
        XCTAssertFalse(s.canEdit(day: old))
        XCTAssertFalse(s.canEdit(day: T.adding(1)))

        s.undo(day: old)
        XCTAssertNotNil(s.state.log(on: old), "前天不能改")
        s.undo(day: y)
        XCTAssertNil(s.state.log(on: y))
        s.skip(day: y, reason: "生病")
        XCTAssertEqual(s.state.log(on: y), DayLog.leave("生病"))
        XCTAssertEqual(s.state.records.last?.source, .backfill)
        s.backfill(day: y)
        XCTAssertEqual(s.state.log(on: y)?.t, .leave, "已經有一筆就不補")
        s.undo(day: y)
        s.backfill(day: y)
        XCTAssertEqual(s.state.log(on: y)?.t, .done)
        s.state.drop(old.string)
        s.backfill(day: old)
        XCTAssertNil(s.state.log(on: old), "補記只能補昨天")

        s.startLetGo()
        XCTAssertFalse(s.canEdit(day: T), "放手中不改")

        let n = makeStore()
        n.plant(floor: "讀一頁書", trigger: "刷完牙")
        XCTAssertFalse(n.canEdit(day: y), "種下去之前")
    }

    /// 旅行中拿掉了：舊存檔還停在旅行中，打開就補一筆結束
    func testOpenEndsTravel() throws {
        var d = AppState.demo(today: T)
        d.mark(.travelOn, T.adding(-3))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shuji-travel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(d).write(to: url)
        let s = Store(now: { localDate(2026, 11, 7, 12, 0) }, fileURL: url, backupDir: dir)
        XCTAssertFalse(s.state.travel)
        XCTAssertEqual(s.state.travelEndedOn, T)
        let again = Store(now: { localDate(2026, 11, 8, 12, 0) }, fileURL: url, backupDir: dir)
        XCTAssertEqual(again.state.marks.filter { $0.kind == .travelOff }.count, 1, "存起來了，不會再補一筆")
    }

    func testLetGoFlow() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.startLetGo()
        XCTAssertEqual(s.state.letgo?.prior, 13)
        XCTAssertEqual(s.state.letgoDaysLeft(today: T), 14)
        XCTAssertFalse(s.showLetGoEnd)
        s.advance(days: 13)
        XCTAssertFalse(s.showLetGoEnd, "第 13 天還沒到")
        s.advance(days: 1)
        XCTAssertTrue(s.showLetGoEnd, "兩週就是兩週，沒有提早結束")
        s.finishLetGo(days: 11)
        XCTAssertNil(s.state.letgo)
        XCTAssertEqual(s.state.letgoResult?.pass, true, "11 >= 13 - 2 算過")
        XCTAssertEqual(s.state.letgoResult?.start, T)
        XCTAssertEqual(s.state.letgoResult?.end, T.adding(14))
        XCTAssertEqual(s.page, 1)
        XCTAssertTrue(s.state.signals(today: s.today).s3)
        s.resetOffset()

        let f = makeStore()
        f.state = AppState.demo(today: T)
        f.startLetGo()
        f.advance(days: 14)
        f.finishLetGo(days: 10)
        XCTAssertEqual(f.state.letgoResult?.pass, false, "10 < 11 不算過")
    }

    func testShortcutReplies() {
        let s = makeStore()
        XCTAssertEqual(s.shortcutLog(), "還沒種東西。先打開薯記種一個。")
        s.plant(floor: "打開檔案寫一句", trigger: "起床喝完第一杯水")
        XCTAssertEqual(s.shortcutLog(), "記好了。打開檔案寫一句，第 1 節。")
        XCTAssertEqual(s.state.log(on: T)?.t, .done)
        XCTAssertEqual(s.state.activeRecords.last?.source, .shortcut, "捷徑記的標成 shortcut")
        XCTAssertEqual(s.shortcutLog(), "今天已經記過了。", "同一天不會記兩次")
        XCTAssertEqual(s.state.stats(today: T).nodes, 1)
        s.undoToday()
        s.leaveToday(reason: "出遠門")
        XCTAssertEqual(s.shortcutLog(), "今天跳過了。")
        s.undoToday()
        s.startLetGo()
        XCTAssertEqual(s.shortcutLog(), "放手測試中，照常做就好，不用記。")
        XCTAssertNil(s.state.log(on: T))
        s.state = AppState.demo(today: T)
        s.state.drop(T.adding(-1).string)
        s.state.drop(T.adding(-2).string)
        XCTAssertTrue(s.shortcutLog().hasPrefix("回來了。"), "漏兩天後再記是回來")
    }

    func testWidgetSnapshotFollowsMainScreenOrder() {
        var d = AppState()
        XCTAssertEqual(WidgetSnapshot.make(state: d, today: T).status, .empty)
        d = AppState.demo(today: T)
        let none = WidgetSnapshot.make(state: d, today: T)
        XCTAssertEqual(none.status, .none)
        XCTAssertEqual(none.nodes, 37)
        XCTAssertEqual(none.trigger, "起床喝完第一杯水")
        XCTAssertEqual(none.floor, "打開檔案寫一句")
        XCTAssertEqual(none.day, T.string)
        d.put(T.string, .done)
        XCTAssertEqual(WidgetSnapshot.make(state: d, today: T).status, .done)
        XCTAssertEqual(WidgetSnapshot.make(state: d, today: T).nodes, 38)
        d.put(T.string, .leave("出遠門"))
        XCTAssertEqual(WidgetSnapshot.make(state: d, today: T).status, .leave)
        var lg = d
        lg.mark(.letgoStart, T, prior: 10)
        XCTAssertEqual(WidgetSnapshot.make(state: lg, today: T).status, .letgo, "放手測試優先於今天的紀錄")
        d.mark(.travelOn, T)
        XCTAssertEqual(WidgetSnapshot.make(state: d, today: T).floor, "在手機上寫三行", "旅行中顯示旅行版最小一步")
        d.mark(.travelOff, T)
        d.justDug = Potato(floor: "x", trigger: "y", nodes: 1, ret: 0, days: 1, planted: T, dug: T)
        XCTAssertEqual(WidgetSnapshot.make(state: d, today: T).status, .dug, "剛挖出來優先於一切")
    }

    func testWidgetSnapshotResetsAfterDayChange() {
        let snap = WidgetSnapshot(trigger: "a", floor: "b", nodes: 3, status: .done, day: T.string, updated: Date())
        XCTAssertEqual(snap.display(today: T), .done)
        XCTAssertEqual(snap.display(today: T.adding(1)), .none, "換日後記了要變回還沒記")
        let leave = WidgetSnapshot(trigger: "a", floor: "b", nodes: 3, status: .leave, day: T.string, updated: Date())
        XCTAssertEqual(leave.display(today: T.adding(1)), .none)
        let letgo = WidgetSnapshot(trigger: "a", floor: "b", nodes: 3, status: .letgo, day: T.string, updated: Date())
        XCTAssertEqual(letgo.display(today: T.adding(1)), .letgo, "放手測試中換日也不變")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shuji-widget-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("widget.json")
        XCTAssertTrue(snap.write(to: url))
        XCTAssertEqual(WidgetSnapshot.read(from: url), snap)
    }

    func testDigAndPlantNext() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.dig()
        XCTAssertEqual(s.state.basket.count, 2)
        XCTAssertEqual(s.state.basket[0].nodes, 37)
        XCTAssertEqual(s.state.basket[0].ret, 5)
        XCTAssertEqual(s.state.basket[0].days, 46)
        XCTAssertEqual(s.state.basket[0].dug, T)
        XCTAssertNotNil(s.state.justDug)
        XCTAssertEqual(s.state.records.count, 38, "紀錄全部留著")
        XCTAssertEqual(s.state.reviews.count, 7, "開始四問全部留著")
        XCTAssertEqual(s.state.basket[0].habit, "hab-v1-2026-09-23", "地瓜指回原始紀錄")
        XCTAssertEqual(s.state.pastHabits.map(\.id), ["hab-v1-2026-09-23"])
        XCTAssertNotNil(s.state.habit, "挖完還沒按「種下一個」之前習慣還在")
        s.plantNext()
        XCTAssertNil(s.state.habit)
        XCTAssertNil(s.state.justDug)
        XCTAssertTrue(s.state.logs.isEmpty, "沒有目前的習慣，畫面上就沒有紀錄")
        XCTAssertEqual(s.state.records.count, 38)
        s.plant(floor: "讀一頁書", trigger: "刷完牙")
        XCTAssertEqual(s.state.stats(today: T).nodes, 0, "新的習慣從 0 節開始，舊的紀錄不算進來")
        XCTAssertTrue(s.state.weekly.isEmpty)
    }

    func testReviewAndPressure() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.recordReview(scores: [5, 6, 7, 6])
        XCTAssertEqual(s.state.weekly.count, 8)
        // 示範資料最後一次四問在未來（原型的寫法），線照日期排，所以看最後加進去的那一筆
        XCTAssertEqual(s.state.reviews.last?.avg, 6)
        XCTAssertEqual(s.state.reviews.last?.date, T)
        XCTAssertEqual(s.state.reviews.last?.habit, s.state.habit?.id)
        XCTAssertNotNil(s.state.reviews.last?.at, "新的開始四問存世界標準時間")
        s.setPressure(true)
        XCTAssertEqual(s.state.pressure, true)
    }

    func testImportRequiresLogs() {
        let s = makeStore()
        XCTAssertFalse(s.importJSON("{\"habit\":null}"))
        XCTAssertFalse(s.importJSON("not json"))
        XCTAssertTrue(s.importJSON(prototypeBackup))
        XCTAssertEqual(s.state.habit?.floor, "打開檔案寫一句")
        XCTAssertEqual(s.exportJSON().isEmpty, false)
    }

    func testTravelEndRemembersDay() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.setTravel(true)
        XCTAssertTrue(s.state.travel)
        s.setTravel(false)
        XCTAssertEqual(s.state.travelEndedOn, T)
    }

    func testWipe() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.wipe()
        XCTAssertEqual(s.state, AppState())
    }
}

// MARK: - AI 任務的輸入

final class AIInputTests: XCTestCase {
    func testGapAndDiagnoseInput() throws {
        var d = AppState.demo(today: T)
        XCTAssertEqual(d.gapDays(today: T), 1)
        XCTAssertEqual(d.gapDays(today: T.adding(18)), 19)
        d.keepOnly([:])
        XCTAssertEqual(d.gapDays(today: T), 45, "沒記過就從種下去那天算")
        let input = try XCTUnwrap(d.diagnoseInput(today: T, q1: "有時候沒有", q2: "不會", q3: "想睡"))
        XCTAssertEqual(input.answers.q3_rival, "想睡")
        XCTAssertEqual(input.trigger, "起床喝完第一杯水")
    }

    func testAuditInputFromDemo() throws {
        let d = AppState.demo(today: T)
        let a = try XCTUnwrap(d.auditInput(today: T, satisfied: "寫了很多", contextChange: ""))
        XCTAssertEqual(a.quarter.done_rate, 37.0 / 45.0, accuracy: 0.0001)
        XCTAssertEqual(a.quarter.leaves, 1)
        XCTAssertEqual(a.quarter.returns, 5)
        XCTAssertEqual(a.quarter.weekly_avg.count, 7)
        XCTAssertEqual(a.why, "把複雜的事想清楚、寫下來")
        XCTAssertEqual(a.user.satisfied, "寫了很多")
    }

    func testWhenAIEntriesShowUp() {
        var d = AppState.demo(today: T)
        XCTAssertFalse(d.obstaclePromptReady(today: T), "已經寫了不順的時候")
        d.habit?.backup = ""
        XCTAssertTrue(d.obstaclePromptReady(today: T))
        XCTAssertFalse(d.auditReady(today: T), "種了 45 天，還不到一季")
        XCTAssertTrue(d.auditReady(today: T.adding(39)))
        var fresh = AppState()
        fresh.habit = Habit(floor: "a", trigger: "b", planted: T.adding(-3))
        XCTAssertFalse(fresh.obstaclePromptReady(today: T), "種下去不到 7 天")
    }

    func testHabitFieldApply() {
        var h = Habit(floor: "a", trigger: "b", planted: T)
        HabitField.obstacle.apply("如果下雨，就在家門口運球", to: &h)
        XCTAssertEqual(h.backup, "如果下雨，就在家門口運球", "障礙版跟備用開關在原生版是同一格")
        HabitField.travelFloor.apply("在手機上寫三行", to: &h)
        XCTAssertEqual(h.travelFloor, "在手機上寫三行")
        HabitField.trigger.apply("刷完牙", to: &h)
        XCTAssertEqual(h.trigger, "刷完牙")
    }

    func testWidgetSnapshotCarriesFullFlag() {
        let d = AppState.demo(today: T)
        XCTAssertEqual(WidgetSnapshot.make(state: d, today: T).full, false)
        XCTAssertEqual(WidgetSnapshot.make(state: d, today: T, full: true).full, true)
    }

    func testOutputsDecodeFromServerShape() throws {
        let json = #"{"type":"ok","layer":4,"field":"obstacle","suggestion":"先坐三個呼吸再去躺","why":"w","closing":"c","category":null,"message":null}"#
        let o = try JSONDecoder().decode(DiagnoseOutput.self, from: Data(json.utf8))
        XCTAssertEqual(o.field, .obstacle)
        let p = #"{"type":"ok","obstacles":[{"if":"早上要趕出門","then":"在捷運上寫三行"}],"backup":null,"travel":{"portable":true,"floor":"在手機上寫三行","alt":""},"note":"","category":null,"message":null}"#
        let ob = try JSONDecoder().decode(ObstacleOutput.self, from: Data(p.utf8))
        XCTAssertEqual(ob.obstacles.first?.if, "早上要趕出門")
        XCTAssertNil(ob.backup)
    }
}
