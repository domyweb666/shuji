import SwiftUI

/// 三頁橫排：田｜今天｜設定。上面一排小點可以點。還沒種的時候只有首次設定這一頁。
struct RootView: View {
    @Environment(Store.self) private var store
    private static let minute = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var store = store
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            if store.state.habit == nil {
                OnboardingView()
                    .transition(.opacity)
            } else {
                TabView(selection: $store.page) {
                    FieldView().tag(0)
                    TodayView().tag(1)
                    SettingsView().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                PageDots(page: $store.page)
                    .padding(.top, 6)
            }
        }
        .overlay(alignment: .bottom) {
            if let text = store.toast {
                ToastView(text: text)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.toast)
        .animation(.easeInOut(duration: 0.3), value: store.state.habit == nil)
        .onReceive(RootView.minute) { _ in store.refreshToday() }
    }
}

struct PageDots: View {
    @Binding var page: Int
    private static let labels = ["田", "今天", "設定"]
    private var labels: [String] { PageDots.labels }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                Button {
                    withAnimation(.easeInOut(duration: 0.38)) { page = i }
                } label: {
                    Circle()
                        .fill(i == page ? Theme.fg : Theme.fg3)
                        .frame(width: 7, height: 7)
                        .scaleEffect(i == page ? 1.1 : 1)
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(labels[i])
                .accessibilityAddTraits(i == page ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("頁面")
    }
}
