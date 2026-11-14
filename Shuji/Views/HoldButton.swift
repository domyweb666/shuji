import SwiftUI

/// 按住一秒半，外圈跑滿就記一節。放開就縮回去。
/// 這是整個 app 唯一的核心動作，刻意要「按住」而不是「點一下」。
/// 外觀照 Domy 的核心大鈕：待機是亮色底＋深字，按著變產品色實心，外圈跟著跑進度。
struct HoldButton: View {
    var hint: String
    var onComplete: () -> Void

    @GestureState private var pressing = false
    @State private var startTime: Date? = nil
    @State private var releaseTime: Date? = nil
    @State private var releaseProgress: CGFloat = 0
    @State private var resetTask: Task<Void, Never>? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let duration: TimeInterval = 1.5
    private static let resetDuration: TimeInterval = 0.25
    private var duration: TimeInterval { HoldButton.duration }
    private var resetDuration: TimeInterval { HoldButton.resetDuration }
    /// 進度圈比靜止外圈粗一倍，按著的時候看得出在跑
    private var progressWidth: CGFloat { Sz.heroRingWidth * 2 }

    var body: some View {
        VStack(spacing: Sp.s3) {
            ZStack {
                Circle()
                    .strokeBorder(pressing ? Theme.accent.opacity(0.25) : Theme.soft, lineWidth: Sz.heroRingWidth)
                TimelineView(.animation(paused: startTime == nil && releaseTime == nil)) { timeline in
                    Circle()
                        .trim(from: 0, to: progress(at: timeline.date))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: progressWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(progressWidth / 2)
                }
                Circle()
                    .fill(pressing ? Theme.accent : Theme.bright)
                    .frame(width: Sz.heroButton, height: Sz.heroButton)
                    .domyShadow(DomyTokens.Elevation.level2)
                    .overlay {
                        VStack(spacing: Sp.s1) {
                            Image(systemName: pressing ? "hand.tap.fill" : "hand.tap")
                                .font(Ty.title2.font)
                            Text("按住")
                                .domyType(Ty.title2)
                                .tracking(2)
                        }
                        .foregroundStyle(pressing ? Theme.onAccent : Theme.onBright)
                    }
                    .scaleEffect(pressing && !reduceMotion ? DomyTokens.Motion.pressScale : 1)
                    .animation(.easeOut(duration: DomyTokens.Motion.pressDuration), value: pressing)
            }
            .frame(width: Sz.heroRing, height: Sz.heroRing)
            .contentShape(Circle())
            .gesture(
                LongPressGesture(minimumDuration: duration, maximumDistance: 40)
                    .updating($pressing) { value, state, _ in state = value }
                    .onEnded { _ in complete() }
            )
            .onChange(of: pressing) { _, isPressing in
                if isPressing {
                    resetTask?.cancel()
                    releaseTime = nil
                    startTime = Date()
                    Haptic.press()
                    SoundPlayer.shared.prime()
                } else if let s = startTime {
                    // 放開（沒按滿）：外圈從現在的進度縮回去
                    releaseProgress = min(1, CGFloat(Date().timeIntervalSince(s) / duration))
                    releaseTime = Date()
                    startTime = nil
                    scheduleResetEnd()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("按住一秒半，記一節")
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { complete() }

            Text(hint)
                .domyType(Ty.subheadline)
                .foregroundStyle(Theme.fg2)
                .multilineTextAlignment(.center)
                .frame(minHeight: Sp.s5)
        }
    }

    private func progress(at date: Date) -> CGFloat {
        if let s = startTime {
            return min(1, CGFloat(date.timeIntervalSince(s) / duration))
        }
        if let r = releaseTime {
            let k = 1 - min(1, date.timeIntervalSince(r) / resetDuration)
            return releaseProgress * CGFloat(k)
        }
        return 0
    }

    private func scheduleResetEnd() {
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(resetDuration + 0.05))
            guard !Task.isCancelled else { return }
            releaseTime = nil
        }
    }

    private func complete() {
        resetTask?.cancel()
        startTime = nil
        releaseTime = nil
        releaseProgress = 0
        onComplete()
    }
}
