import Foundation
import Observation

/// 設定頁裡要被「卡住了」那幾列捲到的欄位
enum SettingsTarget: Hashable {
    case trigger
    case floor
    case backup
    case why
    case travelFloor
}

/// 整個 app 唯一的狀態容器。動作都在這裡，畫面只負責畫。
/// 存檔是 Application Support/Shuji/state.json，內容跟原型的備份格式相同。
@MainActor
@Observable
final class Store {
    var state: AppState
    /// 0 田、1 今天、2 設定
    var page: Int = 1
    var toast: String? = nil
    /// 剛記了一節，下次畫藤要播長出來的動畫
    var vineGrow = false
    /// 正在跑的那個 Store（給 App Intent 用，讓捷徑記的那一節畫面馬上看得到）
    static weak var live: Store?
    var settingsTarget: SettingsTarget? = nil
    private(set) var tick = 0

    let now: () -> Date
    private let fileURL: URL?
    /// 自動備份檔放哪（挖地瓜那一刻會寫一份）。預設是 Documents，檔案 app 看得到。
    private let backupDir: URL?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored var onSaved: ((AppState, DayKey) -> Void)?

    init(now: @escaping () -> Date = Date.init,
         fileURL: URL? = Store.defaultFileURL(),
         backupDir: URL? = Store.defaultBackupDir()) {
        self.now = now
        self.fileURL = fileURL
        self.backupDir = backupDir
        self.state = Store.load(from: fileURL)
        self.state.migrateFields()
        #if !DEBUG
        self.state.dayOffset = 0
        #endif
    }

    // MARK: 今天

    var today: DayKey {
        _ = tick
        return DayKey.today(now: now(), offset: state.dayOffset)
    }

    /// 回到前景、或過了凌晨四點時叫一下，畫面會重算「今天」
    func refreshToday() { tick &+= 1 }

    // MARK: 存檔

    nonisolated static func defaultFileURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Shuji", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    nonisolated static func defaultBackupDir() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// 寫一份備份檔：薯記備份-<tag>-<日期>.json。回傳寫到哪，失敗回 nil。
    @discardableResult
    func writeBackup(tag: String) -> URL? {
        guard let dir = backupDir, let data = try? JSONEncoder().encode(state) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("薯記備份-\(tag)-\(today.string).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    nonisolated private static func load(from url: URL?) -> AppState {
        guard let url, let data = try? Data(contentsOf: url) else { return AppState() }
        if let s = try? JSONDecoder().decode(AppState.self, from: data) { return s }
        // 讀不出來的檔案改名留著，不要蓋掉
        let broken = url.deletingLastPathComponent()
            .appendingPathComponent("state.broken-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: broken)
        return AppState()
    }

    func save() {
        if let url = fileURL, let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url, options: .atomic)
        }
        onSaved?(state, today)
    }

    func exportJSON() -> String {
        guard let data = try? JSONEncoder().encode(state) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// 貼原型匯出的那段文字，或這個 app 自己匯出的。要有 logs 這個 key 才算。
    @discardableResult
    func importJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["logs"] != nil,
              let s = try? JSONDecoder().decode(AppState.self, from: data) else { return false }
        state = s
        state.migrateFields()
        #if !DEBUG
        state.dayOffset = 0
        #endif
        save()
        show("還原好了。")
        return true
    }

    // MARK: 種

    func plant(floor: String, trigger: String) {
        let t = today
        state.habit = Habit(floor: floor, trigger: trigger, planted: t)
        if let i = state.queue.firstIndex(of: floor) { state.queue.remove(at: i) }
        state.logs = [:]
        state.weekly = []
        state.pressure = nil
        state.letgo = nil
        state.letgoResult = nil
        save()
        show("種下去了。做完最小一步，就按住。")
    }

    // MARK: 記

    /// 回傳這一節是不是「回來」（要開花）
    @discardableResult
    func logToday() -> Bool {
        let t = today
        guard state.habit != nil, state.log(on: t) == nil else { return false }
        state.logs[t.string] = .done
        let ret = state.isReturn(t)
        vineGrow = true
        save()
        return ret
    }

    var canBackfillYesterday: Bool {
        guard let h = state.habit else { return false }
        let y = today.adding(-1)
        return state.log(on: y) == nil && y >= h.planted
    }

    func backfillYesterday() {
        guard canBackfillYesterday else { return }
        state.logs[today.adding(-1).string] = .done
        vineGrow = false
        save()
        show("昨天那一節補上了。")
    }

    func leaveToday(reason: String) {
        let t = today
        guard state.log(on: t) == nil, state.stats(today: t).leaveLeft > 0 else { return }
        state.logs[t.string] = .leave(reason.trimmingCharacters(in: .whitespacesAndNewlines))
        save()
    }

    func undoToday() {
        state.logs[today.string] = nil
        save()
    }

    /// 上一次請假寫的原因
    var lastLeaveReason: String? {
        let keys = state.logs.filter { $0.value.t == .leave }.keys.sorted()
        guard let k = keys.last, let r = state.logs[k]?.reason, !r.isEmpty else { return nil }
        return r
    }

    // MARK: 開始四問、訊號

    func recordReview(scores: [Double]) {
        state.weekly.append(WeeklyReview(date: today, scores: scores))
        save()
        show("記下了。")
    }

    func setPressure(_ v: Bool) {
        state.pressure = v
        save()
        if !v { show("等遇到了再回來按。") }
    }

    func startLetGo() {
        let t = today
        state.letgo = LetGo(start: t, prior: state.doneInLast14Days(today: t))
        save()
        show("接下來兩週照常做，不用記。")
    }

    /// 放手兩週到了，憑感覺回想做了幾天
    func finishLetGo(days: Int) {
        guard let lg = state.letgo else { return }
        let pass = days >= lg.prior - 2
        state.letgoResult = LetGoResult(days: days, prior: lg.prior, pass: pass, start: lg.start, end: today)
        state.letgo = nil
        save()
        show(pass ? "沒有明顯變少。" : "比之前少一些，先繼續記。")
        page = 0
    }

    /// 兩週就是兩週，沒有提早結束
    var showLetGoEnd: Bool {
        guard state.letgo != nil else { return false }
        return (state.letgoDaysLeft(today: today) ?? 1) <= 0
    }

    // MARK: 挖

    func dig() {
        let t = today
        guard let h = state.habit else { return }
        // 資料要歸零了，先留一份
        writeBackup(tag: "挖地瓜")
        let st = state.stats(today: t)
        let p = Potato(floor: h.floor, trigger: h.trigger, nodes: st.nodes, ret: st.ret,
                       days: DayKey.days(from: h.planted, to: t) + 1, planted: h.planted, dug: t)
        state.basket.insert(p, at: 0)
        state.justDug = p
        state.logs = [:]
        state.weekly = []
        state.pressure = nil
        state.letgo = nil
        state.letgoResult = nil
        save()
        page = 1
    }

    /// 挖出來那頁按「種下一個」
    func plantNext() {
        state.justDug = nil
        state.habit = nil
        save()
    }

    // MARK: 排隊

    func addQueue(_ s: String) {
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        state.queue.append(v)
        save()
    }

    func removeQueue(at i: Int) {
        guard state.queue.indices.contains(i) else { return }
        state.queue.remove(at: i)
        save()
    }

    // MARK: 設定

    func updateHabit(_ change: (inout Habit) -> Void) {
        guard var h = state.habit else { return }
        change(&h)
        state.habit = h
        save()
    }

    func setTravel(_ on: Bool) {
        state.travel = on
        if !on { state.travelEndedOn = today }
        save()
    }

    func updateSettings(_ change: (inout Settings) -> Void) {
        change(&state.settings)
        save()
    }

    func wipe() {
        state = AppState()
        save()
        page = 1
    }

    // MARK: 測試區（只有 DEBUG 建置有）

    func advance(days: Int) {
        state.dayOffset += days
        save()
        show("到了" + today.long)
    }

    func resetOffset() {
        state.dayOffset = 0
        save()
    }

    func loadDemo() {
        state = AppState.demo(today: today, settings: state.settings, dayOffset: state.dayOffset)
        save()
        page = 1
        show("載入示範資料：種了 45 天。")
    }

    // MARK: 提示

    func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
