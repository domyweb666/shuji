import SwiftUI

/// 回來卡：打開 app 發現有空的日子，只跳一張。
/// 只有昨天：先問有沒有做。兩天以上：你回來了，那幾天是？
/// 收掉就當作不說，同一段不再問。
struct BackSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// 打開那一刻的那一段。答完之後 pendingGap 就空了，所以要留著
    @State private var gap: PendingGap
    @State private var asking: Bool
    @State private var answered = false

    private static let potato: CGFloat = 108 // domy-ignore: 插畫尺寸

    init(gap: PendingGap) {
        _gap = State(initialValue: gap)
        _asking = State(initialValue: gap.onlyYesterday)
    }

    var body: some View {
        SheetFrame(fit: true) {
            VStack(spacing: Sp.s5) {
                if asking {
                    question
                } else {
                    reasons
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onDisappear {
            if !answered { store.closeGap(gap, reason: "") }
        }
    }

    @ViewBuilder
    private var question: some View {
        title("昨天有做嗎？")
            .padding(.top, Sp.s3)
        HStack(spacing: Sp.s3) {
            DomyButton("沒做", variant: .secondary) {
                withAnimation(Feel.transition) { asking = false }
            }
            DomyButton("有做") {
                answered = true
                Haptic.select()
                store.backfill(day: gap.to)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var reasons: some View {
        TalkPotato(width: BackSheet.potato)
            .padding(.top, Sp.s3)
        if !gap.onlyYesterday { title("你回來了") }
        SkipPicker(title: gap.onlyYesterday ? "昨天是？" : "那幾天是？", quiet: "不說") { reason in
            answered = true
            Haptic.select()
            store.closeGap(gap, reason: reason)
            dismiss()
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .domyType(Ty.title1)
            .foregroundStyle(Theme.fg)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 停了一陣子、今天接上之後：上次卡在哪
struct StuckSheet: View {
    enum Choice { case trigger, floor, tips, diagnose }

    var pick: (Choice) -> Void

    var body: some View {
        SheetFrame(fit: true) {
            SheetTitle("上次卡在哪？")
            Card {
                RowButton(text: "那個時機沒出現") { pick(.trigger) }
                RowSep()
                RowButton(text: "最小一步太大") { pick(.floor) }
                RowSep()
                RowButton(text: "旁邊有更近的東西搶走了") { pick(.tips) }
            }
            if AIClient.shared.isAvailable {
                DomyButton("回答三題，幫我找哪裡要改", variant: .plain, size: .compact, fullWidth: true) { pick(.diagnose) }
            }
        }
    }
}
