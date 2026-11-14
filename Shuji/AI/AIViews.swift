import SwiftUI

// AI 只站在設定時刻和出事時，不站在每天的畫面上（ai/AI交接.md 第一節）。
// 每個 AI 入口都是「幫我想」：結果是候選或建議，由人點選或按「改成這個」才寫進去。
// 失敗、沒網路、次數用完：顯示一句話，手動流程照常。

// MARK: 一次呼叫的狀態

@MainActor
@Observable
final class AICall<O: Decodable> {
    enum Phase {
        case idle
        case loading
        case done(O)
        case unfit(String)
        case failed(String)
    }

    var phase: Phase = .idle
    var needsConsent = false
    @ObservationIgnored private var pending: (() async -> Void)?

    var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    var isUnfit: Bool {
        if case .unfit = phase { return true }
        return false
    }

    var output: O? {
        if case .done(let o) = phase { return o }
        return nil
    }

    func run<I: Encodable>(_ task: AITask, _ input: I, habitId: String? = nil) {
        guard !isLoading else { return }
        let job: () async -> Void = { [weak self] in
            await self?.perform(task, input, habitId)
        }
        if !AIClient.shared.hasConsented {
            pending = job
            needsConsent = true
            return
        }
        Task { await job() }
    }

    func consented() {
        AIClient.shared.hasConsented = true
        needsConsent = false
        if let job = pending {
            pending = nil
            Task { await job() }
        }
    }

    func declined() {
        pending = nil
        needsConsent = false
    }

    private func perform<I: Encodable>(_ task: AITask, _ input: I, _ habitId: String?) async {
        phase = .loading
        do {
            switch try await AIClient.shared.run(task, input: input, habitId: habitId, as: O.self) {
            case .result(let o): phase = .done(o)
            case .unfit(_, let referral): phase = .unfit(referral)
            }
        } catch let f as AIClient.Failure {
            phase = .failed(f.message)
        } catch {
            phase = .failed(AIClient.fallbackMessage)
        }
    }
}

// MARK: 第一次用之前：說清楚資料去哪

struct AIConsentSheet: View {
    var agree: () -> Void
    var decline: () -> Void

    var body: some View {
        SheetFrame {
            SheetTitle("先說清楚資料去哪")
            SheetNote("按下去之後，你在這一格寫的字會送到薯記的伺服器，再交給 Anthropic 的 Claude 模型想建議。")
            Card {
                RowLabel(text: "只送這一次需要的內容", mini: "例如開關句和你剛寫的那幾句，不送整份紀錄")
                RowSep()
                RowLabel(text: "薯記的伺服器不存你寫的字", mini: "只記這台裝置今天用了幾次，用來擋濫用")
                RowSep()
                RowLabel(text: "Anthropic 依它的隱私政策處理這段文字")
            }
            SheetNote("不想送也沒關係，每一格都可以自己填，app 照常能用。")
            VStack(spacing: Sp.s2) {
                DomyButton("好，送出去") { agree() }
                DomyButton("不用了，我自己填", variant: .secondary) { decline() }
            }
        }
    }
}

private struct AIConsentModifier<O: Decodable>: ViewModifier {
    @Bindable var call: AICall<O>

    func body(content: Content) -> some View {
        content.sheet(isPresented: $call.needsConsent) {
            AIConsentSheet(agree: { call.consented() }, decline: { call.declined() })
        }
    }
}

extension View {
    func aiConsent<O: Decodable>(_ call: AICall<O>) -> some View {
        modifier(AIConsentModifier(call: call))
    }
}

// MARK: 共用零件

/// 載入中、失敗、不適合三種狀態
struct AIStatus<O: Decodable>: View {
    var call: AICall<O>

    var body: some View {
        switch call.phase {
        case .loading:
            HStack(spacing: Sp.s3) {
                ProgressView().tint(Theme.accent)
                Text("想一下⋯").domyType(Ty.subheadline).foregroundStyle(Theme.fg2)
            }
            .padding(.horizontal, Sp.s1)
            .frame(minHeight: Sz.touch)
        case .failed(let message):
            WarnBox { Text(message) }
        case .unfit(let referral):
            ReferralCard(text: referral)
        default:
            EmptyView()
        }
    }
}

/// 護欄包第六節的固定轉介文字，原文顯示
struct ReferralCard: View {
    var text: String

    var body: some View {
        Card {
            CardBody {
                Text(text)
                    .domyType(Ty.body)
                    .foregroundStyle(Theme.fg)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// AI 給的一段話（摘要、建議），放在白卡裡
struct AIText: View {
    var text: String

    var body: some View {
        Card {
            CardBody {
                Text(text)
                    .domyType(Ty.body)
                    .foregroundStyle(Theme.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 一條建議，按「放進…」直接寫進設定頁那一格
struct SuggestionCard: View {
    @Environment(Store.self) private var store
    var text: String
    var field: HabitField
    var caption: String? = nil
    @State private var applied = false

    var body: some View {
        Card {
            CardBody(spacing: Sp.s3) {
                Eyebrow(caption ?? field.label)
                Text(text)
                    .domyType(Ty.body)
                    .foregroundStyle(Theme.fg)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    DomyButton(applied ? "放好了" : "放進「\(field.label)」",
                               variant: applied ? .secondary : .primary, size: .compact, disabled: applied) {
                        guard !applied else { return }
                        let value = String(text.prefix(60))
                        store.updateHabit { field.apply(value, to: &$0) }
                        applied = true
                        store.show("改好了。")
                    }
                }
            }
        }
    }
}

/// 多行輸入框，Domy 輸入框樣式
struct AIInput: View {
    var placeholder: String
    @Binding var text: String
    var limit: Int = 200
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(2...6)
            .focused($focused)
            .onChange(of: text) { _, v in
                if v.count > limit { text = String(v.prefix(limit)) }
            }
            .domyField(focused: focused)
    }
}

/// 一題：粗一點的題目＋輸入
struct AIQuestion<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.s2) {
            Text(title)
                .domyType(Ty.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Sp.s1)
            content
        }
    }
}

private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

// MARK: 任務 1 種下去助手（首次設定第 1 步）

struct PlantHelper: View {
    @Environment(Store.self) private var store
    var goal: String
    @Binding var floor: String
    @Binding var aiTriggers: [String]
    @Binding var blocked: Bool
    @State private var call = AICall<PlantOutput>()

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.s3) {
            if !call.isLoading {
                DomyButton(call.output == nil ? "幫我拆小一點" : "再想一次",
                           variant: call.output == nil ? .plain : .quiet, size: .compact,
                           disabled: goal.isEmpty) {
                    call.run(.plant, PlantInput(goal: goal, queue: store.state.queue))
                }
            }
            AIStatus(call: call)
            if let o = call.output {
                if o.type == "ok" {
                    Card {
                        CardBody(spacing: Sp.s3) {
                            Eyebrow("最小一步，挑一個")
                            ChipFlow(items: o.floors, accent: true, selected: trimmed(floor)) { floor = $0 }
                            if !o.note.isEmpty {
                                Text(o.note).domyType(Ty.footnote).foregroundStyle(Theme.fg2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Foot("開關的候選放在下一步。")
                } else if let m = o.message, !m.isEmpty {
                    WarnBox { Text(m) }
                }
            }
        }
        .aiConsent(call)
        .onChange(of: call.output?.triggers ?? []) { _, t in
            if !t.isEmpty { aiTriggers = t }
        }
        .onChange(of: call.isUnfit) { _, unfit in
            if unfit {
                blocked = true
                aiTriggers = []
            }
        }
    }
}

// MARK: 任務 2 障礙版與旅行版

struct ObstacleSheet: View {
    @Environment(Store.self) private var store
    @State private var interruptions = ""
    @State private var travels = false
    @State private var call = AICall<ObstacleOutput>()

    var body: some View {
        SheetFrame {
            SheetTitle("不順的時候")
            SheetNote("過去兩週，這件事最常怎麼被打斷？挑最常見的一兩個寫就好。沒被打斷過也可以空著。")
            AIInput(placeholder: "早上有時候要趕出門，週末常常睡到中午", text: $interruptions, limit: 300)
            Card {
                DomyToggleRow(label: "最近會出遠門", isOn: $travels)
            }
            if !call.isLoading {
                DomyButton(call.output == nil ? "幫我想" : "再想一次",
                           variant: call.output == nil ? .primary : .secondary) { run() }
            }
            AIStatus(call: call)
            if let o = call.output { results(o) }
        }
        .aiConsent(call)
    }

    private func run() {
        guard let h = store.state.habit else { return }
        call.run(.obstacle, ObstacleInput(trigger: h.trigger, floor: h.floor, interruptions: trimmed(interruptions), travels: travels))
    }

    @ViewBuilder
    private func results(_ o: ObstacleOutput) -> some View {
        ForEach(Array(o.obstacles.enumerated()), id: \.offset) { _, p in
            SuggestionCard(text: "如果\(p.if)，就\(p.then)。", field: .backup, caption: "被「\(p.if)」擋住的時候")
        }
        if let b = o.backup, !b.isEmpty {
            SuggestionCard(text: b, field: .backup, caption: "開關沒出現的那天")
        }
        if let t = o.travel {
            if t.portable, !t.floor.isEmpty {
                SuggestionCard(text: t.floor, field: .travelFloor, caption: "出遠門的時候")
            }
            if !t.alt.isEmpty {
                Foot(t.alt)
            }
        }
        if !o.note.isEmpty { Foot(o.note) }
    }
}

// MARK: 任務 3 對手偵測（放在「讓開始更容易」裡）

struct RivalHelper: View {
    @Environment(Store.self) private var store
    @State private var rival = ""
    @State private var feel = ""
    @State private var call = AICall<RivalOutput>()
    private static let feels = ["有想要的感覺", "回過神已經在做", "焦慮、無聊或累", "跟某個人或場合有關"]

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.s4) {
            SectionTitle("開關那一刻的對手")
            AIQuestion(title: "開關出現的那一刻，你通常手上拿著什麼、或正在做什麼？") {
                AIInput(placeholder: "手機，會先看一下訊息，常常就滑掉半小時", text: $rival)
            }
            AIQuestion(title: "那時候比較像") {
                ChipFlow(items: Self.feels, accent: false, selected: feel) { feel = $0 }
            }
            if !call.isLoading {
                DomyButton("幫我看看", disabled: trimmed(rival).isEmpty) {
                    guard let h = store.state.habit else { return }
                    call.run(.rival, RivalInput(trigger: h.trigger, floor: h.floor, rival: trimmed(rival), feel: feel))
                }
            }
            AIStatus(call: call)
            if let o = call.output {
                Card {
                    RowLabel(text: o.rivalLabel)
                    RowSep()
                    labeled("擋對手", o.block)
                    RowSep()
                    labeled("拆自己的路", o.clear)
                }
                if !o.note.isEmpty { Foot(o.note) }
            }
        }
        .aiConsent(call)
    }

    private func labeled(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Sp.s1) {
            Eyebrow(title)
            Text(text)
                .domyType(Ty.body)
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Sp.s4)
        .padding(.vertical, Sp.s3)
    }
}

// MARK: 任務 4 三問診斷（停了兩週以上回來）

struct DiagnoseSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var q1 = ""
    @State private var q2 = ""
    @State private var q3 = ""
    @State private var call = AICall<DiagnoseOutput>()

    var body: some View {
        SheetFrame {
            SheetTitle("回答三題")
            SheetNote("照實寫就好，一兩句。答完會給你一個要改的地方。")
            question("開關有出現嗎？", chips: ["有，每天都有", "有時候沒有", "很少出現"], text: $q1)
            question("最小一步太大嗎？", chips: ["不會", "累的日子做不到", "太大了"], text: $q2)
            question("旁邊有更近的東西搶走了嗎？", chips: ["沒有", "手機", "想睡、很累"], text: $q3)
            if !call.isLoading && call.output == nil {
                DomyButton("幫我看哪裡要改", disabled: filled == 0) { run() }
            }
            AIStatus(call: call)
            if let o = call.output {
                if o.layer == 0 || o.field == nil {
                    AIText(text: o.suggestion)
                } else if let f = o.field {
                    SuggestionCard(text: o.suggestion, field: f)
                    if !o.why.isEmpty { Foot(o.why) }
                }
                Text(o.closing)
                    .domyType(Ty.body)
                    .foregroundStyle(Theme.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Sp.s1)
                DomyButton("好") { dismiss() }
            }
        }
        .aiConsent(call)
    }

    private var filled: Int { [q1, q2, q3].filter { !trimmed($0).isEmpty }.count }

    private func run() {
        guard let input = store.state.diagnoseInput(today: store.today, q1: trimmed(q1), q2: trimmed(q2), q3: trimmed(q3)) else { return }
        call.run(.diagnose, input)
    }

    private func question(_ title: String, chips: [String], text: Binding<String>) -> some View {
        AIQuestion(title: title) {
            ChipFlow(items: chips, accent: false, selected: trimmed(text.wrappedValue)) { text.wrappedValue = $0 }
            AIInput(placeholder: "自己寫也可以", text: text)
        }
    }
}

// MARK: 任務 5 週回顧建議（完整版）

struct WeekAdviceSheet: View {
    @Environment(Store.self) private var store
    @State private var call = AICall<WeeklyOutput>()

    var body: some View {
        SheetFrame {
            SheetTitle("這週看什麼")
            SheetNote("讀這兩週的紀錄和開始四問的線，一週只提一個要修的地方。")
            AIStatus(call: call)
            if let o = call.output {
                AIText(text: o.summary)
                if let fix = o.fix, o.verdict == "fix" {
                    if let f = fix.field {
                        SuggestionCard(text: fix.suggestion, field: f)
                    } else {
                        Foot(fix.suggestion)
                    }
                }
                if !o.note.isEmpty { Foot(o.note) }
            }
            if case .failed = call.phase {
                DomyButton("再試一次", variant: .secondary) { run() }
            }
        }
        .aiConsent(call)
        .task { if case .idle = call.phase { run() } }
    }

    private func run() {
        guard let input = store.state.weeklyInput(today: store.today) else { return }
        call.run(.weekly, input, habitId: store.state.habit?.planted.string)
    }
}

// MARK: 任務 6 季稽核（完整版）

struct AuditSheet: View {
    @Environment(Store.self) private var store
    @State private var satisfied = ""
    @State private var change = ""
    @State private var call = AICall<AuditOutput>()

    var body: some View {
        SheetFrame {
            SheetTitle("季稽核")
            SheetNote("一季看一次。只選一條路：維持、加量、換情境或退場。")
            if let why = store.state.habit?.why, !why.isEmpty {
                Card { RowLabel(text: "你說這是為了", mini: why) }
            }
            AIQuestion(title: "這一季它帶來了什麼？滿意嗎？") {
                AIInput(placeholder: "寫了很多，但大多是零散筆記，沒有一篇發出去", text: $satisfied, limit: 300)
            }
            AIQuestion(title: "下一季開關、地點、作息會變嗎？") {
                AIInput(placeholder: "下一季會去外地住兩個月", text: $change, limit: 300)
            }
            if !call.isLoading {
                DomyButton(call.output == nil ? "做稽核" : "再做一次",
                           variant: call.output == nil ? .primary : .secondary,
                           disabled: trimmed(satisfied).isEmpty) {
                    guard let input = store.state.auditInput(today: store.today, satisfied: trimmed(satisfied), contextChange: trimmed(change)) else { return }
                    call.run(.audit, input)
                }
            }
            AIStatus(call: call)
            if let o = call.output {
                Card {
                    RowLabel(text: "這一季走", value: o.pathLabel)
                    RowSep()
                    Text(o.change)
                        .domyType(Ty.body)
                        .foregroundStyle(Theme.fg)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Sp.s4)
                        .padding(.vertical, Sp.s3)
                }
                Foot(o.why)
                if !o.warn.isEmpty { WarnBox { Text(o.warn) } }
            }
        }
        .aiConsent(call)
    }
}

// MARK: 完整版

struct PaywallSheet: View {
    private let purchases = Purchases.shared

    var body: some View {
        SheetFrame {
            VStack(spacing: Sp.s3) {
                PotatoView(width: 96) // domy-ignore: 插畫尺寸
                SheetTitle("薯記完整版")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Sp.s4)
            .background(Theme.tint, in: RoundedRectangle(cornerRadius: Rd.xl, style: .continuous))
            SheetNote("一次買斷，不訂閱。按住記一節、種下去助手、卡住時的三問，這些一直免費。")
            Card {
                feature("calendar", "週回顧建議", "做完開始四問，看這週要修哪一個地方")
                RowSep()
                feature("leaf", "季稽核", "一季一次，選維持、加量、換情境或退場")
                RowSep()
                feature("rectangle.on.rectangle", "小工具", "桌面和鎖定畫面看得到開關句、今天記了沒")
            }
            if purchases.isFull {
                DomyInfoStrip(text: "這台裝置已經是完整版了。")
            } else {
                VStack(spacing: Sp.s2) {
                    DomyButton(buyTitle, disabled: purchases.busy) {
                        Task { await purchases.buy() }
                    }
                    DomyButton("恢復購買", variant: .quiet, size: .compact) {
                        Task { await purchases.restore() }
                    }
                }
            }
            if let m = purchases.message { Foot(m) }
        }
        .task { await purchases.loadProduct() }
    }

    private func feature(_ icon: String, _ title: String, _ mini: String) -> some View {
        HStack(alignment: .top, spacing: Sp.s3) {
            Image(systemName: icon)
                .font(Ty.callout.font)
                .foregroundStyle(Theme.strong)
                .frame(width: Sp.s8, height: Sp.s8)
                .background(Theme.soft, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Sp.s1 / 2) {
                Text(title).domyType(Ty.body).foregroundStyle(Theme.fg)
                Text(mini)
                    .domyType(Ty.footnote)
                    .foregroundStyle(Theme.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Sp.s4)
        .padding(.vertical, Sp.s3)
        .accessibilityElement(children: .combine)
    }

    private var buyTitle: String {
        if purchases.busy { return "處理中⋯" }
        if let p = purchases.product { return "買完整版 \(p.displayPrice)" }
        return "買完整版"
    }
}
