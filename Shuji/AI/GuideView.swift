import SwiftUI

// 任務 7 對話引導：首次設定用問答的方式走。
// 一輪一題，每題附可以點的選項，也可以自己打。問夠了 AI 拆出兩三組「如果…我就…」，
// 估一個大約幾週會長好的範圍，由人挑一組種下去。
// 伺服器不存對話：每一輪把到目前為止的問答整份送過去。
// 失敗、沒網路、次數用完：顯示一句話，可以再試，也可以改成自己填。

enum Guide {
    /// 第一題固定由 app 問，不呼叫模型。跟 server/eval/guide.ts 的 FIRST_QUESTION 一字不差
    static let firstQuestion = "你想養成什麼習慣？"
    static let starters = ["每天運動", "每天寫一點東西", "睡前看書", "多喝水", "每天靜坐"]
    /// 伺服器一段對話最多收 10 筆問答
    static let maxTurns = 10
    static let answerLimit = 100

    /// 對提案有意見時，那一筆問答的 q：把看到的方案寫進去，模型才知道意見是針對什麼
    static func feedbackQuestion(_ plans: [GuideOutput.Plan]) -> String {
        let list = plans.map { "如果\($0.trigger)，我就\($0.floor)" }.joined(separator: "／")
        return String("方案：\(list)。想調整什麼？".prefix(200))
    }

    static func weeksText(_ o: GuideOutput) -> String { "\(o.weeks_min) 到 \(o.weeks_max) 週" }
}

struct GuideView: View {
    @Environment(Store.self) private var store
    /// 有給的話只挑一組交出去（放進排隊），不種、不碰現在的習慣
    var queueOnly: ((GuideOutput.Plan) -> Void)? = nil
    /// 改成自己填。帶著目前選到的最小一步和時機（沒有就空字串）
    var onManual: (_ floor: String, _ trigger: String) -> Void
    var onRestore: () -> Void

    @State private var call = AICall<GuideOutput>()
    @State private var turns: [GuideTurn] = []
    @State private var say = ""
    @State private var question = Guide.firstQuestion
    @State private var options: [String] = []
    @State private var proposal: GuideOutput?
    @State private var picked = 0
    @State private var draft = ""
    /// 送出去了、還沒回來
    @State private var awaiting = false
    @FocusState private var typing: Bool

    private var draftValue: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAddTurn: Bool { turns.count < Guide.maxTurns }

    private var failed: Bool {
        if case .failed = call.phase { return true }
        return false
    }

    private var shownOptions: [String] {
        guard turns.isEmpty else { return options }
        // 排隊中的排前面；重複的只留一個（ChipFlow 用字串當 id）
        var seen = Set<String>()
        return (store.state.queue + Guide.starters).filter { seen.insert($0).inserted }
    }

    var body: some View {
        DomyScreen(title: queueOnly == nil ? "種一個習慣" : "下一個要種什麼", sub: "回答幾題，幫你拆成每天做得到的一步。") {
            if !turns.isEmpty { saidSoFar }
            if call.isLoading {
                AIStatus(call: call)
            } else if call.isUnfit {
                AIStatus(call: call)
                DomyButton("換一件事", variant: .secondary) { restart() }
            } else if failed {
                AIStatus(call: call)
                VStack(spacing: Sp.s2) {
                    DomyButton("再試一次") { send() }
                    if queueOnly == nil {
                        DomyButton("我自己填", variant: .secondary) { onManual("", "") }
                    }
                }
            } else if let p = proposal {
                proposalSection(p)
            } else {
                questionSection
            }
            if !call.isLoading && !failed {
                VStack(spacing: Sp.s2) {
                    if !turns.isEmpty && !call.isUnfit {
                        DomyButton("重新問一次", variant: .quiet, size: .compact) { restart() }
                    }
                    if queueOnly == nil {
                        DomyButton("我自己填", variant: .quiet, size: .compact) { onManual("", "") }
                        DomyButton("從備份還原", variant: .quiet, size: .compact) { onRestore() }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .aiConsent(call)
        .onChange(of: call.seq) { _, _ in arrived() }
        .onChange(of: call.needsConsent) { _, showing in
            // 說明頁關掉了卻沒同意：把剛剛那句收回來，留在輸入框
            if !showing && awaiting && !AIClient.shared.hasConsented { undoLast() }
        }
    }

    // MARK: 到目前為止說過的

    private var saidSoFar: some View {
        VStack(alignment: .leading, spacing: Sp.s2) {
            Eyebrow("你說的")
            FlowLayout(spacing: Sp.s2) {
                ForEach(Array(turns.enumerated()), id: \.offset) { _, t in
                    Chip(t.a.count > 18 ? String(t.a.prefix(18)) + "…" : t.a)
                }
            }
        }
        .padding(.horizontal, Sp.s1)
        .accessibilityElement(children: .combine)
    }

    // MARK: 一題

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: Sp.s3) {
            if !say.isEmpty {
                Text(say)
                    .domyType(Ty.subheadline)
                    .foregroundStyle(Theme.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Sp.s1)
            }
            Text(question)
                .domyType(Ty.headline)
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Sp.s1)
                .accessibilityAddTraits(.isHeader)
            if !shownOptions.isEmpty {
                ChipFlow(items: shownOptions, accent: true) { answer($0) }
            }
            inputRow(placeholder: turns.isEmpty ? "例如：每天運動 30 分鐘" : "都不是的話，自己打") {
                answer(draftValue)
            }
            if turns.isEmpty && queueOnly == nil {
                Foot("一次只種一個，長好了再種下一個。")
            }
        }
    }

    private func inputRow(placeholder: String, submit: @escaping () -> Void) -> some View {
        HStack(alignment: .bottom, spacing: Sp.s2) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .autocorrectionDisabled()
                .onChange(of: draft) { _, v in
                    if v.count > Guide.answerLimit { draft = String(v.prefix(Guide.answerLimit)) }
                }
                .domyField(focused: typing)
            DomyButton("送出", size: .compact, disabled: draftValue.isEmpty) { submit() }
        }
    }

    // MARK: 提案

    @ViewBuilder
    private func proposalSection(_ p: GuideOutput) -> some View {
        VStack(alignment: .leading, spacing: Sp.s3) {
            if !p.say.isEmpty {
                Text(p.say)
                    .domyType(Ty.subheadline)
                    .foregroundStyle(Theme.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Sp.s1)
            }
            Text(p.plans.count > 1 ? "拆成這樣，挑一組" : "拆成這樣")
                .domyType(Ty.headline)
                .foregroundStyle(Theme.fg)
                .padding(.horizontal, Sp.s1)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(p.plans.enumerated()), id: \.offset) { i, plan in
                PlanCard(plan: plan, on: i == picked, recommended: i == 0 && p.plans.count > 1) { picked = i }
            }
        }

        VStack(alignment: .leading, spacing: Sp.s2) {
            Card {
                RowLabel(text: "大約多久會長好", value: Guide.weeksText(p), mini: p.difficultyLabel)
                if !p.reason.isEmpty {
                    RowSep()
                    Text(p.reason)
                        .domyType(Ty.subheadline)
                        .foregroundStyle(Theme.fg)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Sp.s4)
                        .padding(.vertical, Sp.s3)
                }
            }
            Foot("這是照這件事的難度估的範圍，每個人差很多。中間漏掉幾天，它還是在長。")
        }

        DomyButton(queueOnly == nil ? "種下去" : "排進下一個") { plant(p) }

        if canAddTurn {
            VStack(alignment: .leading, spacing: Sp.s2) {
                Eyebrow("想調整的話跟我說").padding(.horizontal, Sp.s1)
                inputRow(placeholder: "例如：時機換成早上的") {
                    turns.append(GuideTurn(q: Guide.feedbackQuestion(p.plans), a: draftValue))
                    draft = ""
                    send()
                }
            }
        }
        if queueOnly == nil {
            DomyButton("我自己改這一組", variant: .quiet, size: .compact) {
                let plan = p.plans[min(picked, p.plans.count - 1)]
                onManual(plan.floor, plan.trigger)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: 動作

    private func answer(_ text: String) {
        let a = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Guide.answerLimit))
        guard !a.isEmpty, canAddTurn, !call.isLoading else { return }
        turns.append(GuideTurn(q: String(question.prefix(200)), a: a))
        draft = ""
        typing = false
        send()
    }

    private func send() {
        guard !turns.isEmpty else { return }
        awaiting = true
        call.run(.guide, GuideInput(turns: turns, queue: Array(store.state.queue.prefix(10))))
    }

    /// 新的一輪回來了
    private func arrived() {
        awaiting = false
        guard let o = call.output else { return }
        if o.type == "propose", !o.plans.isEmpty {
            proposal = o
            picked = 0
        } else {
            proposal = nil
            say = o.say
            question = o.question
            options = o.options
        }
    }

    private func undoLast() {
        awaiting = false
        guard let last = turns.popLast() else { return }
        draft = last.a
    }

    private func restart() {
        call = AICall<GuideOutput>()
        turns = []
        say = ""
        question = Guide.firstQuestion
        options = []
        proposal = nil
        picked = 0
        draft = ""
        awaiting = false
    }

    private func plant(_ p: GuideOutput) {
        guard !p.plans.isEmpty else { return }
        let plan = p.plans[min(picked, p.plans.count - 1)]
        typing = false
        if let queueOnly {
            queueOnly(plan)
            return
        }
        Haptic.bloom()
        store.plant(floor: String(plan.floor.prefix(40)), trigger: String(plan.trigger.prefix(30)))
    }
}

/// 一組「如果…我就…」，可以點選
private struct PlanCard: View {
    var plan: GuideOutput.Plan
    var on: Bool
    var recommended: Bool
    var pick: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Rd.xl, style: .continuous)
        Button(action: pick) {
            HStack(alignment: .top, spacing: Sp.s3) {
                SignalDot(ok: on).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Sp.s1) {
                    if recommended {
                        Text("我會先選這組")
                            .domyType(Ty.caption)
                            .foregroundStyle(Theme.strong)
                    }
                    (Text("如果") + Text(plan.trigger).bold() + Text("，我就") + Text(plan.floor).bold() + Text("。"))
                        .domyType(Ty.body)
                        .foregroundStyle(Theme.fg)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Sp.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Theme.tint : Theme.surface, in: shape)
            .overlay(shape.strokeBorder(on ? Theme.accent : Theme.separator, lineWidth: on ? Sz.hairline * 2 : Sz.hairline))
            .contentShape(shape)
        }
        .buttonStyle(DomyPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
