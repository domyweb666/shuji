import XCTest
@testable import Shuji

private let T = DayKey("2026-11-25")!

private func makeState(planted: DayKey, total: Int?, done: [DayKey]) -> AppState {
    var s = AppState()
    s.habit = Habit(floor: "讀一頁書", trigger: "刷完牙", planted: planted, id: "hab-test", estimatedDays: total)
    s.records = done.map {
        DayRecord(id: "rec-\($0.string)", habit: "hab-test", kind: .done, day: $0, at: nil, tz: nil, source: .hold)
    }
    return s
}

final class HabitEstimateTests: XCTestCase {
    func testDifficultyDays() {
        XCTAssertEqual(HabitDifficulty.easy.days, 60)
        XCTAssertEqual(HabitDifficulty.medium.days, 66)
        XCTAssertEqual(HabitDifficulty.hard.days, 90)
    }

    func testOldHabitHasNoEstimate() {
        let s = makeState(planted: T.adding(-10), total: nil, done: [])
        XCTAssertNil(s.estimateDate(today: T))
        XCTAssertNil(s.estimateProgress(today: T))
        XCTAssertNil(AppState().estimateDate(today: T))
    }

    func testPlantedTodayCountsEveryDay() {
        let s = makeState(planted: T, total: 66, done: [])
        XCTAssertEqual(s.estimateDate(today: T), T.adding(66))
        XCTAssertEqual(s.estimateProgress(today: T)?.done, 0)
        XCTAssertEqual(s.estimateProgress(today: T)?.total, 66)
    }

    func testShortHistoryUsesPlantedDays() {
        // 種了 4 天、記了 2 天：記錄率 0.5，剩 58 天要 116 天
        let s = makeState(planted: T.adding(-4), total: 60, done: [T.adding(-4), T.adding(-2)])
        XCTAssertEqual(s.estimateDate(today: T), T.adding(116))
    }

    func testOnlyLast14DaysCount() {
        // 前面每天都記，最近 14 天記 7 天
        let early = (15...34).map { T.adding(-$0) }
        let late = (1...7).map { T.adding(-$0) }
        let s = makeState(planted: T.adding(-34), total: 60, done: early + late)
        XCTAssertEqual(s.estimateProgress(today: T)?.done, 27)
        XCTAssertEqual(s.estimateDate(today: T), T.adding(66), "剩 33 天 ÷ 0.5")
    }

    func testRateFloorAndRoundingUp() {
        let none = makeState(planted: T.adding(-20), total: 60, done: [])
        XCTAssertEqual(none.estimateDate(today: T), T.adding(150), "最低算 0.4：60 ÷ 0.4")
        // 14 天記 13 天：剩 47 × 14 ÷ 13 = 50.6，進位成 51
        let most = makeState(planted: T.adding(-14), total: 60, done: (1...13).map { T.adding(-$0) })
        XCTAssertEqual(most.estimateDate(today: T), T.adding(51))
    }

    func testTodayDoesNotMoveTheRate() {
        let before = makeState(planted: T.adding(-14), total: 60, done: (1...14).map { T.adding(-$0) })
        XCTAssertEqual(before.estimateDate(today: T), T.adding(46))
        let after = makeState(planted: T.adding(-14), total: 60, done: (0...14).map { T.adding(-$0) })
        XCTAssertEqual(after.estimateDate(today: T), T.adding(45))
    }

    func testFinishedHasNoDate() {
        let s = makeState(planted: T.adding(-80), total: 60, done: (1...61).map { T.adding(-$0) })
        XCTAssertNil(s.estimateDate(today: T))
    }

    func testSkippedAndUndoneDaysDoNotCount() {
        var s = makeState(planted: T.adding(-2), total: 60, done: [T.adding(-1), T.adding(-2)])
        s.records[0].kind = .leave
        s.records[1].deletedAt = "2026-11-24T00:00:00Z"
        XCTAssertEqual(s.estimateProgress(today: T)?.done, 0)
    }

    func testEstimatedDaysSurvivesCodingAndOldFiles() throws {
        let h = Habit(floor: "讀一頁書", trigger: "刷完牙", planted: T, id: "a", estimatedDays: 66)
        XCTAssertEqual(try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(h)).estimatedDays, 66)
        let old = #"{"floor":"讀一頁書","trigger":"刷完牙","planted":"2026-11-01"}"#
        XCTAssertNil(try JSONDecoder().decode(Habit.self, from: Data(old.utf8)).estimatedDays)
    }
}

final class PlanOutputTests: XCTestCase {
    func testDecodesOptions() throws {
        let json = #"{"type":"options","lead":"先從這個開始","options":["換上球鞋","走到門口","拿起水壺"],"difficulty":null,"category":null,"message":null}"#
        let o = try JSONDecoder().decode(PlanOutput.self, from: Data(json.utf8))
        XCTAssertEqual(o.options.count, 3)
        XCTAssertNil(o.difficulty)
    }

    func testDecodesEstimateAndUnknownDifficulty() throws {
        let json = #"{"type":"estimate","lead":"","options":[],"difficulty":"hard","category":null,"message":null}"#
        XCTAssertEqual(try JSONDecoder().decode(PlanOutput.self, from: Data(json.utf8)).difficulty, .hard)
        let odd = #"{"type":"estimate","difficulty":"extreme"}"#
        XCTAssertNil(try JSONDecoder().decode(PlanOutput.self, from: Data(odd.utf8)).difficulty)
    }

    func testInputMatchesServerFields() throws {
        let input = PlanInput(step: .trigger, goal: "每天運動", floor: "換上球鞋", trigger: "", exclude: ["洗完臉"])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["step", "goal", "floor", "trigger", "rival", "exclude"])
        XCTAssertEqual(obj["step"] as? String, "trigger")
    }
}

@MainActor
final class TalkModelTests: XCTestCase {
    func testOptionsThenMoreKeepsWhatWasSeen() {
        let m = TalkModel()
        m.arrived(PlanOutput(type: "options", lead: "a", options: ["一", "二", " 二 ", "三", "四"]), at: .floor)
        XCTAssertEqual(m.step, .floor)
        XCTAssertEqual(m.floorOffer.options, ["一", "二", "三"])
        m.arrived(PlanOutput(type: "options", lead: "b", options: ["五", "六", "七"]), at: .floor)
        XCTAssertEqual(m.floorOffer.options, ["五", "六", "七"])
        XCTAssertEqual(m.floorOffer.seen, ["一", "二", "三", "五", "六", "七"])
    }

    func testEstimateFillsDaysByTable() {
        let m = TalkModel()
        m.arrived(PlanOutput(type: "estimate", difficulty: .hard), at: .plan)
        XCTAssertEqual(m.days, HabitDifficulty.hard.days)
        XCTAssertEqual(m.step, .plan)
        XCTAssertTrue(m.back())
        XCTAssertEqual(m.step, .reward)
    }

    /// 對手、擋對手、犒賞：三選一照常收；回上一步照走過的路回去
    func testRivalBlockRewardSteps() {
        let m = TalkModel()
        m.arrived(PlanOutput(type: "options", options: ["滑手機", "躺沙發", "開電視"]), at: .rival)
        XCTAssertEqual(m.step, .rival)
        XCTAssertTrue(m.step.skippable)
        XCTAssertEqual(m.offer.options, ["滑手機", "躺沙發", "開電視"])
        m.arrived(PlanOutput(type: "options", options: ["手機放客廳", "前一晚擺好", "登出"]), at: .block)
        m.arrived(PlanOutput(type: "options", options: ["泡茶", "聽歌", "看窗外"]), at: .reward)
        XCTAssertEqual(m.offer.options, ["泡茶", "聽歌", "看窗外"])
        XCTAssertTrue(m.back())
        XCTAssertEqual(m.step, .rival, "沒選對手，擋對手沒問過，直接回對手")
        XCTAssertFalse(TalkModel.Step.trigger.skippable)
        XCTAssertFalse(TalkModel.Step.plan.picks)
        XCTAssertEqual(TalkModel.Step.reward.next, .plan)
    }

    /// 每一步只送用得到的：對手不帶 rival，擋對手、犒賞才帶
    func testInputCarriesOnlyWhatTheStepNeeds() {
        let i = { (t: TalkModel.Step) in
            TalkModel.input(for: t, goal: "練吉他", floor: "拿起吉他", trigger: "下班進家門", rival: "滑手機", seen: ["甲"])
        }
        XCTAssertEqual(i(.floor).floor, "")
        XCTAssertEqual(i(.floor).trigger, "")
        XCTAssertEqual(i(.trigger).trigger, "")
        XCTAssertEqual(i(.rival).step, .rival)
        XCTAssertEqual(i(.rival).trigger, "下班進家門")
        XCTAssertEqual(i(.rival).rival, "")
        XCTAssertEqual(i(.block).rival, "滑手機")
        XCTAssertEqual(i(.reward).rival, "滑手機")
        XCTAssertEqual(i(.reward).exclude, ["甲"])
        XCTAssertEqual(i(.plan).step, .estimate)
        XCTAssertEqual(i(.plan).exclude, [])
    }

    func testOffTopicTwiceHidesInputUntilAsked() {
        let m = TalkModel()
        XCTAssertTrue(m.showsInput)
        m.arrived(PlanOutput(type: "off_topic", lead: "模型的字", options: ["不要顯示"]), at: .floor)
        XCTAssertEqual(m.step, .goal)
        XCTAssertNotNil(m.offTopic)
        XCTAssertTrue(m.showsInput)
        XCTAssertTrue(m.floorOffer.options.isEmpty, "離題時模型的字全部丟掉")
        m.arrived(PlanOutput(type: "off_topic"), at: .floor)
        XCTAssertFalse(m.showsInput)
        m.typeOwn()
        XCTAssertTrue(m.showsInput)
        m.arrived(PlanOutput(type: "options", options: ["一"]), at: .floor)
        XCTAssertEqual(m.offTopicCount, 0, "連續的才算")
    }

    func testBackGoesToGoalAndStopsThere() {
        let m = TalkModel()
        m.arrived(PlanOutput(type: "options", options: ["一", "二", "三"]), at: .floor)
        m.typeOwn()
        XCTAssertTrue(m.back(), "先收起輸入框")
        XCTAssertEqual(m.step, .floor)
        XCTAssertTrue(m.back())
        XCTAssertEqual(m.step, .goal)
        XCTAssertFalse(m.back())
    }

    func testNegativeFloorCannotBeSent() {
        let m = TalkModel()
        m.ownFloor()
        m.draft = "不滑手機"
        XCTAssertFalse(m.canSend)
        m.draft = "把手機放到客廳"
        XCTAssertTrue(m.canSend)
    }

    func testClipCountsLikeTheServer() {
        XCTAssertEqual(TalkModel.clip("  讀書 ", 60), "讀書")
        XCTAssertLessThanOrEqual(TalkModel.clip(String(repeating: "🍠", count: 60), 60).utf16.count, 60)
    }
}

@MainActor
final class ReplanTests: XCTestCase {
    private func makeStore() -> Store {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 25; c.hour = 12
        let now = Calendar.current.date(from: c)!
        return Store(now: { now }, fileURL: nil, backupDir: nil)
    }

    /// 種下去時三件跟著存進習慣；舊存檔沒有這三欄讀成空字串
    func testHabitKeepsRivalBlockReward() throws {
        let s = makeStore()
        s.plant(floor: "拿起吉他", trigger: "下班進家門", estimatedDays: 66, rival: "滑手機", block: "手機放客廳", reward: "泡茶")
        XCTAssertEqual(s.state.habit?.rival, "滑手機")
        XCTAssertEqual(s.state.habit?.block, "手機放客廳")
        XCTAssertEqual(s.state.habit?.reward, "泡茶")
        let old = #"{"id":"h","floor":"a","trigger":"b"}"#
        let h = try JSONDecoder().decode(Habit.self, from: Data(old.utf8))
        XCTAssertEqual(h.reward, "")
        let again = try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(s.state.habit!))
        XCTAssertEqual(again.reward, "泡茶")
    }

    func testPlantKeepsEstimate() {
        let s = makeStore()
        s.plant(floor: "讀一頁書", trigger: "刷完牙", estimatedDays: 66)
        XCTAssertEqual(s.state.habit?.estimatedDays, 66)
        XCTAssertEqual(s.state.estimateDate(today: s.today), s.today.adding(66))
        s.plant(floor: "喝一口水", trigger: "刷完牙")
        XCTAssertNil(s.state.habit?.estimatedDays)
    }

    func testReplanPutsTheOldOneAwayAndStopsItsTests() {
        let s = makeStore()
        s.state = AppState.demo(today: s.today)
        let old = s.state.habit!.id
        let records = s.state.records.count
        s.startLetGo()
        s.state.trials = [Trial(id: "try-1", habit: old, observation: "obs-1", kind: .weekend, group: "weekend",
                                change: "none", start: s.today.adding(-3), end: s.today.adding(11), status: .running,
                                before: .zero, after: nil, conclusion: nil, concludedAt: nil)]
        s.plant(floor: "喝一口水", trigger: "刷完牙", estimatedDays: 60)
        XCTAssertEqual(s.state.pastHabits.map(\.id), [old])
        XCTAssertNotEqual(s.state.habit?.id, old)
        XCTAssertEqual(s.state.records.count, records, "紀錄留著")
        XCTAssertNil(s.state.letgo)
        XCTAssertEqual(s.state.marks.last?.kind, .letgoEnd)
        XCTAssertEqual(s.state.marks.last?.habit, old)
        XCTAssertNil(s.state.marks.last?.pass, "只是收掉，沒有判定")
        XCTAssertEqual(s.state.trials.first?.status, .stopped)
    }

    /// QC-0011：換習慣之後，今天的藤要馬上是空的；舊的收在「種到一半的」
    func testReplanClearsTheSceneAndKeepsTheOldOne() {
        let s = makeStore()
        s.plant(floor: "坐到鋪墊上", trigger: "洗完臉")
        let old = s.state.habit!.id
        s.logToday()
        s.vineGrow = true
        s.plant(floor: "握起啞鈴做一下", trigger: "剛坐上椅子")
        XCTAssertEqual(s.state.doneKeys, [], "新的習慣一節都還沒有")
        XCTAssertNil(s.state.log(on: s.today))
        XCTAssertFalse(s.vineGrow)
        XCTAssertEqual(s.state.unfinished.map(\.id), [old])
        XCTAssertEqual(s.state.unfinished.first?.done, 1)
        XCTAssertEqual(s.state.unfinished.first?.end, s.today)
    }

    /// 長好挖出來的在竹籃，一天都沒記過的不算
    func testUnfinishedSkipsDugAndEmpty() {
        let s = makeStore()
        s.state = AppState.demo(today: s.today)
        s.dig()
        s.plantNext()
        s.plant(floor: "讀一頁書", trigger: "刷完牙")
        s.plant(floor: "喝一口水", trigger: "刷完牙")
        XCTAssertEqual(s.state.pastHabits.count, 2)
        XCTAssertEqual(s.state.unfinished, [])
    }

    /// 種到一半的排進排隊：排最前面、不重複排
    func testQueueUnfinishedGoesFirstOnce() {
        let s = makeStore()
        s.plant(floor: "坐到鋪墊上", trigger: "洗完臉")
        s.logToday()
        s.plant(floor: "握起啞鈴做一下", trigger: "剛坐上椅子")
        s.addQueue("喝一口水")
        let u = s.state.unfinished.first!
        s.queueUnfinished(u)
        s.queueUnfinished(u)
        XCTAssertEqual(s.state.queue, ["坐到鋪墊上", "喝一口水"])
        XCTAssertEqual(s.state.habit?.floor, "握起啞鈴做一下", "不搶正在種的")
    }

    /// 種回來：同一句同一個時機重新種，換掉的那個收進種到一半的，紀錄都留著
    func testReplantUnfinishedSwapsBack() {
        let s = makeStore()
        s.plant(floor: "坐到鋪墊上", trigger: "洗完臉")
        let first = s.state.habit!.id
        s.logToday()
        s.plant(floor: "握起啞鈴做一下", trigger: "剛坐上椅子")
        let second = s.state.habit!.id
        s.logToday()
        let records = s.state.records.count
        s.queueUnfinished(s.state.unfinished.first!)
        s.replantUnfinished(s.state.unfinished.first!)
        XCTAssertEqual(s.state.habit?.floor, "坐到鋪墊上")
        XCTAssertEqual(s.state.habit?.trigger, "洗完臉")
        XCTAssertNotEqual(s.state.habit?.id, first, "新的一輪，藤從頭長")
        XCTAssertEqual(s.state.records.count, records, "紀錄留著")
        XCTAssertEqual(s.state.queue, [], "種了就從排隊拿掉")
        XCTAssertEqual(s.state.unfinished.map(\.id), [second], "同一句種回來了就不列")
        XCTAssertEqual(s.page, 1)
    }

    /// 回來卡後面只問一次「下次怎麼辦」；想過了就不問
    func testBackupIsOfferedOnce() {
        let s = makeStore()
        XCTAssertFalse(s.shouldOfferBackup)
        s.plant(floor: "讀一頁書", trigger: "刷完牙")
        XCTAssertTrue(s.shouldOfferBackup)
        s.markBackupOffered()
        XCTAssertFalse(s.shouldOfferBackup)
        s.plant(floor: "喝一口水", trigger: "刷完牙")
        XCTAssertTrue(s.shouldOfferBackup)
        s.updateHabit { $0.backup = "晚上補一口" }
        XCTAssertFalse(s.shouldOfferBackup)
    }

    func testDueLineHasTheYear() {
        XCTAssertTrue(TalkModel.dueLine(today: DayKey("2026-11-26")!, days: 90).contains("2027 年 2 月 24 日"))
    }

    /// 進度條：答完一題才走一格（共七步）
    @MainActor
    func testProgressCountsAnswered() {
        let m = TalkModel()
        XCTAssertEqual(m.answered, 0)
        m.arrived(PlanOutput(type: "options", lead: "", options: ["坐到鋪墊上"]), at: .floor)
        XCTAssertEqual(m.answered, 1)
        m.arrived(PlanOutput(type: "options", lead: "", options: ["洗完臉"]), at: .trigger)
        XCTAssertEqual(m.answered, 2)
        m.arrived(PlanOutput(type: "estimate", difficulty: .hard), at: .plan)
        XCTAssertEqual(m.answered, 6, "中間還有對手、擋對手、犒賞三步")
    }

    func testReplanWhileJustDug() {
        let s = makeStore()
        s.state = AppState.demo(today: s.today)
        s.dig()
        s.plant(floor: "喝一口水", trigger: "刷完牙")
        XCTAssertNil(s.state.justDug)
        XCTAssertEqual(s.state.pastHabits.count, 1)
    }

    func testQueueWordIsRemovedOnce() {
        let s = makeStore()
        s.addQueue("坐上蒲團")
        s.removeQueue("沒有這個")
        XCTAssertEqual(s.state.queue, ["坐上蒲團"])
        s.removeQueue("坐上蒲團")
        XCTAssertEqual(s.state.queue, [])
    }
}
