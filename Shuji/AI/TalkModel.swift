import Foundation
import Observation

/// 跟地瓜對答的狀態：四步，一步問一次 AI（任務 8）。畫面在 TalkView。
/// 伺服器不存對話；選過的、給過的選項都只在這裡，換頁就沒了。
@MainActor
@Observable
final class TalkModel {
    enum Step: Int { case goal = 1, floor, trigger, plan }

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

    private(set) var step: Step = .goal
    private(set) var phase: Phase = .ready
    private(set) var goal = ""
    private(set) var floor = ""
    private(set) var trigger = ""
    private(set) var days: Int?
    private(set) var floorOffer = Offer()
    private(set) var triggerOffer = Offer()
    /// 剛剛離題的那一句
    private(set) var offTopic: String?
    private(set) var offTopicCount = 0

    var draft = ""
    /// 按了「自己打」
    var typing = false
    /// 第一次送出前先問資料去哪
    var needsConsent = false

    @ObservationIgnored private var pending: Step?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 第幾次問。取消、重來之後，晚到的結果對不上就丟掉
    @ObservationIgnored private var round = 0

    // MARK: 畫面要的

    var offer: Offer { step == .trigger ? triggerOffer : floorOffer }

    var draftValue: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var draftLimit: Int {
        switch step {
        case .goal: return PlanInput.goalLimit
        case .floor: return PlanInput.floorLimit
        case .trigger, .plan: return PlanInput.triggerLimit
        }
    }

    /// 最小一步不能是「不做某件事」
    var draftNegative: Bool { step == .floor && Wording.isNegative(draftValue) }

    var canSend: Bool { !draftValue.isEmpty && !draftNegative }

    var showsInput: Bool {
        switch step {
        case .goal: return typing || offTopicCount < TalkModel.offTopicLimit
        case .floor, .trigger: return typing || offer.options.isEmpty
        case .plan: return false
        }
    }

    /// 上一步選的那句，靠右的泡泡
    var bubble: String? {
        let s: String
        switch step {
        case .goal: s = offTopic ?? ""
        case .floor: s = goal
        case .trigger: s = floor
        case .plan: s = trigger
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
        floor = ""
        trigger = ""
        days = nil
        floorOffer = Offer()
        triggerOffer = Offer()
        request(.floor)
    }

    func pickFloor(_ text: String) {
        let v = TalkModel.clip(text, PlanInput.floorLimit)
        guard !v.isEmpty, phase != .waiting else { return }
        if v == floor, !triggerOffer.options.isEmpty {
            go(.trigger)
            return
        }
        floor = v
        trigger = ""
        days = nil
        triggerOffer = Offer()
        request(.trigger)
    }

    func pickTrigger(_ text: String) {
        let v = TalkModel.clip(text, PlanInput.triggerLimit)
        guard !v.isEmpty, phase != .waiting else { return }
        if v == trigger, days != nil {
            go(.plan)
            return
        }
        trigger = v
        days = nil
        request(.plan)
    }

    /// 換一批
    func more() {
        guard phase == .ready, step == .floor || step == .trigger else { return }
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
        let middle = step == .floor || step == .trigger
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
        case .plan:
            go(.trigger)
        }
        return true
    }

    /// 改成自己填：等的時候不等了，回到問之前那一步
    func leave() {
        if phase != .ready { back() }
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
        let ask: PlanInput.Step
        switch target {
        case .goal, .floor: ask = .floor
        case .trigger: ask = .trigger
        case .plan: ask = .estimate
        }
        let input = PlanInput(
            step: ask,
            goal: goal,
            floor: ask == .floor ? "" : floor,
            trigger: ask == .estimate ? trigger : "",
            exclude: ask == .estimate ? [] : Array(offer.seen.suffix(PlanInput.excludeLimit))
        )
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
        if o.type == "options", target == .floor || target == .trigger {
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
            var next = target == .floor ? floorOffer : triggerOffer
            next.lead = o.lead.trimmingCharacters(in: .whitespacesAndNewlines)
            next.options = fresh
            next.seen += fresh
            if target == .floor { floorOffer = next } else { triggerOffer = next }
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
        case .plan: said = trigger
        }
        go(.goal)
        phase = .ready
        offTopic = said
        offTopicCount += 1
        clearPlan()
    }

    private func clearPlan() {
        goal = ""
        floor = ""
        trigger = ""
        days = nil
        floorOffer = Offer()
        triggerOffer = Offer()
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
    /// 模擬器拍圖用：啟動參數 -talkDemo N。1 到 4 是四步，5 離題，6 等待，7 連兩次離題，8 連不到
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
        m.arrived(PlanOutput(type: "estimate", difficulty: .medium), at: .plan)
        return m
    }
}
#endif
