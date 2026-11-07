import SwiftUI

/// 按住一秒半，外圈跑滿就記一節。放開就縮回去。
/// 這是整個 app 唯一的核心動作，刻意要「按住」而不是「點一下」。
struct HoldButton: View {
    var hint: String
    var onComplete: () -> Void

    @GestureState private var pressing = false
    @State private var startTime: Date? = nil
    @State private var releaseTime: Date? = nil
    @State private var releaseProgress: CGFloat = 0
    @State private var resetTask: Task<Void, Never>? = nil

    private static let duration: TimeInterval = 1.5
    private static let resetDuration: TimeInterval = 0.25
    private var duration: TimeInterval { HoldButton.duration }
    private var resetDuration: TimeInterval { HoldButton.resetDuration }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Theme.accentSoft, lineWidth: 6)
                    .padding(3)
                TimelineView(.animation(paused: startTime == nil && releaseTime == nil)) { timeline in
                    Circle()
                        .trim(from: 0, to: progress(at: timeline.date))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(3)
                }
                Circle()
                    .fill(Theme.accent)
                    .padding(12)
                    .overlay {
                        Text("按住")
                            .font(.system(size: 22, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(pressing ? 0.94 : 1)
                    .animation(.easeOut(duration: 0.15), value: pressing)
            }
            .frame(width: 140, height: 140)
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
                .font(.subheadline)
                .foregroundStyle(Theme.fg2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 20)
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
