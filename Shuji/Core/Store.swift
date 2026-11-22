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
/// 存檔是 Application Support/Shuji/state.json（v2，.analytics/04-資料結構.md）。
/// 每個動作都是「加一筆紀錄」：撤銷是標記，挖地瓜不清紀錄，改開關句留一筆改版。
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
    /// 從這週的田過去改設定時，下一次存下去的改版記成「從這週的田」
    var pendingVia: HabitChange.Via? = nil
    private(set) var tick = 0

    let now: () -> Date
    let timeZone: () -> TimeZone
    private let fileURL: URL?
    /// 自動備份檔放哪（挖地瓜、還原之前會寫一份）。預設是 Documents，檔案 app 看得到。
    private let backupDir: URL?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored var onSaved: ((AppState, DayKey) -> Void)?
    /// 編號產生器（測試時換成固定的）
    @ObservationIgnored var makeID: (String) -> String = { "\($0)-\(UUID().uuidString)" }

    init(now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { TimeZone.current },
         fileURL: URL? = Store.defaultFileURL(),
         backupDir: URL? = Store.defaultBackupDir()) {
        self.now = now
        self.timeZone = timeZone
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
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone()
        return DayKey.today(now: now(), offset: state.dayOffset, calendar: cal)
    }

    /// 回到前景、或過了凌晨四點時叫一下，畫面會重算「今天」
    func refreshToday() { tick &+= 1 }

    /// 這一刻的世界標準時間與時區
    private func stamp() -> (at: String, tz: String) {
        (Stamp.string(now()), timeZone().identifier)
    }

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
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        guard let data = try? e.encode(state) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// 貼原型匯出的那段文字，或這個 app 匯出的（v1、v2 都可以）。要有 logs 或 records 才算。
    /// 蓋掉之前先自動寫一份「還原前」的備份。
    @discardableResult
    func importJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["logs"] != nil || obj["records"] != nil,
              let s = try? JSONDecoder().decode(AppState.self, from: data) else { return false }
        if state.habit != nil || !state.records.isEmpty { writeBackup(tag: "還原前") }
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
        let st = stamp()
        if let old = state.habit, !state.pastHabits.contains(where: { $0.id == old.id }) {
            state.pastHabits.append(old)
        }
        state.habit = Habit(floor: floor, trigger: trigger, planted: t, id: makeID("hab"), plantedAt: st.at, tz: st.tz)
        if let i = state.queue.firstIndex(of: floor) { state.queue.remove(at: i) }
        save()
        show("種下去了。做完最小一步，就按住。")
    }

    // MARK: 記

    private func addRecord(_ kind: LogKind, day: DayKey, source: RecordSource, reason: String? = nil) {
        guard let h = state.habit else { return }
        let st = stamp()
        state.records.append(DayRecord(id: makeID("rec"), habit: h.id, kind: kind, day: day,
                                       at: st.at, tz: st.tz, source: source, reason: reason))
    }

    /// 回傳這一節是不是「回來」（要開花）
    @discardableResult
    func logToday(source: RecordSource = .hold) -> Bool {
        let t = today
        guard state.habit != nil, state.log(on: t) == nil else { return false }
        addRecord(.done, day: t, source: source)
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
        addRecord(.done, day: today.adding(-1), source: .backfill)
        vineGrow = false
        save()
        show("昨天那一節補上了。")
    }

    func leaveToday(reason: String) {
        let t = today
        guard state.log(on: t) == nil, state.stats(today: t).leaveLeft > 0 else { return }
        addRecord(.leave, day: t, source: .hold, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
        save()
    }

    /// 撤銷今天：標記，不刪（原則 3）
    func undoToday() {
        guard let h = state.habit else { return }
        let t = today
        let at = stamp().at
        for i in state.records.indices where state.records[i].habit == h.id && state.records[i].day == t && state.records[i].isActive {
            state.records[i].deletedAt = at
        }
        save()
    }

    /// 上一次請假寫的原因
    var lastLeaveReason: String? {
        let leaves = state.activeRecords.filter { $0.kind == .leave }.sorted { $0.day < $1.day }
        guard let r = leaves.last?.reason, !r.isEmpty else { return nil }
        return r
    }

    /// 捷徑「記一節」回給 Siri 的那一句（跟畫面上的狀態機同一個順序）
    func shortcutLog() -> String {
        let s = state
        let t = today
        guard let h = s.habit else { return "還沒種東西。先打開薯記種一個。" }
        if s.justDug != nil { return "剛挖出來了。先打開薯記種下一個。" }
        if s.letgo != nil { return "放手測試中，照常做就好，不用記。" }
        if let log = s.log(on: t) {
            return log.t == .leave ? "今天請假了。" : "今天已經記過了。"
        }
        let isReturn = logToday(source: .shortcut)
        let n = state.stats(today: t).nodes
        return GlanceCopy.t(isReturn ? .siriReturn : .siriDone, ["floor": h.floor, "n": "\(n)"])
    }

    // MARK: 開始四問、訊號

    func recordReview(scores: [Double]) {
        guard let h = state.habit else { return }
        let st = stamp()
        state.reviews.append(WeeklyReview(date: today, scores: scores, id: makeID("rev"), habit: h.id, at: st.at, tz: st.tz))
        save()
    }

    private func addMark(_ kind: Mark.Kind, habit: String?, prior: Int? = nil, recalled: Int? = nil, pass: Bool? = nil) {
        let st = stamp()
        state.marks.append(Mark(id: makeID("mark"), habit: habit, kind: kind, day: today, at: st.at, tz: st.tz,
                                prior: prior, recalled: recalled, pass: pass))
    }

    func setPressure(_ v: Bool) {
        guard let h = state.habit else { return }
        addMark(v ? .pressureYes : .pressureNotYet, habit: h.id)
        save()
        if !v { show("等遇到了再回來按。") }
    }

    func startLetGo() {
        guard let h = state.habit else { return }
        addMark(.letgoStart, habit: h.id, prior: state.doneInLast14Days(today: today))
        save()
        show("接下來兩週照常做，不用記。")
    }

    /// 放手兩週到了，憑感覺回想做了幾天。nil 是「記不清楚」：這次不算過
    func finishLetGo(days: Int?) {
        guard let h = state.habit, let lg = state.letgo else { return }
        let pass = days.map { $0 >= lg.prior - 2 } ?? false
        addMark(.letgoEnd, habit: h.id, prior: lg.prior, recalled: days, pass: pass)
        save()
        if days == nil {
            show(Copy.t(.p4unsure))
        } else {
            show(Copy.t(pass ? .p4pass : .p4fail))
        }
        page = 0
    }

    /// 兩週就是兩週，沒有提早結束
    var showLetGoEnd: Bool {
        guard state.letgo != nil else { return false }
        return (state.letgoDaysLeft(today: today) ?? 1) <= 0
    }

    // MARK: 挖

    /// 挖地瓜：地瓜照存當時的數字；習慣搬進 pastHabits；每天的紀錄全部留著（04 邊界 25）
    func dig() {
        let t = today
        guard let h = state.habit else { return }
        writeBackup(tag: "挖地瓜")
        let st = state.stats(today: t)
        let p = Potato(floor: h.floor, trigger: h.trigger, nodes: st.nodes, ret: st.ret,
                       days: DayKey.days(from: h.planted, to: t) + 1, planted: h.planted, dug: t,
                       id: makeID("pot"), habit: h.id)
        state.basket.insert(p, at: 0)
        state.justDug = p
        if !state.pastHabits.contains(where: { $0.id == h.id }) { state.pastHabits.append(h) }
        for i in state.trials.indices where state.trials[i].habit == h.id && state.trials[i].status == .running {
            state.trials[i].status = .stopped
        }
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

    /// 改開關句：每個改到的欄位留一筆改版（原值、新值、從哪裡改）
    func updateHabit(via: HabitChange.Via = .settings, _ change: (inout Habit) -> Void) {
        guard var h = state.habit else { return }
        let before = h
        change(&h)
        state.habit = h
        let source = pendingVia ?? via
        pendingVia = nil
        let st = stamp()
        for f in HabitFieldName.allCases {
            let a = before.value(f), b = h.value(f)
            if a != b {
                state.changes.append(HabitChange(id: makeID("chg"), habit: h.id, field: f, from: a, to: b,
                                                 day: today, at: st.at, tz: st.tz, via: source))
            }
        }
        save()
    }

    func setTravel(_ on: Bool) {
        guard on != state.travel else { return }
        addMark(on ? .travelOn : .travelOff, habit: nil)
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

    // MARK: 這週的田

    /// 打開這週的田：記一筆看過；這週要出的觀察第一次出現時存下來（數字照存）；到期的試兩週把結果照存
    @discardableResult
    func openReport(from: String) -> WeekReport? {
        let t = today
        guard let h = state.habit, var report = state.weekReport(today: t) else { return nil }
        let st = stamp()
        if !state.seen.contains(where: { $0.habit == h.id && $0.week == report.end && $0.from == from }) {
            state.seen.append(ReportSeen(id: makeID("seen"), habit: h.id, week: report.end, at: st.at, tz: st.tz, from: from))
        }
        switch report.observation {
        case .finding(let f) where f.recorded == nil:
            let o = Insight(id: makeID("obs"), habit: h.id, kind: f.kind, week: report.end,
                                shownAt: st.at, tz: st.tz, counts: f.counts, low: f.low, subject: f.subject,
                                metricVersion: MetricVersion.current, shown: true,
                                cause: nil, action: nil, note: nil, trial: nil)
            state.observations.append(o)
        case .trialResult(let r) where r.trial.after == nil:
            if let i = state.trials.firstIndex(where: { $0.id == r.trial.id }) {
                state.trials[i].after = r.after
            }
        default:
            break
        }
        save()
        report = state.weekReport(today: t) ?? report
        return report
    }

    private func updateObservation(_ id: String, _ change: (inout Insight) -> Void) {
        guard let i = state.observations.firstIndex(where: { $0.id == id }) else { return }
        change(&state.observations[i])
        save()
    }

    func answerCause(_ id: String, _ cause: String) {
        updateObservation(id) { $0.cause = cause }
    }

    func answerAction(_ id: String, _ action: String) {
        updateObservation(id) { $0.action = action }
    }

    func answerNote(_ id: String, _ note: String) {
        let v = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updateObservation(id) { $0.note = v.isEmpty ? nil : v }
    }

    /// 她按「好，試試看」：試兩週一筆（照觀察當時那一組的天數當試之前）
    @discardableResult
    func startTrial(from observationID: String) -> Trial? {
        guard let h = state.habit, let o = state.observations.first(where: { $0.id == observationID }),
              o.kind == .weekend, let action = o.action, let low = o.low,
              let before = o.counts[low] else { return nil }
        let t = today
        let trial = Trial(id: makeID("try"), habit: h.id, observation: o.id, kind: o.kind, group: low,
                          change: action, start: t, end: t.adding(Threshold.trialDays), status: .running,
                          before: before, after: nil, conclusion: nil, concludedAt: nil)
        state.trials.append(trial)
        updateObservation(o.id) { $0.trial = trial.id }
        return trial
    }

    /// 試兩週的結論。「再看兩週」：這一筆收掉，接著開一筆新的兩週（不覆寫）
    func concludeTrial(_ id: String, _ conclusion: String) {
        guard let i = state.trials.firstIndex(where: { $0.id == id }) else { return }
        let t = today
        var trial = state.trials[i]
        if trial.after == nil { trial.after = state.trialResult(trial, today: t).after }
        trial.status = .done
        trial.conclusion = conclusion
        trial.concludedAt = stamp().at
        state.trials[i] = trial
        if conclusion == "again" {
            let next = Trial(id: makeID("try"), habit: trial.habit, observation: trial.observation, kind: trial.kind,
                             group: trial.group, change: trial.change, start: t, end: t.adding(Threshold.trialDays),
                             status: .running, before: trial.before, after: nil, conclusion: nil, concludedAt: nil)
            state.trials.append(next)
        }
        save()
    }

    /// 先不試了：不追問、不給結論
    func stopTrial(_ id: String) {
        guard let i = state.trials.firstIndex(where: { $0.id == id }) else { return }
        state.trials[i].status = .stopped
        save()
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

extension Habit {
    func value(_ f: HabitFieldName) -> String {
        switch f {
        case .trigger: return trigger
        case .floor: return floor
        case .backup: return backup
        case .travelFloor: return travelFloor
        case .why: return why
        }
    }
}
