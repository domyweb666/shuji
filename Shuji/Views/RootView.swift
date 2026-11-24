import SwiftUI
import VeggieKit

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
        NavigationStack(path: $store.route) {
            tabs(page: $store.page)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                        .toolbar(.visible, for: .navigationBar)
                        .navigationBarTitleDisplayMode(.inline)
                }
        }
        .overlay(alignment: .bottom) {
            if let text = store.toast {
                ToastView(text: text)
                    .padding(.bottom, store.state.habit == nil || !store.route.isEmpty ? Sp.s8 : Theme.tabBarClearance)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tint(Theme.accent)
        .veggieStyle(.shuji)
        .animation(Feel.transition, value: store.toast)
        .animation(Feel.transition, value: store.state.habit == nil)
        .onReceive(RootView.minute) { _ in store.refreshToday() }
        .onAppear { Appearance.stored.apply() }
    }

    private func tabs(page: Binding<Int>) -> some View {
        ZStack(alignment: .top) {
            Theme.canvas.ignoresSafeArea()
            if store.state.habit == nil {
                OnboardingView()
                    .transition(.opacity)
            } else {
                TabView(selection: page) {
                    FieldView().tag(0)
                    TodayView().tag(1)
                    SettingsView().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .environment(\.domyBottomInset, Theme.tabBarClearance)
                // 內容鋪到螢幕最底，土不會在手勢條上面斷掉
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .overlay(alignment: .bottom) {
            if store.state.habit != nil {
                DomyTabBar(items: RootView.tabs, selection: page)
                    .padding(.bottom, Sz.tabBarBottom)
                    .ignoresSafeArea(.keyboard)
            }
        }
    }
}

/// 推進去的第二層各畫哪一頁
struct RouteView: View {
    var route: Route

    var body: some View {
        switch route {
        case .sentence: SentenceView()
        case .grown: FieldView(part: .grown).navigationTitle("長好了嗎")
        case .weeks: FieldView(part: .weeks).navigationTitle(Copy.t(.d7title))
        case .pattern: FieldView(part: .pattern).navigationTitle(Copy.t(.d8title))
        case .queue: FieldView(part: .queue).navigationTitle("排隊")
        case .basket: FieldView(part: .basket).navigationTitle("竹籃")
        case .family: VeggieFamilyView(config: .shuji)
        }
    }
}
