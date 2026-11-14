import SwiftUI

@main
struct ShujiApp: App {
    @State private var store: Store = {
        let s = Store()
        s.onSaved = { state, today in
            CheckNotification.reschedule(state: state, today: today)
            WidgetBridge.write(state: state, today: today, full: Purchases.shared.isFull)
        }
        Store.live = s
        // 買了或退款：小工具馬上換畫面
        Purchases.shared.onChange = { full in
            WidgetBridge.write(state: s.state, today: s.today, full: full)
        }
        return s
    }()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // 回到前景重算「今天」（凌晨四點換日），順便把收工檢查排到對的那天
                store.refreshToday()
                CheckNotification.reschedule(state: store.state, today: store.today)
            }
        }
    }
}
