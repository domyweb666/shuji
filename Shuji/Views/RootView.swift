import SwiftUI

/// 三頁：田｜今天｜設定。下面一條懸浮膠囊分頁列，手指也照樣可以左右滑。還沒種的時候只有首次設定這一頁。
struct RootView: View {
    @Environment(Store.self) private var store
    private static let minute = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private static let tabs: [DomyTabBar.Item] = [
        .init(title: "田", icon: "leaf"),
        .init(title: "今天", icon: "sun.max"),
        .init(title: "設定", icon: "gearshape"),
    ]

    var body: some View {
        @Bindable var store = store
        ZStack(alignment: .top) {
            Theme.canvas.ignoresSafeArea()
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
                .environment(\.domyBottomInset, Theme.tabBarClearance)
            }
        }
        .overlay(alignment: .bottom) {
            if store.state.habit != nil {
                DomyTabBar(items: RootView.tabs, selection: $store.page)
                    .padding(.bottom, Sz.tabBarBottom)
                    .ignoresSafeArea(.keyboard)
            }
        }
        .overlay(alignment: .bottom) {
            if let text = store.toast {
                ToastView(text: text)
                    .padding(.bottom, store.state.habit == nil ? Sp.s8 : Theme.tabBarClearance)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tint(Theme.accent)
        .animation(.easeOut(duration: DomyTokens.Motion.transition), value: store.toast)
        .animation(.easeInOut(duration: DomyTokens.Motion.transition), value: store.state.habit == nil)
        .onReceive(RootView.minute) { _ in store.refreshToday() }
    }
}
