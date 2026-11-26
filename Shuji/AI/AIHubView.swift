import SwiftUI

/// AI：從設定推進來的一頁，只管連線。AI 幫的忙各自在用得到的時候出現，不列成選單（QC-0011）：
/// 漏掉說了理由 → 想下次怎麼辦；連著沒做 → 找哪裡卡住；放手中 → 想下一個。
struct AIHubView: View {
    @Environment(Store.self) private var store
    @State private var scanning = false
    @State private var pasting = false
    @State private var draft = ""
    @State private var connecting = false
    @State private var problem: String? = nil
    @State private var shopping = false
    @FocusState private var typing: Bool
    private let ai = AIClient.shared

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
            if ai.serverReady {
                DomySection(footer: ai.bridge == nil ? "連電腦的 Claude 就不用點數。" : "連著電腦時不用點數。") {
                    RowButton(text: "AI 點數", value: Credits.shared.balanceText) { shopping = true }
                }
            }
        }
        .navigationTitle("AI")
        .fullScreenCover(isPresented: $scanning) { scanner }
        .sheet(isPresented: $shopping) { CreditsSheet() }
        .task { await Credits.shared.refresh() }
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
}

/// 跟地瓜對答想下一個要種什麼，選好最小一步放進排隊，不動現在種著的
struct NextHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = TalkModel()

    var body: some View {
        TalkView(model: model, queueOnly: true, onExit: { dismiss() }, onDone: { dismiss() })
            .padding(.top, Sp.s3)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Rd.xxl)
            .presentationBackground(Theme.canvas)
            .tint(Theme.accent)
    }
}
