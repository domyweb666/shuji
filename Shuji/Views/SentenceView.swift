import SwiftUI

/// 開關句：從設定推進來的一頁。欄位是「離開欄位或按完成才存」，跟原型的 change 事件一樣。
struct SentenceView: View {
    @Environment(Store.self) private var store
    @FocusState private var focus: SettingsTarget?
    @State private var showNegWarning = false
    @State private var showObstacle = false

    private var habit: Habit? { store.state.habit }

    var body: some View {
        ScrollViewReader { proxy in
            DomyScreen {
                field("如果", "每天一定會發生的瞬間", habit?.trigger, 30, .trigger) { v in
                    if v.isEmpty { return false }
                    store.updateHabit { $0.trigger = v }
                    return true
                }
                field("我就", "最小一步", habit?.floor, 40, .floor,
                      error: showNegWarning ? "「就」後面要放一個做得出來的動作。" : nil) { v in
                    if v.isEmpty || Wording.isNegative(v) {
                        showNegWarning = true
                        return false
                    }
                    showNegWarning = false
                    store.updateHabit { $0.floor = v }
                    return true
                }
                VStack(alignment: .leading, spacing: Sp.s2) {
                    field("不順的時候（選填）", "早上要出門，就在捷運上用手機寫三行", habit?.backup, 60, .backup) { v in
                        store.updateHabit { $0.backup = v }
                        return true
                    }
                    if habit != nil && AIClient.shared.isAvailable {
                        DomyButton("幫我想不順的時候怎麼辦", variant: .plain, size: .compact) { showObstacle = true }
                    }
                }
                field("旅行版最小一步（選填）", "在手機上寫三行", habit?.travelFloor, 40, .travelFloor) { v in
                    store.updateHabit { $0.travelFloor = v }
                    return true
                }
                field("這件事為了什麼（選填）", "", habit?.why, 60, .why) { v in
                    store.updateHabit { $0.why = v }
                    return true
                }
                if let trial = store.state.runningTrial, store.today < trial.end {
                    DomySection(footer: Copy.t(.d9, ["change": Copy.changeLabel(trial.change, group: trial.group),
                                                     "date": trial.end.adding(-1).short])) {
                        RowButton(text: Copy.t(.d9stop), chevron: false) { store.stopTrial(trial.id) }
                    }
                }
            }
            .task {
                // 從「卡住了」那幾列過來：等推進的動畫停了，捲到那一格、叫出鍵盤
                guard let target = store.settingsTarget else { return }
                store.settingsTarget = nil
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation { proxy.scrollTo(target, anchor: .center) }
                focus = target
            }
        }
        .navigationTitle("開關句")
        .sheet(isPresented: $showObstacle) { ObstacleSheet() }
        .onDisappear {
            // 從這週的田過來、沒改就離開：之後的改動不算在這週的田。等欄位先存完再清
            DispatchQueue.main.async { store.pendingVia = nil }
        }
    }

    private func field(_ label: String, _ placeholder: String, _ value: String?, _ limit: Int, _ tag: SettingsTarget,
                       error: String? = nil, onCommit: @escaping (String) -> Bool) -> some View {
        CommitField(label: label, placeholder: placeholder, value: value ?? "", limit: limit,
                    enabled: habit != nil, focus: $focus, tag: tag, error: error, onCommit: onCommit)
            .id(tag)
    }
}

/// 一個「標籤在框外、框在下」的欄位，離開或按完成才交出去。onCommit 回 false 代表退回原值。
struct CommitField: View {
    var label: String
    var helper: String? = nil
    var placeholder: String
    var value: String
    var limit: Int
    var enabled: Bool
    var focus: FocusState<SettingsTarget?>.Binding
    var tag: SettingsTarget
    var error: String? = nil
    /// 放在框下面的說明（helper 放在標籤旁邊）
    var helper2: String? = nil
    var onCommit: (String) -> Bool

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Sp.s2) {
                Text(label)
                    .domyType(Ty.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.fg)
                if let helper {
                    Text(helper)
                        .domyType(Ty.footnote)
                        .foregroundStyle(Theme.fg2)
                }
            }
            .padding(.horizontal, Sp.s1)
            TextField(placeholder, text: $text)
                .focused(focus, equals: tag)
                .submitLabel(.done)
                .disabled(!enabled)
                .onSubmit { commit() }
                .onChange(of: text) { _, v in
                    if v.count > limit { text = String(v.prefix(limit)) }
                }
                .onChange(of: focus.wrappedValue) { old, new in
                    if old == tag && new != tag { commit() }
                }
                .domyField(focused: focus.wrappedValue == tag, error: error != nil)
                .accessibilityLabel(label)
                .accessibilityHint(error ?? helper ?? "")
            if let error {
                HStack(alignment: .top, spacing: Sp.s2) {
                    Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                    Text(error).fixedSize(horizontal: false, vertical: true)
                }
                .domyType(Ty.footnote)
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, Sp.s1)
            } else if let helper2 {
                Foot(helper2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(enabled ? 1 : DomyTokens.Motion.pressedOpacity)
        .onAppear { text = value }
        .onDisappear { if focus.wrappedValue == tag { commit() } }
        .onChange(of: value) { _, v in text = v }
    }

    private func commit() {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !onCommit(v) { text = value }
    }
}
