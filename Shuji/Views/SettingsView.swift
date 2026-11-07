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

    private var habit: Habit? { store.state.habit }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    BigTitle(title: "設定")
                    switchSection
                    travelSection
                    rhythmSection
                    reminderSection
                    dataSection
                    Card {
                        RowButton(text: "什麼時候不適合用這個 app") { showUnfit = true }
                    }
                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 560)
                .padding(.top, 44)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
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
        .confirmationDialog("全部清除？", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("清除全部，不可復原", role: .destructive) { store.wipe() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("藤、竹籃、排隊、設定都會刪掉。先匯出備份比較穩。")
        } // 只有 Debug 測試區按得到；正式版照原型，不給清
    }

    // MARK: 開關句

    private var switchSection: some View {
        Group {
            SectionTitle("開關句")
            Card {
                CommitField(label: "如果（每天一定會發生的瞬間）", placeholder: "", value: habit?.trigger ?? "",
                            limit: 30, enabled: habit != nil, focus: $focus, tag: .trigger) { v in
                    if v.isEmpty { return false }
                    store.updateHabit { $0.trigger = v }
                    return true
                }
                .id(SettingsTarget.trigger)
                RowSep()
                CommitField(label: "我就（最小一步）", placeholder: "", value: habit?.floor ?? "",
                            limit: 40, enabled: habit != nil, focus: $focus, tag: .floor) { v in
                    if v.isEmpty || Wording.isNegative(v) {
                        showNegWarning = true
                        return false
                    }
                    showNegWarning = false
                    store.updateHabit { $0.floor = v }
                    return true
                }
                .id(SettingsTarget.floor)
                RowSep()
                CommitField(label: "不順的時候（選填）：主開關沒出現、或有東西擋著，改做什麼",
                            placeholder: "早上要出門，就在捷運上用手機寫三行",
                            value: habit?.backup ?? "", limit: 60, enabled: habit != nil, focus: $focus, tag: .backup) { v in
                    store.updateHabit { $0.backup = v }
                    return true
                }
            }
            if showNegWarning {
                Foot("「就」後面要放一個做得出來的動作。")
            }
            Card {
                CommitField(label: "這件事為了什麼（選填）", placeholder: "", value: habit?.why ?? "",
                            limit: 60, enabled: habit != nil, focus: $focus, tag: .why) { v in
                    store.updateHabit { $0.why = v }
                    return true
                }
            }
        }
    }

    // MARK: 旅行中

    private var travelSection: some View {
        Group {
            SectionTitle("旅行中")
            Card {
                HStack {
                    Text("旅行中")
                    Spacer()
                    Toggle("旅行中", isOn: Binding(get: { store.state.travel }, set: { store.setTravel($0) }))
                        .labelsHidden()
                        .disabled(habit == nil)
                }
                .padding(.horizontal, Theme.rowInset)
                .frame(minHeight: Theme.rowHeight)
                RowSep()
                CommitField(label: "旅行版最小一步", placeholder: "在手機上寫三行", value: habit?.travelFloor ?? "",
                            limit: 40, enabled: habit != nil, focus: $focus, tag: .travelFloor) { v in
                    store.updateHabit { $0.travelFloor = v }
                    return true
                }
            }
            Foot("帶得走的照做最小一步，藤照長。回家第一天會提醒你把東西擺回原位。")
        }
    }

    // MARK: 節奏

    private var rhythmSection: some View {
        Group {
            SectionTitle("節奏")
            Card {
                HStack {
                    Text("每月請假")
                    Spacer()
                    Picker("每月請假", selection: Binding(get: { store.state.settings.leave },
                                                      set: { v in store.updateSettings { $0.leave = v } })) {
                        ForEach(0..<4, id: \.self) { n in Text("\(n)").tag(n) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                .padding(.horizontal, Theme.rowInset)
                .frame(minHeight: Theme.rowHeight)
                RowSep()
                VStack(alignment: .leading, spacing: 10) {
                    Text("週回顧日")
                    Picker("週回顧日", selection: Binding(get: { store.state.settings.reviewDay },
                                                     set: { v in store.updateSettings { $0.reviewDay = v } })) {
                        ForEach(0..<7, id: \.self) { i in Text(DayKey.weekNames[i]).tag(i) }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.rowInset)
                .padding(.vertical, 12)
            }
            Foot("凌晨四點換日：過了午夜才記的那一節，還是算前一天。")
        }
    }

    // MARK: 提醒

    private var reminderSection: some View {
        Group {
            SectionTitle("提醒")
            Card {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("收工檢查")
                        Text("一天最多一則，記了就不會響。預設關閉，開關要在生活裡，不在手機裡。")
                            .font(.footnote).foregroundStyle(Theme.fg2)
                    }
                    Spacer(minLength: 0)
                    Toggle("收工檢查", isOn: Binding(get: { store.state.settings.check }, set: { setCheck($0) }))
                        .labelsHidden()
                }
                .padding(.horizontal, Theme.rowInset)
                .padding(.vertical, 12)
                if store.state.settings.check {
                    RowSep()
                    HStack {
                        Text("時間")
                        Spacer()
                        DatePicker("時間", selection: checkTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .padding(.horizontal, Theme.rowInset)
                    .frame(minHeight: Theme.rowHeight)
                }
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

    // MARK: 資料

    private var dataSection: some View {
        Group {
            SectionTitle("資料")
            Card {
                RowButton(text: "匯出備份") { showExport = true }
                RowSep()
                RowButton(text: "從備份還原") { showRestore = true }
            }
            Foot("資料存在這支手機裡，會跟著 iPhone 的 iCloud 備份走。換手機前自己匯出一份比較穩。")
        }
    }

    // MARK: 測試區（正式版沒有）

    #if DEBUG
    private var debugSection: some View {
        Group {
            SectionTitle("測試區")
            Card {
                RowLabel(text: "現在是", mini: store.today.long + (store.state.dayOffset != 0 ? "（往後 \(store.state.dayOffset) 天）" : ""))
                RowSep()
                RowButton(text: "往後一天", chevron: false, color: Theme.accent) { store.advance(days: 1) }
                RowSep()
                RowButton(text: "往後一週（不記）", chevron: false, color: Theme.accent) { store.advance(days: 7) }
                RowSep()
                RowButton(text: "回到真正的今天", chevron: false, color: Theme.accent) { store.resetOffset() }
                RowSep()
                RowButton(text: "載入示範資料（會蓋掉目前的）", chevron: false, color: Theme.accent) { store.loadDemo() }
                RowSep()
                RowButton(text: "全部清除", chevron: false, color: Theme.danger) { confirmWipe = true }
            }
            Foot("原型專用。正式版沒有這一區，也沒有全部清除。")
        }
    }
    #endif
}

/// 一個「標籤在上、文字在下」的欄位，離開或按完成才交出去。onCommit 回 false 代表退回原值。
struct CommitField: View {
    var label: String
    var placeholder: String
    var value: String
    var limit: Int
    var enabled: Bool
    var focus: FocusState<SettingsTarget?>.Binding
    var tag: SettingsTarget
    var onCommit: (String) -> Bool

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(Theme.fg2)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.rowInset)
        .padding(.vertical, 12)
        .opacity(enabled ? 1 : 0.5)
        .onAppear { text = value }
        .onChange(of: value) { _, v in text = v }
    }

    private func commit() {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !onCommit(v) { text = value }
    }
}
