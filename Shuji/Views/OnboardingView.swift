import SwiftUI

/// 還沒種的時候：一打開就是跟地瓜對答
struct OnboardingView: View {
    @Environment(Store.self) private var store
    @State private var showRestore = false

    var body: some View {
        PlantFlow(prefill: store.state.queue.first ?? "", onRestore: { showRestore = true })
            .sheet(isPresented: $showRestore) { RestoreSheet() }
    }
}

/// 種一個：跟地瓜對答，隨時可以改成自己填。首次設定和重新規劃共用
struct PlantFlow: View {
    /// 先填在第一步的字（排隊的第一個）
    var prefill: String = ""
    var onExit: (() -> Void)? = nil
    var onRestore: (() -> Void)? = nil
    var onDone: () -> Void = {}
    @State private var model = TalkModel()
    @State private var manual = false
    @State private var loaded = false

    var body: some View {
        Group {
            if manual {
                ManualPlantView(floor: model.floor.isEmpty ? prefill : model.floor, trigger: model.trigger,
                                step: model.floor.isEmpty ? 1 : 2,
                                onBack: { manual = false }, onRestore: onRestore, onDone: onDone)
            } else {
                TalkView(model: model, onExit: onExit, onManual: { manual = true }, onRestore: onRestore, onDone: onDone)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            #if DEBUG
            let demo = UserDefaults.standard.integer(forKey: "talkDemo")
            if demo > 0, onExit == nil {
                model = TalkModel.demo(demo)
                return
            }
            #endif
            if model.draft.isEmpty { model.draft = prefill }
        }
    }
}

/// 設定的「重新規劃習慣」：整頁蓋上來，種下去就回今天
struct ReplanView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlantFlow(onExit: { dismiss() }, onDone: {
            store.page = 1
            dismiss()
        })
        .background(Theme.canvas.ignoresSafeArea())
        .environment(\.domyBottomInset, Sp.s8)
        .tint(Theme.accent)
    }
}

/// 今天頁切換選單的「加一個習慣」：整頁蓋上來，種下去時現在養的那些都留著，新的變成現在看的
struct AddHabitView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlantFlow(onExit: { dismiss() }, onDone: {
            store.page = 1
            dismiss()
        })
        .background(Theme.canvas.ignoresSafeArea())
        .environment(\.domyBottomInset, Sp.s8)
        .tint(Theme.accent)
        .onAppear { store.addingHabit = true }
        .onDisappear { store.addingHabit = false }
    }
}

/// 自己填：最小一步、掛在哪個瞬間後面，兩格。預估天數當中等難度
struct ManualPlantView: View {
    @Environment(Store.self) private var store
    private let onBack: () -> Void
    private let onRestore: (() -> Void)?
    private let onDone: () -> Void
    @State private var step: Int
    @State private var floor: String
    @State private var trigger: String
    @State private var showUnfit = false
    /// 種下去助手給的開關候選，第 2 步用來取代預設的範例
    @State private var aiTriggers: [String] = []
    /// 種下去助手判斷不適合（轉介），改了最小一步才放行
    @State private var blocked = false
    @FocusState private var focus: Field?

    enum Field { case floor, trigger }

    init(floor: String, trigger: String, step: Int, onBack: @escaping () -> Void,
         onRestore: (() -> Void)?, onDone: @escaping () -> Void) {
        self.onBack = onBack
        self.onRestore = onRestore
        self.onDone = onDone
        _step = State(initialValue: step)
        _floor = State(initialValue: floor)
        _trigger = State(initialValue: trigger)
    }

    private var floorValue: String { floor.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var triggerValue: String { trigger.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if step == 1 { stepOne } else { stepTwo }
        }
        .sheet(isPresented: $showUnfit) { UnfitSheet() }
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
                DomyButton("‹ 回去問地瓜", variant: .quiet, size: .compact) { onBack() }
                if let onRestore {
                    DomyButton("從備份還原", variant: .quiet, size: .compact) { onRestore() }
                }
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
        Haptic.bloom()
        store.plant(floor: floorValue, trigger: triggerValue, estimatedDays: HabitDifficulty.medium.days)
        onDone()
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
                        .fill(i <= step ? Theme.leafDynamic : Theme.surfaceMuted)
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
