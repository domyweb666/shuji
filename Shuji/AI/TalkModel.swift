import Foundation
import Observation

/// 跟地瓜對答的狀態：七步，一步問一次 AI（任務 8）。畫面在 TalkView。
/// 時機之後多三步：對手、擋對手、犒賞（多米 2026-11-26 加），都可以按「先不用」跳過。
/// 伺服器不存對話；選過的、給過的選項都只在這裡，換頁就沒了。
@MainActor
@Observable
final class TalkModel {
    enum Step: Int {
        case goal = 1, floor, trigger, rival, block, reward, plan

        /// 這一步是從 AI 給的三個裡挑一個
        var picks: Bool { self != .goal && self != .plan }
        /// 可以按「先不用」跳過
        var skippable: Bool { self == .rival || self == .block || self == .reward }
        /// 下一步
        var next: Step { Step(rawValue: rawValue + 1) ?? .plan }
    }

    enum Phase: Equatable {
        case ready
        case waiting
        case failed(String)
        case unfit(String)
    }

    /// 這一步 AI 給的：一句話、三個選項、給過的全部（換一批時不要再給）
    struct Offer: Equatable {
        var lead = ""
        var options: [String] = []
        var seen: [String] = []
    }

    static let presets = ["早點睡", "多動一點", "看點書"]
    /// 連續離題幾次就先收起輸入框
    static let offTopicLimit = 2
    private static let pickSteps: [Step] = [.floor, .trigger, .rival, .block, .reward]

    private(set) var step: Step = .goal
    private(set) var phase: Phase = .ready
    private(set) var goal = ""
    private(set) var floor = ""
    private(set) var trigger = ""
    /// 那個時機最會跟習慣搶的事；跳過是空字串
    private(set) var rival = ""
    /// 讓對手變難、或讓最小一步變簡單的事
    private(set) var block = ""
    /// 做完馬上給自己的小犒賞
    private(set) var reward = ""
    private(set) var days: Int?
    /// 每一步 AI 給的三個
    private(set) var offers: [Step: Offer] = [:]
    /// 剛剛離題的那一句
    private(set) var offTopic: String?
    private(set) var offTopicCount = 0

    var draft = ""
    /// 按了「自己打」
    var typing = false
    /// 第一次送去伺服器之前先問（送到自己的電腦不問）
    var needsConsent = false

    @ObservationIgnored private var pending: Step?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 第幾次問。取消、重來之後，晚到的結果對不上就丟掉
    @ObservationIgnored private var round = 0

    // MARK: 畫面要的

    var floorOffer: Offer { offers[.floor] ?? Offer() }
    var triggerOffer: Offer { offers[.trigger] ?? Offer() }
    var offer: Offer { offers[step == .goal ? .floor : step] ?? Offer() }

    var draftValue: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var draftLimit: Int { TalkModel.limit(step) }

    /// 最小一步不能是「不做某件事」
    var draftNegative: Bool { step == .floor && Wording.isNegative(draftValue) }

    var canSend: Bool { !draftValue.isEmpty && !draftNegative }

    var showsInput: Bool {
        switch step {
        case .goal: return typing || offTopicCount < TalkModel.offTopicLimit
        case .plan: return false
        default: return typing || offer.options.isEmpty
        }
    }

    /// 答好幾題了：進度條照這個走。還在問的、還在想的那題不算（QC-0011）
    var answered: Int { step.rawValue - 1 }

    /// 種下去那頁的小字：照這樣做大概哪一天，連年份
    static func dueLine(today: DayKey, days: Int) -> String {
        let d = today.adding(days)
        return "順利的話，大約 \(d.year) 年 \(d.month) 月 \(d.day) 日養成。快慢每個人不同，我每週會跟你說走到哪。"
    }

    /// 上一步選的那句，靠右的泡泡
    var bubble: String? {
        let s: String
        switch step {
        case .goal: s = offTopic ?? ""
        case .floor: s = goal
        case .trigger: s = floor
        case .rival: s = trigger
        case .block: s = rival
        case .reward: s = [block, rival, trigger].first { !$0.isEmpty } ?? ""
        case .plan: s = reward.isEmpty ? trigger : reward
        }
        return s.isEmpty ? nil : s
    }

    // MARK: 使用者的動作

    func submitGoal(_ text: String) {
        let v = TalkModel.clip(text, PlanInput.goalLimit)
        guard !v.isEmpty, phase != .waiting else { return }
        if v == goal, !floorOffer.options.isEmpty {
            go(.floor)
            return
        }
        goal = v
        clearAfter(.goal)
        request(.floor)
    }

    func pickFloor(_ text: String) { choose(text, at: .floor) }

    func pickTrigger(_ text: String) { choose(text, at: .trigger) }

    /// 目前這一步挑了或打了這句
    func pick(_ text: String) { choose(text, at: step) }

    /// 挑了這一步（或自己打的），接著問下一步。跟上次挑的一樣、下一步也問過了，就直接過去不再問
    func choose(_ text: String, at s: Step) {
        guard s.picks else { return }
        let v = TalkModel.clip(text, TalkModel.limit(s))
        guard !v.isEmpty, phase != .waiting else { return }
        let target = s.next
        let asked = target == .plan ? days != nil : !(offers[target]?.options.isEmpty ?? true)
        if v == value(s), asked {
            go(target)
            return
        }
        set(s, v)
        clearAfter(s)
        request(target)
    }

    /// 對手、擋對手、犒賞按「先不用」：這一步空著往下走。對手不用，擋對手也一起跳過
    func skip() {
        guard phase == .ready, step.skippable else { return }
        let s = step
        set(s, "")
        clearAfter(s)
        request(s == .rival ? .reward : s.next)
    }

    /// 換一批
    func more() {
        guard phase == .ready, step.picks else { return }
        request(step)
    }

    func retry() {
        guard phase != .waiting else { return }
        request(step)
    }

    func typeOwn() {
        draft = ""
        typing = true
    }

    /// 排隊不等 AI：直接打一個最小的
    func ownFloor() {
        stop()
        phase = .ready
        go(.floor)
        typing = true
    }

    /// 回上一步。沒有上一步可以回是 false
    @discardableResult
    func back() -> Bool {
        stop()
        let middle = step.picks
        if phase != .ready {
            phase = .ready
            // 換一批的時候回來，還是看得到原本那批
            if middle, !offer.options.isEmpty { return true }
        } else if typing, middle, !offer.options.isEmpty {
            go(step)
            return true
        }
        switch step {
        case .goal:
            return false
        case .floor:
            go(.goal)
            offTopic = nil
            draft = goal
            typing = true
        case .trigger:
            go(.floor)
        case .rival:
            go(.trigger)
        case .block:
            go(.rival)
        case .reward:
            // 對手跳過了，擋對手也沒問過
            go(rival.isEmpty ? .rival : .block)
        case .plan:
            go(.reward)
        }
        return true
    }

    /// 改成自己填：等的時候不等了，回到問之前那一步
    func leave() {
        if phase != .ready { back() }
    }

    /// 畫面關掉：還在等就不等了，跟按「不等了」一樣回到問之前那一步；沒在等就什麼都不動
    func cancel() {
        guard phase == .waiting else { return }
        leave()
    }

    func restart() {
        stop()
        go(.goal)
        phase = .ready
        offTopic = nil
        offTopicCount = 0
        clearPlan()
    }

    // MARK: 同意

    func agree() {
        AIClient.shared.hasConsented = true
        needsConsent = false
        if let p = pending {
            pending = nil
            start(p)
        }
    }

    /// 不同意或把說明頁滑掉：留在原本那一步，打的字也留著
    func decline() {
        pending = nil
        needsConsent = false
    }

    // MARK: 問 AI

    private func request(_ target: Step) {
        guard AIClient.shared.hasConsented else {
            pending = target
            needsConsent = true
            return
        }
        start(target)
    }

    private func start(_ target: Step) {
        stop()
        go(target)
        phase = .waiting
        let mine = round
        let input = TalkModel.input(for: target, goal: goal, floor: floor, trigger: trigger, rival: rival,
                                    seen: offer.seen)
        task = Task { [weak self] in
            do {
                let out = try await AIClient.shared.run(.plan, input: input, as: PlanOutput.self)
                self?.finished(out, at: target, round: mine)
            } catch let f as AIClient.Failure {
                self?.fail(f.message, round: mine)
            } catch {
                self?.fail(AIClient.fallbackMessage, round: mine)
            }
        }
    }

    /// 問這一步要送的東西：每一步只帶用得到的
    static func input(for target: Step, goal: String, floor: String, trigger: String, rival: String,
                      seen: [String]) -> PlanInput {
        let ask: PlanInput.Step
        switch target {
        case .goal, .floor: ask = .floor
        case .trigger: ask = .trigger
        case .rival: ask = .rival
        case .block: ask = .block
        case .reward: ask = .reward
        case .plan: ask = .estimate
        }
        return PlanInput(
            step: ask,
            goal: goal,
            floor: ask == .floor ? "" : floor,
            trigger: ask == .floor || ask == .trigger ? "" : trigger,
            rival: ask == .block || ask == .reward ? rival : "",
            exclude: ask == .estimate ? [] : Array(seen.suffix(PlanInput.excludeLimit))
        )
    }

    private func finished(_ out: AIClient.Outcome<PlanOutput>, at target: Step, round r: Int) {
        guard r == round else { return }
        switch out {
        case .result(let o): arrived(o, at: target)
        case .unfit(_, let referral): phase = .unfit(referral)
        }
    }

    /// 放棄還在路上的那一次
    private func stop() {
        round += 1
        task?.cancel()
        task = nil
    }

    private func fail(_ message: String, round r: Int) {
        guard r == round else { return }
        phase = .failed(message)
        Haptic.error()
    }

    /// 一次回來的結果。測試直接叫這個
    func arrived(_ o: PlanOutput, at target: Step) {
        if o.type == "off_topic" {
            drift(at: target)
            return
        }
        if o.type == "options", target.picks {
            var fresh: [String] = []
            for raw in o.options {
                let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty, !fresh.contains(v) { fresh.append(v) }
            }
            fresh = Array(fresh.prefix(3))
            guard !fresh.isEmpty else {
                fail(AIClient.fallbackMessage, round: round)
                return
            }
            var next = offers[target] ?? Offer()
            next.lead = o.lead.trimmingCharacters(in: .whitespacesAndNewlines)
            next.options = fresh
            next.seen += fresh
            offers[target] = next
        } else if o.type == "estimate", target == .plan {
            days = (o.difficulty ?? .medium).days
        } else {
            fail(AIClient.fallbackMessage, round: round)
            return
        }
        offTopicCount = 0
        offTopic = nil
        step = target
        phase = .ready
    }

    /// 離題：丟掉 AI 的字，回第一步，只留他打的那句
    private func drift(at target: Step) {
        let said: String
        switch target {
        case .goal, .floor: said = goal
        case .trigger: said = floor
        case .rival, .plan: said = trigger
        case .block: said = rival
        case .reward: said = block.isEmpty ? trigger : block
        }
        go(.goal)
        phase = .ready
        offTopic = said
        offTopicCount += 1
        clearPlan()
    }

    private func clearPlan() {
        goal = ""
        clearAfter(.goal)
    }

    /// 這一步之後選過的、問過的都清掉（換了前面的答案，後面要重問）
    private func clearAfter(_ s: Step) {
        for later in TalkModel.pickSteps where later.rawValue > s.rawValue {
            set(later, "")
            offers[later] = nil
        }
        days = nil
    }

    private func value(_ s: Step) -> String {
        switch s {
        case .goal: return goal
        case .floor: return floor
        case .trigger: return trigger
        case .rival: return rival
        case .block: return block
        case .reward: return reward
        case .plan: return ""
        }
    }

    private func set(_ s: Step, _ v: String) {
        switch s {
        case .goal: goal = v
        case .floor: floor = v
        case .trigger: trigger = v
        case .rival: rival = v
        case .block: block = v
        case .reward: reward = v
        case .plan: break
        }
    }

    private static func limit(_ s: Step) -> Int {
        switch s {
        case .goal: return PlanInput.goalLimit
        case .floor: return PlanInput.floorLimit
        case .trigger, .plan: return PlanInput.triggerLimit
        case .rival: return PlanInput.rivalLimit
        case .block: return PlanInput.blockLimit
        case .reward: return PlanInput.rewardLimit
        }
    }

    private func go(_ s: Step) {
        step = s
        draft = ""
        typing = false
    }

    /// 去頭尾空白，截到伺服器收的長度（伺服器用 UTF-16 數，表情符號一個算兩個以上）
    static func clip(_ text: String, _ limit: Int) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.utf16.count > limit { s.removeLast() }
        return s
    }
}

#if DEBUG
extension TalkModel {
    /// 模擬器拍圖用：啟動參數 -talkDemo N。1 到 4 是想養什麼、最小一步、時機、種下去（種下去那頁對手、擋對手、犒賞都填好），
    /// 5 離題，6 等待，7 連兩次離題，8 連不到，9 對手，10 擋對手，11 犒賞
    static func demo(_ n: Int) -> TalkModel {
        let m = TalkModel()
        guard n > 1 else { return m }
        if n == 5 || n == 7 {
            for _ in 0..<(n == 7 ? 2 : 1) {
                m.goal = "幫我寫一封信"
                m.arrived(PlanOutput(type: "off_topic"), at: .floor)
            }
            return m
        }
        m.goal = "我想每天靜下來"
        if n == 6 || n == 8 {
            m.step = .floor
            m.phase = n == 6 ? .waiting : .failed(AIClient.unreachableMessage)
            return m
        }
        m.arrived(PlanOutput(type: "options", lead: "最累那天也做得到的是？",
                             options: ["坐到鋪墊上", "深呼吸三次", "坐著一分鐘"]), at: .floor)
        guard n > 2 else { return m }
        m.floor = "坐到鋪墊上"
        m.arrived(PlanOutput(type: "options", lead: "每天一定會做的是？",
                             options: ["洗完臉", "刷完牙", "泡好咖啡"]), at: .trigger)
        guard n > 3 else { return m }
        m.trigger = "洗完臉"
        m.arrived(PlanOutput(type: "options", lead: "洗完臉最常先做的是這些",
                             options: ["拿起手機看訊息", "直接去泡咖啡", "回房間躺一下"]), at: .rival)
        if n == 9 { return m }
        m.rival = "拿起手機看訊息"
        m.arrived(PlanOutput(type: "options", lead: "前一晚做好，那一刻就不用忍",
                             options: ["手機放客廳充電", "前一晚把鋪墊鋪好", "手機開飛航再進浴室"]), at: .block)
        if n == 10 { return m }
        m.block = "手機放客廳充電"
        m.arrived(PlanOutput(type: "options", lead: "做完馬上有，才記得住",
                             options: ["泡一杯喜歡的茶", "坐完感覺呼吸變慢", "聽一首喜歡的歌"]), at: .reward)
        if n == 11 { return m }
        m.reward = "泡一杯喜歡的茶"
        m.arrived(PlanOutput(type: "estimate", difficulty: .medium), at: .plan)
        return m
    }
}
#endif
