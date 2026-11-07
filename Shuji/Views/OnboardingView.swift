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
    @FocusState private var focus: Field?

    enum Field { case floor, trigger }

    private var floorValue: String { floor.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var triggerValue: String { trigger.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if step == 1 { stepOne } else { stepTwo }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 560)
            .padding(.top, 44)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if floor.isEmpty { floor = store.state.queue.first ?? "" }
        }
        .sheet(isPresented: $showUnfit) { UnfitSheet() }
        .sheet(isPresented: $showRestore) { RestoreSheet() }
    }

    // MARK: 第 1 步

    private var stepOne: some View {
        Group {
            BigTitle(title: "種一個習慣", sub: "一次只種一個，長好了再種下一個。")
            VStack(alignment: .leading, spacing: 14) {
                stepLine(1)
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("每天想多做的事，最小的那一步是？").font(.footnote).foregroundStyle(Theme.fg2)
                        bigInput("打開檔案寫一句", text: $floor, limit: 40, field: .floor)
                            .onSubmit { if canGoNext { goNext() } }
                        if !store.state.queue.isEmpty {
                            Text("排隊中").font(.footnote).foregroundStyle(Theme.fg2).padding(.top, 12)
                            ChipFlow(items: store.state.queue, accent: true) { floor = $0 }
                            Text("或從這些開始").font(.footnote).foregroundStyle(Theme.fg2).padding(.top, 12)
                        }
                        ChipFlow(items: Phrases.floorExamples) { floor = $0 }
                            .padding(.top, store.state.queue.isEmpty ? 10 : 0)
                        Text("小到最糟的一天也做得到，兩分鐘內做完。").font(.footnote).foregroundStyle(Theme.fg2).padding(.top, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 18, leading: 18, bottom: 20, trailing: 18))
                }
                warnings(floor: floorValue, trigger: "")
                PrimaryButton(title: "下一步") { goNext() }
                    .disabled(!canGoNext)
                    .opacity(canGoNext ? 1 : 0.35)
                HStack {
                    Spacer()
                    LinkButton(title: "從備份還原", quiet: true) { showRestore = true }
                    Spacer()
                }
            }
        }
    }

    private var canGoNext: Bool { !floorValue.isEmpty && !Wording.isNegative(floorValue) }

    private func goNext() {
        step = 2
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focus = .trigger }
    }

    // MARK: 第 2 步

    private var stepTwo: some View {
        Group {
            BigTitle(title: "掛在哪裡", sub: "找一個每天一定會發生的瞬間。")
            VStack(alignment: .leading, spacing: 14) {
                stepLine(2)
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("「\(floorValue)」要接在每天哪個瞬間後面？").font(.footnote).foregroundStyle(Theme.fg2)
                        bigInput("起床喝完第一杯水", text: $trigger, limit: 30, field: .trigger)
                            .onSubmit { if !triggerValue.isEmpty { plant() } }
                        ChipFlow(items: Phrases.triggerExamples) { trigger = $0 }
                            .padding(.top, 10)
                        Text("一個瞬間，不是一段時間。「早上有空時」不算，「刷完牙」算。")
                            .font(.footnote).foregroundStyle(Theme.fg2).padding(.top, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 18, leading: 18, bottom: 20, trailing: 18))
                }
                SwitchCard(trigger: triggerValue.isEmpty ? "＿＿" : triggerValue, floor: floorValue)
                if Wording.isFood(triggerValue) && !Wording.isFood(floorValue) {
                    warnings(floor: "", trigger: triggerValue)
                }
                PrimaryButton(title: "種下去") { plant() }
                    .disabled(triggerValue.isEmpty)
                    .opacity(triggerValue.isEmpty ? 0.35 : 1)
                HStack {
                    Spacer()
                    LinkButton(title: "‹ 改最小一步", quiet: true) { step = 1 }
                    Spacer()
                }
            }
        }
    }

    private func plant() {
        guard !floorValue.isEmpty, !triggerValue.isEmpty else { return }
        focus = nil
        store.plant(floor: floorValue, trigger: triggerValue)
    }

    // MARK: 零件

    private func stepLine(_ n: Int) -> some View {
        Text("第 \(n) 步，共 2 步")
            .font(.footnote)
            .foregroundStyle(Theme.fg2)
            .padding(.leading, 2)
            .padding(.bottom, -6)
    }

    private func bigInput(_ placeholder: String, text: Binding<String>, limit: Int, field: Field) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 20))
            .padding(14)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .focused($focus, equals: field)
            .submitLabel(.done)
            .autocorrectionDisabled()
            .onChange(of: text.wrappedValue) { _, v in
                if v.count > limit { text.wrappedValue = String(v.prefix(limit)) }
            }
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
                    HStack(spacing: 6) {
                        Text(Wording.foodWarning)
                        Button("看說明") { showUnfit = true }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.top, (neg || long) ? 10 : 0)
                }
            }
        }
    }
}
