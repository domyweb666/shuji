import Foundation

extension WidgetSnapshot {
    /// 把狀態縮成給小工具看的快照。照主畫面狀態機的順序：挖出來了 → 放手測試 → 今天做了 → 今天請假 → 還沒做
    /// 節數用跟今天頁同一個算法（M2），四處同一個數字。
    static func make(state: AppState, today t: DayKey, full: Bool = false, now: Date = Date()) -> WidgetSnapshot {
        guard let h = state.habit else {
            return WidgetSnapshot(trigger: "", floor: "", nodes: 0, status: .empty, day: t.string, updated: now, full: full)
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
                              status: status, day: t.string, updated: now, full: full)
    }
}
