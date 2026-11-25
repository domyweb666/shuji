import SwiftUI
import UIKit
import VeggieKit

/// 設定（2026-11-25 多米選 A）：四張卡都不放標題，app 專屬 → 一般 → 資料與購買 → 支援與關於 → 頁尾。
/// 列一律是「圖示＋名稱＋右邊的狀態或箭頭」（VeggieKit），不放常駐說明（3-4）。
/// 開關句要打字的欄位收進 SentenceView。
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var sheet: SettingsSheet? = nil
    @State private var confirmWipe = false
    @State private var confirmReplan = false
    @State private var replanning = false
    @State private var restoring = false
    @AppStorage(Appearance.storageKey) private var appearanceCode = Appearance.system.rawValue
    @AppStorage(VeggieHaptics.storageKey) private var hapticsOn = true
    @AppStorage("shuji.ai.devToken") private var devToken = ""
    @AppStorage("shuji.ai.baseURL") private var aiBaseURL = ""
    private let purchases = Purchases.shared
    private let config = VeggieConfig.shuji

    enum SettingsSheet: String, Identifiable {
        case export, restore, paywall, mail
        var id: String { rawValue }
    }

    private var habit: Habit? { store.state.habit }

    var body: some View {
        DomyScreen(title: "設定") {
            habitSection
            generalSection
            dataSection
            supportSection
            #if DEBUG
            debugSection
            #endif
            VeggieFooter(config: config, logo: Image("AppLogo")) { store.show($0) }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .export: ExportSheet()
            case .restore: RestoreSheet()
            case .paywall: PaywallSheet()
            case .mail:
                FeedbackMailView(recipient: config.supportEmail ?? "", feedback: Feedback(config: config)) { sheet = nil }
                    .ignoresSafeArea()
            }
        }
        .alert("重新規劃習慣？", isPresented: $confirmReplan) {
            Button("取消", role: .cancel) {}
            Button("重新規劃") { replanning = true }
        } message: {
            Text("現在這個會收起來，紀錄留著。")
        }
        .fullScreenCover(isPresented: $replanning) { ReplanView() }
        .confirmationDialog("全部清除？", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("清除全部，不可復原", role: .destructive) {
                Haptic.remove()
                store.wipe()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("藤、竹籃、排隊、設定都會刪掉。先匯出備份比較穩。")
        } // 只有 Debug 測試區按得到；正式版照原型，不給清
    }

    // MARK: 列

    private func row<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content().padding(.horizontal, Sp.s4)
    }

    private func pushRow(_ icon: String, _ title: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            row { VeggieRow(icon: icon, title: title, value: value, accessory: .push) }
        }
        .buttonStyle(DomyRowPressStyle())
    }

    private func toggleRow(_ icon: String, _ title: String, isOn: Binding<Bool>) -> some View {
        row { VeggieToggleRow(icon: icon, title: title, isOn: isOn) }
    }

    private func menuRow<V: Hashable>(_ icon: String, _ title: String, options: [V], selection: Binding<V>,
                                      name: @escaping (V) -> String) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { Text(name($0)).tag($0) }
            }
        } label: {
            row { VeggieRow(icon: icon, title: title, value: name(selection.wrappedValue), accessory: .push) }
        }
        .buttonStyle(.plain)
    }

    // MARK: 這個習慣

    private var habitSection: some View {
        DomySection {
            pushRow("text.quote", "我的習慣") { store.route = [.sentence] }
                .disabled(habit == nil)
            RowSep()
            pushRow("arrow.triangle.2.circlepath", "重新規劃習慣") { confirmReplan = true }
                .disabled(habit == nil)
            RowSep()
            pushRow("forward", "跳過的理由", value: "\(store.state.settings.skipReasons.count) 個") { store.route = [.skipReasons] }
            RowSep()
            toggleRow("alarm", "每天提醒", isOn: Binding(get: { store.state.settings.check }, set: { setCheck($0) }))
            if store.state.settings.check {
                RowSep()
                timeRow
            }
            RowSep()
            pushRow("sparkles", "AI", value: AIClient.shared.bridge == nil ? nil : "已連電腦") { store.route = [.ai] }
        }
    }

    private var timeRow: some View {
        row {
            HStack {
                Text("時間").domyType(Ty.body).foregroundStyle(Theme.fg)
                Spacer()
                DatePicker("時間", selection: checkTimeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(Theme.accent)
            }
            .frame(minHeight: Sz.row)
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
            store.setReminder(false)
            return
        }
        Task {
            let ok = await CheckNotification.requestAuthorization()
            if ok {
                store.setReminder(true)
            } else {
                store.setReminder(false)
                store.show("通知沒有開。到 iPhone 的「設定」裡打開薯記的通知。")
            }
        }
    }

    // MARK: 一般

    private var generalSection: some View {
        DomySection {
            menuRow("circle.lefthalf.filled", VeggieText.appearance, options: Appearance.allCases.map(\.rawValue),
                    selection: $appearanceCode,
                    name: { (Appearance(rawValue: $0) ?? .system).title })
                .onChange(of: appearanceCode) { _, _ in Appearance.stored.apply() }
            RowSep()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                row { VeggieRow(icon: "bell", title: VeggieText.notifications, accessory: .external) }
            }
            .buttonStyle(DomyRowPressStyle())
            RowSep()
            toggleRow("iphone.radiowaves.left.and.right", VeggieText.haptics, isOn: $hapticsOn)
        }
    }

    // MARK: 資料與購買

    private var dataSection: some View {
        DomySection {
            pushRow("square.and.arrow.up", VeggieText.exportData) { sheet = .export }
            RowSep()
            pushRow("square.and.arrow.down", VeggieText.importData) { sheet = .restore }
            RowSep()
            pushRow("star.circle", "完整版", value: purchases.isFull ? "已購買" : purchases.product?.displayPrice) { sheet = .paywall }
            RowSep()
            Button { Task { await restore() } } label: {
                row { VeggieRow(icon: "arrow.clockwise", title: VeggieText.restore) }
            }
            .buttonStyle(DomyRowPressStyle())
            .disabled(restoring)
        }
    }

    private func restore() async {
        restoring = true
        defer { restoring = false }
        await purchases.restore()
        purchases.message = nil
        store.show(purchases.owned ? VeggieText.restored : VeggieText.restoreNothing)
    }

    // MARK: 支援與關於

    /// 評分、分享要有 Apple ID 才出現（還沒上架，分享出去也找不到）
    private var supportSection: some View {
        DomySection {
            Button { writeFeedback() } label: {
                row { VeggieRow(icon: "envelope", title: VeggieText.feedback, accessory: .push) }
            }
            .buttonStyle(DomyRowPressStyle())
            if let url = config.writeReviewURL {
                RowSep()
                Link(destination: url) {
                    row { VeggieRow(icon: "star", title: VeggieText.rate, accessory: .external) }
                }
                .buttonStyle(.plain)
                RowSep()
                ShareLink(item: config.shareText) {
                    row { VeggieRow(icon: "square.and.arrow.up", title: VeggieText.share, accessory: .external) }
                }
                .buttonStyle(.plain)
            }
            aboutRows
        }
    }

    @ViewBuilder
    private var aboutRows: some View {
        if !VeggieApp.others(excluding: config.slug).isEmpty {
            RowSep()
            pushRow("square.grid.2x2", VeggieText.family) { store.route = [.family] }
        }
        if let url = config.privacyURL {
            RowSep()
            Link(destination: url) {
                row { VeggieRow(icon: "hand.raised", title: VeggieText.privacy, accessory: .external) }
            }
            .buttonStyle(.plain)
        }
    }

    private func writeFeedback() {
        if Feedback.canUseMailSheet {
            sheet = .mail
            return
        }
        guard let address = config.supportEmail, let url = Feedback(config: config).mailtoURL(to: address) else { return }
        openURL(url) { accepted in
            if !accepted { store.show("這支手機沒有可以寄信的 app") }
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

