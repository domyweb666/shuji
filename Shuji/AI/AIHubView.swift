import SwiftUI

/// AI：從設定推進來的一頁。沒連電腦時只有一顆連線的按鈕；連上之後列 AI 可以幫的事。
struct AIHubView: View {
    @Environment(Store.self) private var store
    @State private var sheet: HubSheet? = nil
    @State private var scanning = false
    @State private var pasting = false
    @State private var draft = ""
    @State private var connecting = false
    @State private var problem: String? = nil
    @FocusState private var typing: Bool
    private let ai = AIClient.shared

    enum HubSheet: String, Identifiable {
        case obstacle, diagnose, next
        var id: String { rawValue }
    }

    private var draftValue: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        DomyScreen {
            if let link = ai.bridge {
                DomySection {
                    RowLabel(text: "已連上", value: link.name)
                        .accessibilityElement(children: .combine)
                    RowSep()
                    RowButton(text: "斷開", chevron: false, tone: .danger) {
                        Haptic.remove()
                        withAnimation(Feel.change) { ai.disconnect() }
                    }
                }
            } else {
                connectSection
            }
            if ai.isAvailable { helpSection }
        }
        .navigationTitle("AI")
        .fullScreenCover(isPresented: $scanning) { scanner }
        .sheet(item: $sheet) { which in
            switch which {
            case .obstacle: ObstacleSheet()
            case .diagnose: DiagnoseSheet()
            case .next: NextHabitSheet()
            }
        }
    }

    // MARK: 連電腦

    private var connectSection: some View {
        VStack(spacing: Sp.s3) {
            DomyButton(connecting ? "連線中⋯" : "連電腦的 Claude", disabled: connecting) {
                problem = nil
                if QRScanner.isAvailable { scanning = true } else { withAnimation(Feel.change) { pasting = true } }
            }
            if pasting {
                HStack(spacing: Sp.s2) {
                    TextField("http://192.168…", text: $draft)
                        .focused($typing)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { if !draftValue.isEmpty { connect(draftValue) } }
                        .domyField(focused: typing, error: problem != nil)
                        .accessibilityLabel("電腦上印的網址")
                    DomyButton("連線", size: .compact, disabled: draftValue.isEmpty || connecting) { connect(draftValue) }
                }
            } else if !connecting {
                DomyButton("貼網址", variant: .quiet, size: .compact) {
                    withAnimation(Feel.change) { pasting = true }
                    typing = true
                }
            }
            if let problem { WarnBox { Text(problem) } }
        }
        .frame(maxWidth: .infinity)
    }

    private var scanner: some View {
        QRScanner { text in
            scanning = false
            connect(text)
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button { scanning = false } label: {
                Image(systemName: "xmark")
                    .font(Ty.headline.font)
                    .foregroundStyle(Theme.fg)
                    .frame(width: Sz.touch, height: Sz.touch)
                    .background(Theme.surface, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(DomyPressStyle())
            .accessibilityLabel("關閉")
            .padding(Sz.screenMargin)
        }
    }

    private func connect(_ raw: String) {
        guard !connecting else { return }
        typing = false
        problem = nil
        connecting = true
        Task {
            defer { connecting = false }
            do {
                let saved = try await ai.connect(raw)
                draft = ""
                pasting = false
                Haptic.bloom()
                if !saved { store.show("這次連上了，關掉 app 要再掃一次。") }
            } catch {
                Haptic.error()
                problem = (error as? AIClient.Failure)?.message ?? AIClient.unreachableMessage
            }
        }
    }

    // MARK: 可以幫的事

    private var helpSection: some View {
        DomySection(title: "AI 可以幫你") {
            RowButton(text: "想不順的時候怎麼辦", disabled: store.state.habit == nil) { sheet = .obstacle }
            RowSep()
            RowButton(text: "找哪裡卡住", disabled: store.state.habit == nil) { sheet = .diagnose }
            RowSep()
            RowButton(text: "想下一個要種什麼") { sheet = .next }
        }
    }
}

/// 用問答想下一個要種什麼，選好放進排隊，不動現在種著的
private struct NextHabitSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GuideView(queueOnly: { plan in
            store.addQueue(String(plan.floor.prefix(40)))
            store.show("排進去了。")
            dismiss()
        }, onManual: { _, _ in }, onRestore: {})
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Rd.xxl)
            .presentationBackground(Theme.canvas)
            .tint(Theme.accent)
    }
}
