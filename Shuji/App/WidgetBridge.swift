import Foundation
import WidgetKit

/// app 這邊負責把狀態縮成一份快照寫給小工具，然後叫它重畫。
enum WidgetBridge {
    /// 照主畫面狀態機的順序：挖出來了 → 放手測試 → 今天做了 → 今天請假 → 還沒做
    static func snapshot(state: AppState, today t: DayKey, now: Date = Date()) -> WidgetSnapshot {
        guard let h = state.habit else {
            return WidgetSnapshot(trigger: "", floor: "", nodes: 0, status: .empty, day: t.string, updated: now)
        }
        let nodes = state.stats(today: t).nodes
        let status: WidgetSnapshot.Status
        if state.justDug != nil {
            status = .dug
        } else if state.letgo != nil {
            status = .letgo
        } else if let log = state.log(on: t) {
            status = log.t == .leave ? .leave : .done
        } else {
            status = .none
        }
        return WidgetSnapshot(trigger: h.trigger, floor: state.activeFloor, nodes: nodes,
                              status: status, day: t.string, updated: now)
    }

    static func write(state: AppState, today: DayKey) {
        let snap = snapshot(state: state, today: today)
        guard snap != WidgetSnapshot.read() else { return }
        if snap.write() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
