import SwiftUI

@main
struct ShujiApp: App {
    @State private var store: Store = {
        let s = Store()
        s.onSaved = { state, today in
            CheckNotification.reschedule(state: state, today: today)
        }
        Store.live = s
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
