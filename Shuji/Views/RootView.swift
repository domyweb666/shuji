import SwiftUI
import VeggieKit

/// 三頁：田｜今天｜設定。下面一條懸浮膠囊分頁列，手指也照樣可以左右滑。還沒種的時候只有首次設定這一頁。
struct RootView: View {
    @Environment(Store.self) private var store
    @State private var bottomSafe: CGFloat = 0
    /// 畫面上停在哪一頁，跟 store.page 互相同步
    @State private var shown: Int? = 1
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
                pager(page: page)
            }
        }
        .overlay(alignment: .top) {
            // 捲上去的字不要疊在時間上
            Theme.canvas.frame(height: 0).background(Theme.canvas.ignoresSafeArea(edges: .top)) // domy-ignore: 只借安全區那一條，自己不佔高
        }
        .background {
            // 不算鍵盤，只要手勢條那一段
            GeometryReader { geo in
                Color.clear.onChange(of: geo.safeAreaInsets.bottom, initial: true) { _, v in bottomSafe = v }
            }
            .ignoresSafeArea(.keyboard)
        }
        .overlay(alignment: .bottom) {
            if store.state.habit != nil {
                DomyTabBar(items: RootView.tabs, selection: page)
                    .padding(.bottom, Sz.tabBarBottom)
                    .ignoresSafeArea(.keyboard)
            }
        }
    }

    /// 左右滑的三頁。不用 TabView(.page)：它的頁面只有安全區那麼高，忽略安全區之後內容會上下置中、標題跑掉，
    /// 切深色之後點分頁列也不換頁
    private func pager(page: Binding<Int>) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                pageBox(0, page.wrappedValue) { FieldView() }
                pageBox(1, page.wrappedValue) { TodayView() }
                pageBox(2, page.wrappedValue) { SettingsView() }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $shown)
        // 起始停在中間那頁（今天），不靠 scrollPosition 的起始值
        .defaultScrollAnchor(.center)
        .onAppear { shown = page.wrappedValue }
        .onChange(of: shown) { _, v in
            if let v, v != page.wrappedValue { page.wrappedValue = v }
        }
        .onChange(of: page.wrappedValue) { _, v in
            if shown != v { withAnimation(Feel.transition) { shown = v } }
        }
        .scrollIndicators(.hidden)
        .environment(\.domyBottomInset, Theme.tabBarClearance + bottomSafe)
        // 內容鋪到螢幕最底，土不會在手勢條上面斷掉
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func pageBox<Content: View>(_ tag: Int, _ current: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .containerRelativeFrame(.horizontal)
            .accessibilityHidden(tag != current)
            .id(tag)
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
