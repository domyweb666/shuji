import Foundation
import WidgetKit

/// app 這邊負責把狀態縮成一份快照寫給小工具，然後叫它重畫。
enum WidgetBridge {
    /// 照主畫面狀態機的順序：挖出來了 → 放手測試 → 今天做了 → 今天請假 → 還沒做
    static func snapshot(state: AppState, today t: DayKey, full: Bool = false, now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot.make(state: state, today: t, full: full, now: now)
    }

    static func write(state: AppState, today: DayKey, full: Bool) {
        let snap = snapshot(state: state, today: today, full: full)
        guard snap != WidgetSnapshot.read() else { return }
        if snap.write() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
