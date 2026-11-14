import SwiftUI

/// 首次設定，兩步：最小一步、掛在哪個瞬間後面。
struct OnboardingView: View {
    @Environment(Store.self) private var store
    @State private var step = 1
    @State private var floor = ""
    @State private var trigger = ""
    @State private var showUnfit = false
    @State private var showRestore = false
    @State private var loaded = false
    /// 種下去助手給的開關候選，第 2 步用來取代預設的範例
    @State private var aiTriggers: [String] = []
    /// 種下去助手判斷不適合（轉介），改了最小一步才放行
    @State private var blocked = false
    @FocusState private var focus: Field?

    enum Field { case floor, trigger }

    private var floorValue: String { floor.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var triggerValue: String { trigger.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if step == 1 { stepOne } else { stepTwo }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if floor.isEmpty { floor = store.state.queue.first ?? "" }
        }
        .sheet(isPresented: $showUnfit) { UnfitSheet() }
        .sheet(isPresented: $showRestore) { RestoreSheet() }
        .onChange(of: floor) { _, _ in blocked = false }
    }

    // MARK: 第 1 步

    private var stepOne: some View {
        DomyScreen(title: "種一個習慣", sub: "一次只種一個，長好了再種下一個。") {
            StepBar(step: 1, total: 2)
            VStack(alignment: .leading, spacing: Sp.s3) {
                fieldLabel("每天想多做的事，最小的那一步是？")
                bigInput("打開檔案寫一句", text: $floor, limit: 40, field: .floor)
                    .onSubmit { if canGoNext { goNext() } }
                Foot("小到最糟的一天也做得到，兩分鐘內做完。")
                if !store.state.queue.isEmpty {
                    Eyebrow("排隊中").padding(.top, Sp.s2)
                    ChipFlow(items: store.state.queue, accent: true, selected: floorValue) { floor = $0 }
                    Eyebrow("或從這些開始").padding(.top, Sp.s2)
                } else {
                    Eyebrow("從這些開始").padding(.top, Sp.s2)
                }
                ChipFlow(items: Phrases.floorExamples, selected: floorValue) { floor = $0 }
            }
            warnings(floor: floorValue, trigger: "")
            if AIClient.shared.isAvailable {
                PlantHelper(goal: floorValue, floor: $floor, aiTriggers: $aiTriggers, blocked: $blocked)
            }
            VStack(spacing: Sp.s2) {
                DomyButton("下一步", disabled: !canGoNext) { goNext() }
                DomyButton("從備份還原", variant: .quiet, size: .compact) { showRestore = true }
            }
        }
    }

    private var canGoNext: Bool { !floorValue.isEmpty && !Wording.isNegative(floorValue) && !blocked }

    private func goNext() {
        step = 2
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focus = .trigger }
    }

    // MARK: 第 2 步

    private var stepTwo: some View {
        DomyScreen(title: "掛在哪裡", sub: "找一個每天一定會發生的瞬間。") {
            StepBar(step: 2, total: 2)
            VStack(alignment: .leading, spacing: Sp.s3) {
                fieldLabel("「\(floorValue)」要接在每天哪個瞬間後面？")
                bigInput("起床喝完第一杯水", text: $trigger, limit: 30, field: .trigger)
                    .onSubmit { if !triggerValue.isEmpty { plant() } }
                Foot("一個瞬間，不是一段時間。「早上有空時」不算，「刷完牙」算。")
                ChipFlow(items: aiTriggers.isEmpty ? Phrases.triggerExamples : aiTriggers,
                         accent: !aiTriggers.isEmpty, selected: triggerValue) { trigger = $0 }
                    .padding(.top, Sp.s2)
            }
            SwitchCard(trigger: triggerValue.isEmpty ? "＿＿" : triggerValue, floor: floorValue)
            if Wording.isFood(triggerValue) && !Wording.isFood(floorValue) {
                warnings(floor: "", trigger: triggerValue)
            }
            VStack(spacing: Sp.s2) {
                DomyButton("種下去", disabled: triggerValue.isEmpty) { plant() }
                DomyButton("‹ 改最小一步", variant: .quiet, size: .compact) { step = 1 }
            }
        }
    }

    private func plant() {
        guard !floorValue.isEmpty, !triggerValue.isEmpty else { return }
        focus = nil
        store.plant(floor: floorValue, trigger: triggerValue)
    }

    // MARK: 零件

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .domyType(Ty.headline)
            .foregroundStyle(Theme.fg)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Sp.s1)
    }

    private func bigInput(_ placeholder: String, text: Binding<String>, limit: Int, field: Field) -> some View {
        TextField(placeholder, text: text)
            .focused($focus, equals: field)
            .submitLabel(.done)
            .autocorrectionDisabled()
            .onChange(of: text.wrappedValue) { _, v in
                if v.count > limit { text.wrappedValue = String(v.prefix(limit)) }
            }
            .font(Ty.title3.font.weight(.regular)) // 比一般輸入框大一級，越過 domyField 的字級
            .domyField(focused: focus == field)
    }

    /// 同原型 warnFor：否定句、太長、飲食體重
    @ViewBuilder
    private func warnings(floor fv: String, trigger tv: String) -> some View {
        let neg = Wording.isNegative(fv)
        let long = !neg && fv.count > 20
        let food = Wording.isFood(fv + tv)
        if neg || long || food {
            WarnBox {
                if neg { Text(Wording.negativeWarning) }
                else if long { Text(Wording.tooLongWarning) }
                if food {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Wording.foodWarning)
                        DomyButton("看說明", variant: .plain, size: .compact) { showUnfit = true }
                    }
                }
            }
        }
    }
}

/// 第幾步：兩段細條＋一行字
struct StepBar: View {
    var step: Int
    var total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.s2) {
            HStack(spacing: Sp.s1) {
                ForEach(1...total, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Theme.accent : Theme.surfaceMuted)
                        .frame(height: Sp.s1)
                }
            }
            Text("第 \(step) 步，共 \(total) 步")
                .domyType(Ty.footnote)
                .foregroundStyle(Theme.fg2)
        }
        .accessibilityElement(children: .combine)
    }
}
