import SwiftUI

/// 設定。欄位是「離開欄位或按完成才存」，跟原型的 change 事件一樣。
struct SettingsView: View {
    @Environment(Store.self) private var store
    @FocusState private var focus: SettingsTarget?
    @State private var showNegWarning = false
    @State private var showExport = false
    @State private var showRestore = false
    @State private var showUnfit = false
    @State private var confirmWipe = false
    @State private var showObstacle = false
    @State private var showPaywall = false
    @AppStorage("shuji.ai.devToken") private var devToken = ""
    @AppStorage("shuji.ai.baseURL") private var aiBaseURL = ""
    private let purchases = Purchases.shared

    private var habit: Habit? { store.state.habit }

    var body: some View {
        ScrollViewReader { proxy in
            DomyScreen(title: "設定") {
                switchSection
                travelSection
                rhythmSection
                reminderSection
                fullSection
                dataSection
                Card {
                    RowButton(text: "什麼時候不適合用這個 app") { showUnfit = true }
                }
                #if DEBUG
                debugSection
                #endif
            }
            .onChange(of: store.settingsTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focus = target }
                store.settingsTarget = nil
            }
        }
        .sheet(isPresented: $showExport) { ExportSheet() }
        .sheet(isPresented: $showRestore) { RestoreSheet() }
        .sheet(isPresented: $showUnfit) { UnfitSheet() }
        .sheet(isPresented: $showObstacle) { ObstacleSheet() }
        .sheet(isPresented: $showPaywall) { PaywallSheet() }
        .confirmationDialog("全部清除？", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("清除全部，不可復原", role: .destructive) { store.wipe() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("藤、竹籃、排隊、設定都會刪掉。先匯出備份比較穩。")
        } // 只有 Debug 測試區按得到；正式版照原型，不給清
    }

    // MARK: 開關句

    private var switchSection: some View {
        VStack(alignment: .leading, spacing: Sp.s4) {
            SectionTitle("開關句")
            CommitField(label: "如果", helper: "每天一定會發生的瞬間", placeholder: "", value: habit?.trigger ?? "",
                        limit: 30, enabled: habit != nil, focus: $focus, tag: .trigger) { v in
                if v.isEmpty { return false }
                store.updateHabit { $0.trigger = v }
                return true
            }
            .id(SettingsTarget.trigger)
            CommitField(label: "我就", helper: "最小一步", placeholder: "", value: habit?.floor ?? "",
                        limit: 40, enabled: habit != nil, focus: $focus, tag: .floor,
                        error: showNegWarning ? "「就」後面要放一個做得出來的動作。" : nil) { v in
                if v.isEmpty || Wording.isNegative(v) {
                    showNegWarning = true
                    return false
                }
                showNegWarning = false
                store.updateHabit { $0.floor = v }
                return true
            }
            .id(SettingsTarget.floor)
            CommitField(label: "不順的時候（選填）", helper: "主開關沒出現、或有東西擋著，改做什麼",
                        placeholder: "早上要出門，就在捷運上用手機寫三行",
                        value: habit?.backup ?? "", limit: 60, enabled: habit != nil, focus: $focus, tag: .backup) { v in
                store.updateHabit { $0.backup = v }
                return true
            }
            if habit != nil && AIClient.shared.isAvailable {
                DomyButton("幫我想不順的時候怎麼辦", variant: .plain, size: .compact) { showObstacle = true }
            }
            CommitField(label: "這件事為了什麼（選填）", placeholder: "", value: habit?.why ?? "",
                        limit: 60, enabled: habit != nil, focus: $focus, tag: .why) { v in
                store.updateHabit { $0.why = v }
                return true
            }
        }
    }

    // MARK: 旅行中

    private var travelSection: some View {
        VStack(alignment: .leading, spacing: Sp.s4) {
            DomySection(title: "旅行中") {
                DomyToggleRow(label: "旅行中",
                              isOn: Binding(get: { store.state.travel }, set: { store.setTravel($0) }),
                              disabled: habit == nil)
            }
            CommitField(label: "旅行版最小一步", placeholder: "在手機上寫三行", value: habit?.travelFloor ?? "",
                        limit: 40, enabled: habit != nil, focus: $focus, tag: .travelFloor,
                        helper2: "帶得走的照做最小一步，藤照長。回家第一天會提醒你把東西擺回原位。") { v in
                store.updateHabit { $0.travelFloor = v }
                return true
            }
        }
    }

    // MARK: 節奏

    private var rhythmSection: some View {
        DomySection(title: "節奏", footer: "凌晨四點換日：過了午夜才記的那一節，還是算前一天。") {
            DomyPickerRow(label: "每月請假", options: Array(0..<4),
                          selection: Binding(get: { store.state.settings.leave },
                                             set: { v in store.updateSettings { $0.leave = v } }),
                          title: { "\($0) 次" })
            RowSep()
            DomyPickerRow(label: "週回顧日", options: Array(0..<7),
                          selection: Binding(get: { store.state.settings.reviewDay },
                                             set: { v in store.updateSettings { $0.reviewDay = v } }),
                          title: { DayKey.weekNames[$0] })
        }
    }

    // MARK: 提醒

    private var reminderSection: some View {
        DomySection(title: "提醒") {
            DomyToggleRow(label: "收工檢查",
                          mini: "一天最多一則，記了就不會響。預設關閉，開關要在生活裡，不在手機裡。",
                          isOn: Binding(get: { store.state.settings.check }, set: { setCheck($0) }))
            if store.state.settings.check {
                RowSep()
                HStack {
                    Text("時間").domyType(Ty.body).foregroundStyle(Theme.fg)
                    Spacer()
                    DatePicker("時間", selection: checkTimeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(Theme.accent)
                }
                .padding(.horizontal, Sp.s4)
                .frame(minHeight: Sz.row)
            }
        }
    }

    private var checkTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: store.state.settings.checkHour,
                                      minute: store.state.settings.checkMinute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                store.updateSettings {
                    $0.checkHour = c.hour ?? 21
                    $0.checkMinute = c.minute ?? 0
                }
            }
        )
    }

    private func setCheck(_ on: Bool) {
        if !on {
            store.updateSettings { $0.check = false }
            return
        }
        Task {
            let ok = await CheckNotification.requestAuthorization()
            if ok {
                store.updateSettings { $0.check = true }
            } else {
                store.updateSettings { $0.check = false }
                store.show("通知沒有開。到 iPhone 的「設定」裡打開薯記的通知。")
            }
        }
    }

    // MARK: 完整版

    private var fullSection: some View {
        DomySection(title: "完整版", footer: "一次買斷：週回顧建議、季稽核、小工具。其他功能一直免費。") {
            RowButton(text: purchases.isFull ? "完整版已解鎖" : "看看完整版",
                      value: purchases.isFull ? nil : purchases.product?.displayPrice,
                      tone: purchases.isFull ? .normal : .action) { showPaywall = true }
        }
    }

    // MARK: 資料

    private var dataSection: some View {
        DomySection(title: "資料", footer: "資料存在這支手機裡，會跟著 iPhone 的 iCloud 備份走。換手機前自己匯出一份比較穩。") {
            RowButton(text: "匯出備份") { showExport = true }
            RowSep()
            RowButton(text: "從備份還原") { showRestore = true }
        }
    }

    // MARK: 測試區（正式版沒有）

    #if DEBUG
    private var debugSection: some View {
        DomySection(title: "測試區", footer: "原型專用。正式版沒有這一區，也沒有全部清除。") {
            RowLabel(text: "現在是", mini: store.today.long + (store.state.dayOffset != 0 ? "（往後 \(store.state.dayOffset) 天）" : ""))
            RowSep()
            RowButton(text: "往後一天", chevron: false, tone: .action) { store.advance(days: 1) }
            RowSep()
            RowButton(text: "往後一週（不記）", chevron: false, tone: .action) { store.advance(days: 7) }
            RowSep()
            RowButton(text: "回到真正的今天", chevron: false, tone: .action) { store.resetOffset() }
            RowSep()
            RowButton(text: "載入示範資料（會蓋掉目前的）", chevron: false, tone: .action) { store.loadDemo() }
            RowSep()
            RowButton(text: "全部清除", chevron: false, tone: .danger) { confirmWipe = true }
            RowSep()
            DomyToggleRow(label: "假裝買了完整版",
                          isOn: Binding(get: { purchases.debugFull }, set: { purchases.debugFull = $0 }))
            RowSep()
            debugField("AI 伺服器網址（空白用 Info.plist 的）", text: $aiBaseURL)
            RowSep()
            debugField("開發用通行碼（模擬器沒有 App Attest）", text: $devToken)
        }
    }

    private func debugField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Sp.s1) {
            Eyebrow(label)
            TextField("", text: text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(Ty.footnote.textStyle, design: .monospaced))
                .foregroundStyle(Theme.fg)
        }
        .padding(.horizontal, Sp.s4)
        .padding(.vertical, Sp.s3)
    }
    #endif
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
        .onChange(of: value) { _, v in text = v }
    }

    private func commit() {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !onCommit(v) { text = value }
    }
}
