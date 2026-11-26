import Foundation
import WidgetKit

/// app 這邊負責把狀態縮成一份快照寫給小工具，然後叫它重畫。
enum WidgetBridge {
    /// 照主畫面狀態機的順序：挖出來了 → 放手測試 → 今天做了 → 今天請假 → 還沒做
    static func snapshot(state: AppState, today t: DayKey, full: Bool = false, now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot.make(state: state, today: t, full: full, now: now)
    }

    /// 上次寫出去的那份。比對時不看 updated（每次都不一樣），內容一樣就不寫、不叫小工具重畫
    private static var last: WidgetSnapshot?

    static func write(state: AppState, today: DayKey, full: Bool) {
        let snap = snapshot(state: state, today: today, full: full)
        guard let prev = last ?? WidgetSnapshot.read(), sameContent(prev, snap) else {
            if snap.write() {
                last = snap
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }
        last = prev
    }

    private static func sameContent(_ a: WidgetSnapshot, _ b: WidgetSnapshot) -> Bool {
        var a = a
        a.updated = b.updated
        return a == b
    }
}
