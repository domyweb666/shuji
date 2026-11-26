import SwiftUI

@main
struct ShujiApp: App {
    @State private var store: Store = {
        let s = Store.makeLive()
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
                store.settleReminder()
                CheckNotification.reschedule(state: store.state, today: store.today)
            } else if phase == .background {
                // 存檔在背景佇列寫，進背景前等它寫完，被系統收掉也不掉資料
                Store.flush()
            }
        }
    }
}

extension Store {
    /// 開一個接好存檔副作用的 Store（重排收工提醒、寫小工具），並設成 live。
    /// app 啟動和「記一節」捷徑（app 沒在跑時）共用，捷徑記的那一節才會馬上更新小工具和提醒。
    @MainActor
    static func makeLive() -> Store {
        let s = Store()
        s.onSaved = { state, today in
            CheckNotification.reschedule(state: state, today: today)
            WidgetBridge.write(state: state, today: today, full: Purchases.shared.isFull)
        }
        Store.live = s
        return s
    }
}
