import SwiftUI

/// 週回顧：開始四問 → 這週的田（.analytics/06 回顧層、07 字串表、08 T-1 到 T-3）。
/// 時間到了打開 app 自動跳出來（AutoAsk），田裡沒有入口。
/// 這週的田只說現象；有原因的觀察由她選原因、選做法；試兩週由她答應、結論由她下。
struct WeekSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var report: WeekReport? = nil

    var body: some View {
        if let report {
            WeekReportView(report: report, close: { dismiss() }, goField: goField)
        } else {
            ReviewQuestions(onSubmit: submitted, later: { dismiss() })
        }
    }

    private func submitted(_ scores: [Double]) {
        store.recordReview(scores: scores)
        if store.state.settings.weekCard, let r = store.openReport(from: "review") {
            withAnimation(Feel.transition) { report = r }
        } else {
            store.show(Copy.t(.done))
            dismiss()
        }
    }

    private func goField() {
        dismiss()
        withAnimation(Feel.transition) { store.page = 0 }
    }
}

/// 打開 app 自動跳出來的那一張
struct AskSheet: View {
    var ask: AutoAsk
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch ask {
        case .review:
            WeekSheet()
        case .dig:
            AskCard(potato: true, title: "「\(floor)」長好了", yes: "挖地瓜", no: "再種一陣子", onYes: {
                Haptic.bloom()
                dismiss()
                store.route = []
                store.dig()
            }, onNo: { dismiss() })
        case .pressure:
            AskCard(title: "最近有特別忙或累的一週嗎？那週也照做了嗎？", yes: "有，照做了", no: "還沒遇到，或那週掉了", onYes: {
                store.setPressure(true)
                dismiss()
            }, onNo: {
                store.setPressure(false)
                dismiss()
            })
        case .letgo:
            AskCard(title: "試試看，接下來兩週照常做，不用記", yes: "試兩週", no: "先不要", onYes: {
                store.startLetGo()
                dismiss()
            }, onNo: { dismiss() })
        }
    }

    private var floor: String { store.state.habit?.floor ?? "" }
}

/// 一句話、兩顆按鈕
private struct AskCard: View {
    var potato = false
    var title: String
    var yes: String
    var no: String
    var onYes: () -> Void
    var onNo: () -> Void

    var body: some View {
        SheetFrame {
            if potato {
                PotatoView(width: 140) // domy-ignore: 插畫尺寸
                    .frame(maxWidth: .infinity)
                    .padding(.top, Sp.s4)
            }
            Text(title)
                .domyType(Ty.title2)
                .foregroundStyle(Theme.fg)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Sp.s4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Sp.s2) {
                DomyButton(yes) { onYes() }
                DomyButton(no, variant: .secondary) { onNo() }
            }
        }
    }
}

// MARK: - 開始四問

/// 四句自動化量表，一題一頁，點了就到下一題。沒有預設分數
struct ReviewQuestions: View {
    @Environment(Store.self) private var store
    var onSubmit: ([Double]) -> Void
    var later: () -> Void
    @State private var scores: [Int] = [0, 0, 0, 0]
    @State private var step = 0
    /// 點了分數、還沒換到下一題
    @State private var moving = false

    var body: some View {
        let questions = Phrases.reviewQuestions(floor: store.state.habit?.floor ?? "")
        SheetFrame {
            HStack(spacing: Sp.s2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Theme.accent : Theme.surfaceMuted)
                        .frame(height: Sp.s1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("第 \(step + 1) 題，共 4 題")
            HStack {
                if step > 0 {
                    DomyButton("上一題", variant: .quiet, size: .compact) {
                        guard !moving else { return }
                        withAnimation(Feel.transition) { step -= 1 }
                    }
                }
                Spacer(minLength: 0)
                DomyButton("晚點再說", variant: .quiet, size: .compact) { later() }
            }
            Text(questions[step])
                .domyType(Ty.title2)
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Sp.s4)
                .id(step)
                .transition(.opacity)
            VStack(spacing: Sp.s2) {
                ScalePicker(title: questions[step], selection: picked)
                    .accessibilityIdentifier("review-q\(step + 1)")
                HStack {
                    Text("完全不像")
                    Spacer()
                    Text("完全就是")
                }
                .domyType(Ty.footnote)
                .foregroundStyle(Theme.fg2)
                .accessibilityHidden(true)
            }
        }
    }

    private var picked: Binding<Int> {
        Binding(get: { scores[step] }, set: { v in
            guard !moving else { return }
            scores[step] = v
            moving = true
            Task {
                // 讓選到的那顆看得見再換題
                try? await Task.sleep(for: .seconds(0.3))
                moving = false
                if step < 3 {
                    withAnimation(Feel.transition) { step += 1 }
                } else if scores.allSatisfy({ $0 >= 1 }) {
                    onSubmit(scores.map(Double.init))
                }
            }
        })
    }
}

// MARK: - 這週的田

struct WeekReportView: View {
    var report: WeekReport
    var close: () -> Void
    var goField: () -> Void
    @Environment(Store.self) private var store

    var body: some View {
        SheetFrame {
            SheetTitle(Copy.t(.w0))
            SheetNote(Copy.t(.w0s, ["start": report.start.short, "end": report.end.short]))
            Card {
                // 第三行是「長好了嗎」過了幾個訊號，收在後台不給看
                ForEach(Array(report.lines.prefix(2).enumerated()), id: \.offset) { i, line in
                    if i > 0 { RowSep() }
                    Text(line)
                        .domyType(Ty.body)
                        .foregroundStyle(Theme.fg)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Sp.s4)
                        .padding(.vertical, Sp.s3)
                }
            }
            switch report.observation {
            case .trialResult(let r):
                TrialResultCard(result: r)
            case .finding(let f):
                if let id = f.recorded?.id {
                    FindingCard(finding: f, insightID: id, close: close)
                }
            case nil:
                EmptyView()
            }
            VStack(spacing: Sp.s2) {
                DomyButton(Copy.t(.w4ok)) { close() }
                DomyButton(Copy.t(.w4field), variant: .secondary) { goField() }
            }
        }
    }
}

/// 一個觀察：現象 → 原因（她選）→ 做法（依原因列）→ 要不要試兩週
struct FindingCard: View {
    var finding: Finding
    var insightID: String
    var close: () -> Void
    @Environment(Store.self) private var store
    @State private var note = ""
    @State private var noteSaved = false
    @State private var askTrial = false
    @State private var trialReply: String? = nil
    @State private var sheet: Destination? = nil
    @FocusState private var noteFocused: Bool

    enum Destination: String, Identifiable {
        case obstacle, tips
        var id: String { rawValue }
    }

    /// 存起來的那一筆（她答到哪裡，照它畫）
    private var insight: Insight? { store.state.observations.first(where: { $0.id == insightID }) }
    private var cause: String? { insight?.cause ?? finding.previousCause }
    private var action: String? { insight?.action }
    private var group: String { Copy.groupName(finding.low ?? "weekend") }

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.s3) {
            // 突顯只用在這一處：過門檻的那一句
            Text(store.state.findingText(finding))
                .domyType(Ty.body)
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Sp.s4)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Rd.xl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Rd.xl, style: .continuous).strokeBorder(Theme.accent, lineWidth: Sz.hairline * 1.5))
            if let memory = store.state.memoryText(finding) {
                Foot(memory)
            }
            if finding.askCause && insight?.cause == nil {
                causeQuestion
            } else if insight?.cause == "not_this" {
                noteField
            } else if insight?.cause == "not_sure" {
                Foot(Copy.t(.notSure))
            }
            if let c = actionsCause, !Copy.actions(finding.kind, cause: c, low: finding.low).isEmpty, action == nil {
                actionQuestion(c)
            }
            if askTrial {
                trialQuestion
            }
            if let trialReply {
                Foot(trialReply)
            } else if action == "none" {
                Foot(Copy.t(.done))
            }
        }
        .sheet(item: $sheet, onDismiss: { store.pendingVia = nil }) { which in
            switch which {
            case .obstacle: ObstacleSheet()
            case .tips: TipsSheet()
            }
        }
    }

    /// 要列做法的原因：問了原因就照她選的；同一個請假原因不問原因，直接列；上次選過的照上次
    private var actionsCause: String? {
        if finding.kind == .leaveReason { return "repeat" }
        if let c = insight?.cause, c != "unanswered" { return c }
        if !finding.askCause { return finding.previousCause }
        return nil
    }

    private var causeQuestion: some View {
        VStack(alignment: .leading, spacing: Sp.s2) {
            Text(finding.kind == .travel ? Copy.t(.trQ) : Copy.t(.weQ, ["g": group]))
                .domyType(Ty.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.fg)
                .padding(.horizontal, Sp.s1)
            let options = Copy.causes(finding.kind, low: finding.low) + [Copy.Option(code: "unanswered", text: Copy.t(.skip))]
            ChipFlow(items: options.map(\.text), accent: false, selected: nil) { text in
                guard let o = options.first(where: { $0.text == text }) else { return }
                store.answerCause(insightID, o.code)
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: Sp.s2) {
            if noteSaved {
                Foot(Copy.t(.done))
            } else {
                TextField(Copy.t(.noteQ), text: $note)
                    .focused($noteFocused)
                    .submitLabel(.done)
                    .onSubmit { saveNote() }
                    .onChange(of: note) { _, v in if v.count > 60 { note = String(v.prefix(60)) } }
                    .domyField(focused: noteFocused)
                DomyButton(Copy.t(.noteOK), variant: .secondary, size: .compact) { saveNote() }
            }
        }
    }

    private func saveNote() {
        store.answerNote(insightID, note)
        noteSaved = true
        noteFocused = false
    }

    private func actionQuestion(_ c: String) -> some View {
        VStack(alignment: .leading, spacing: Sp.s2) {
            Text(finding.kind == .leaveReason ? Copy.t(.lvAQ) : Copy.t(.aq))
                .domyType(Ty.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.fg)
                .padding(.horizontal, Sp.s1)
            let options = Copy.actions(finding.kind, cause: c, low: finding.low) + [Copy.Option(code: "none", text: Copy.t(.aNone))]
            ChipFlow(items: options.map(\.text), accent: false, selected: nil) { text in
                guard let o = options.first(where: { $0.text == text }) else { return }
                store.answerAction(insightID, o.code)
                if o.code == "none" { return }
                if finding.kind == .weekend {
                    askTrial = true
                } else {
                    go(o.code)
                }
            }
        }
    }

    private var trialEnd: DayKey { store.today.adding(Threshold.trialDays) }

    private var trialQuestion: some View {
        VStack(alignment: .leading, spacing: Sp.s2) {
            Text(Copy.t(.tryQ, ["end": trialEnd.short, "g": group]))
                .domyType(Ty.subheadline)
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Sp.s1)
            HStack(spacing: Sp.s2) {
                DomyButton(Copy.t(.tryYes), size: .compact) {
                    store.startTrial(from: insightID)
                    askTrial = false
                    trialReply = Copy.t(.tryOK, ["end": trialEnd.short])
                    go(action ?? "none")
                }
                DomyButton(Copy.t(.tryNo), variant: .secondary, size: .compact) {
                    askTrial = false
                    go(action ?? "none")
                }
            }
        }
    }

    /// 做法 → 去改的那個地方。改的那一筆記成「從這週的田」
    private func go(_ code: String) {
        switch code {
        case "backup":
            store.pendingVia = .week
            if AIClient.shared.isAvailable {
                sheet = .obstacle
            } else {
                toSettings(.backup)
            }
        case "tips":
            sheet = .tips
        case "trigger":
            toSettings(.trigger)
        case "floor":
            toSettings(.floor)
        default:
            break
        }
    }

    private func toSettings(_ target: SettingsTarget) {
        store.pendingVia = .week
        close()
        withAnimation(Feel.transition) { store.openSentence(target) }
    }
}

/// 試兩週到了：攤天數，結論由她下
struct TrialResultCard: View {
    var result: TrialResult
    @Environment(Store.self) private var store

    private var trial: Trial? { store.state.trials.first(where: { $0.id == result.trial.id }) }

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.s3) {
            VStack(alignment: .leading, spacing: Sp.s2) {
                ForEach(Array(store.state.trialText(result).enumerated()), id: \.offset) { i, line in
                    Text(line)
                        .domyType(i == 0 ? Ty.body : Ty.subheadline)
                        .foregroundStyle(i == 0 ? Theme.fg : Theme.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Sp.s4)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Rd.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Rd.xl, style: .continuous).strokeBorder(Theme.accent, lineWidth: Sz.hairline * 1.5))
            if trial?.status == .running {
                Text(Copy.t(.expQ))
                    .domyType(Ty.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.fg)
                    .padding(.horizontal, Sp.s1)
                let options = [Copy.Option(code: "keep", text: Copy.t(.expKeep)),
                               Copy.Option(code: "no_difference", text: Copy.t(.expSame)),
                               Copy.Option(code: "again", text: Copy.t(.expAgain)),
                               Copy.Option(code: "unanswered", text: Copy.t(.skip))]
                ChipFlow(items: options.map(\.text), accent: false, selected: nil) { text in
                    guard let o = options.first(where: { $0.text == text }) else { return }
                    store.concludeTrial(result.trial.id, o.code)
                }
            } else if trial?.conclusion == "again", let next = store.state.runningTrial {
                Foot(Copy.t(.expAgainOK, ["end": next.end.short]))
            } else {
                Foot(Copy.t(.done))
            }
        }
    }
}
