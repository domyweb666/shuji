import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 底部彈出卡共用的外框：畫布色、左右 20、區塊之間 16
struct SheetFrame<Content: View>: View {
    /// true：一打開就是整頁，不先停在一半
    var full = false
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Sp.s4) { content }
                .padding(.horizontal, Sz.screenMargin)
                .padding(.top, Sp.s6)
                .padding(.bottom, full ? Sp.s4 : Sp.s8)
                .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(full ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Rd.xxl)
        .presentationBackground(Theme.canvas)
        .tint(Theme.accent)
    }
}

struct SheetTitle: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .domyType(Ty.title2)
            .foregroundStyle(Theme.fg)
            .padding(.horizontal, Sp.s1)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SheetNote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .domyType(Ty.subheadline)
            .foregroundStyle(Theme.fg2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Sp.s1)
    }
}

// MARK: 跳過一次

/// 今天頁的跳過單：不預選理由，也可以不選。昨天忘了記、撤銷今天也在這裡
struct SkipSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var t: DayKey { store.today }
    private var logged: Bool { store.state.log(on: t) != nil }

    var body: some View {
        SheetFrame {
            SheetTitle(logged ? "今天" : "跳過一次")
            if !logged {
                SkipForm(day: t, button: "跳過今天") { dismiss() }
            }
            if logged || store.canBackfillYesterday {
                Card { otherRows }
            }
        }
    }

    @ViewBuilder
    private var otherRows: some View {
        if store.canBackfillYesterday {
            RowButton(text: "昨天做了，忘了記", chevron: false) {
                store.backfillYesterday()
                dismiss()
            }
        }
        if logged && store.canBackfillYesterday { RowSep() }
        if logged {
            RowButton(text: "撤銷今天", chevron: false, tone: .danger) {
                Haptic.remove()
                store.undoToday()
                dismiss()
            }
        }
    }
}

/// 一排理由＋一顆跳過。點一下選，再點一下取消
struct SkipForm: View {
    var day: DayKey
    var button: String
    var done: () -> Void
    @Environment(Store.self) private var store
    @State private var reason: String? = nil

    /// 這個習慣跳過幾次同一個理由（M9，比全部，不只上一次）
    private var sameCount: Int { store.state.leaveReasonCount(reason ?? "", today: day) }

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.s4) {
            if !store.state.settings.skipReasons.isEmpty {
                ChipFlow(items: store.state.settings.skipReasons, selected: reason) { r in
                    Haptic.select()
                    reason = reason == r ? nil : r
                }
            }
            if sameCount > 0 { Foot(Copy.t(.p2, ["k": sameCount + 1])) }
            DomyButton(button) {
                store.skip(day: day, reason: reason ?? "")
                done()
            }
        }
    }
}

/// 設定 → 跳過的理由
struct SkipReasonsView: View {
    @Environment(Store.self) private var store
    @State private var text = ""
    @FocusState private var focused: Bool

    private var reasons: [String] { store.state.settings.skipReasons }

    var body: some View {
        DomyScreen {
            DomySection {
                ForEach(reasons, id: \.self) { r in reasonRow(r) }
                if reasons.count < Settings.maxSkipReasons { addRow }
            }
        }
    }

    private func reasonRow(_ r: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Sp.s3) {
                Text(r).domyType(Ty.body).foregroundStyle(Theme.fg)
                Spacer(minLength: 0)
                DomyButton("移除", variant: .quiet, size: .compact) {
                    Haptic.remove()
                    withAnimation(Feel.change) { store.removeSkipReason(r) }
                }
                .accessibilityLabel("移除 \(r)")
            }
            .padding(.leading, Sp.s4)
            .padding(.trailing, Sp.s2)
            .frame(minHeight: Sz.row)
            RowSep()
        }
    }

    private var addRow: some View {
        HStack(spacing: Sp.s2) {
            TextField("加一個理由", text: $text)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { add() }
                .onChange(of: text) { _, v in
                    if v.count > Settings.maxSkipReasonLength { text = String(v.prefix(Settings.maxSkipReasonLength)) }
                }
                .domyField(focused: focused)
            DomyButton("加入", size: .compact, disabled: text.trimmingCharacters(in: .whitespaces).isEmpty) { add() }
        }
        .padding(Sp.s4)
    }

    private func add() {
        withAnimation(Feel.change) {
            _ = store.addSkipReason(text)
        }
        text = ""
    }
}

// MARK: 月曆點一天

struct DaySheet: View {
    var day: DayKey
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var skipping = false

    private var log: DayLog? { store.state.log(on: day) }
    private var isToday: Bool { day == store.today }

    private var status: String {
        guard let log else {
            if store.state.ledger(today: store.today).isLetGo(day) { return "放手測試" }
            return isToday ? "還沒記" : "沒記"
        }
        if log.t == .done { return "記了" }
        let reason = log.reason ?? ""
        return reason.isEmpty ? "跳過" : "跳過：\(reason)"
    }

    var body: some View {
        SheetFrame {
            SheetTitle(day.long)
            SheetNote(status)
            if store.canEdit(day: day) {
                if skipping {
                    SkipForm(day: day, button: isToday ? "跳過今天" : "那天跳過") { dismiss() }
                } else {
                    Card { actions }
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if log != nil {
            RowButton(text: "撤銷", chevron: false, tone: .danger) {
                Haptic.remove()
                store.undo(day: day)
                dismiss()
            }
        } else {
            // 今天有做要回今天頁按住，這裡不給記
            if !isToday {
                RowButton(text: "那天有做", chevron: false) {
                    store.backfill(day: day)
                    dismiss()
                }
                RowSep()
            }
            RowButton(text: isToday ? "今天跳過" : "那天跳過", chevron: false) {
                withAnimation(Feel.transition) { skipping = true }
            }
        }
    }
}

// 開始四問搬到 WeekView.swift：送出之後接著看「這週的田」。

// MARK: 讓開始更容易（從設定頁搬過來，卡住的時候才看）

struct TipsSheet: View {
    @Environment(Store.self) private var store

    var body: some View {
        SheetFrame {
            SheetTitle("讓開始更容易")
            SheetNote("時機到的那一刻，手邊的阻力越小越好。三件前一晚就能做的事：")
            Card {
                ForEach(Array(Phrases.tips.enumerated()), id: \.offset) { i, tip in
                    if i > 0 { RowSep() }
                    HStack(alignment: .top, spacing: Sp.s3) {
                        Text("\(i + 1)")
                            .domyType(Ty.callout)
                            .foregroundStyle(Theme.strong)
                            .frame(width: Sp.s6, height: Sp.s6)
                            .background(Theme.soft, in: Circle())
                        Text(tip)
                            .domyType(Ty.body)
                            .foregroundStyle(Theme.fg)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Sp.s4)
                    .padding(.vertical, Sp.s3)
                }
            }
            if store.state.habit != nil && AIClient.shared.isAvailable {
                RivalHelper().padding(.top, Sp.s2)
            }
        }
    }
}

// MARK: 什麼時候不適合用這個 app

struct UnfitSheet: View {
    var body: some View {
        SheetFrame(full: true) {
            SheetTitle("什麼時候不適合用這個 app")
            SheetNote("這個 app 幫你把一個新行為接到生活裡的固定瞬間。下面這些情況，單靠習慣設計不夠，先找專業的人看：")
            Card {
                RowLabel(text: "停不下來的渴望、量控制不了、不做會很難受（菸、酒、賭博、某些網路使用）")
                RowSep()
                RowLabel(text: "做某件事是為了壓下一個停不下來的念頭")
                RowSep()
                RowLabel(text: "拔頭髮、摳皮膚、咬指甲到受傷")
                RowSep()
                RowLabel(text: "跟飲食、體重、身形有關的目標")
                RowSep()
                RowLabel(text: "兩週以上對大部分事情都提不起勁")
            }
            Card {
                hotline("安心專線", number: "1925")
                RowSep()
                hotline("戒菸專線", number: "0800-63-63-63")
            }
            SheetNote("兩支都免付費，安心專線 24 小時有人接。也可以掛精神科、身心科，或找臨床心理師。")
        }
    }

    private func hotline(_ name: String, number: String) -> some View {
        HStack(spacing: Sp.s3) {
            Text(name).domyType(Ty.body).foregroundStyle(Theme.fg)
            Spacer()
            Text(number)
                .domyType(Ty.headline)
                .foregroundStyle(Theme.strong)
                .monospacedDigit()
                .fixedSize()
                .textSelection(.enabled)
        }
        .padding(.horizontal, Sp.s4)
        .padding(.vertical, Sp.s3)
        .frame(minHeight: Sz.row)
    }
}

// MARK: 匯出備份

struct ExportSheet: View {
    @Environment(Store.self) private var store
    @State private var fileURL: URL? = nil
    @State private var json = ""

    var body: some View {
        SheetFrame {
            SheetTitle("匯出備份")
            SheetNote("存成一個檔案，放到 iCloud 雲碟、傳給自己都可以。要還原時用「從備份還原」選這個檔，或把內容貼進去。")
            if let fileURL {
                ShareLink(item: fileURL, preview: SharePreview("薯記備份", image: Image(systemName: "leaf"))) {
                    Text("分享備份檔")
                        .domyType(Ty.headline)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: Sz.button)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(DomyPressStyle())
            }
            DomyButton("複製成文字", variant: .secondary) {
                UIPasteboard.general.string = json
                store.show("複製好了。")
            }
            SheetNote("這段文字跟網頁原型的備份是同一種格式，兩邊可以互相還原。")
        }
        .onAppear { prepare() }
    }

    private func prepare() {
        json = store.exportJSON()
        let name = "薯記備份-\(store.today.string).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if let data = json.data(using: .utf8), (try? data.write(to: url, options: .atomic)) != nil {
            fileURL = url
        }
    }
}

// MARK: 從備份還原

struct RestoreSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var failed = false
    @State private var picking = false
    @FocusState private var editing: Bool

    var body: some View {
        SheetFrame {
            SheetTitle("從備份還原")
            SheetNote("貼上之前匯出的那段文字，或選一個備份檔。目前的資料會被取代。")
            TextEditor(text: $text)
                .font(.system(Ty.footnote.textStyle, design: .monospaced))
                .scrollContentBackground(.hidden)
                .focused($editing)
                .frame(minHeight: 120) // domy-ignore: 貼上整段 JSON 的高度
                .autocorrectionDisabled()
                .domyField(focused: editing, error: failed)
            if failed {
                HStack(alignment: .top, spacing: Sp.s2) {
                    Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                    Text("這段讀不出來，確認是完整複製的那一整段。")
                }
                .domyType(Ty.footnote)
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, Sp.s1)
            }
            DomyButton("選備份檔", variant: .secondary) { picking = true }
            DomyButton("還原") {
                if store.importJSON(text) {
                    dismiss()
                } else {
                    failed = true
                    Haptic.error()
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json, .plainText, .text]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                text = String(decoding: data, as: UTF8.self)
                failed = false
            }
        }
    }
}

// MARK: 竹籃裡的一顆地瓜

struct PotatoSheet: View {
    var potato: Potato

    var body: some View {
        SheetFrame {
            HStack { Spacer(); PotatoView(width: 120); Spacer() } // domy-ignore: 插畫尺寸
                .padding(.vertical, Sp.s2)
                .background(Theme.tint, in: RoundedRectangle(cornerRadius: Rd.xl, style: .continuous))
            Text(potato.floor)
                .domyType(Ty.title2)
                .foregroundStyle(Theme.fg)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            Card {
                RowLabel(text: "時機", value: potato.trigger)
                RowSep()
                RowLabel(text: "根", value: "\(potato.nodes) 條")
                RowSep()
                RowLabel(text: "回來", value: "\(potato.ret) 次")
                RowSep()
                RowLabel(text: "種了", value: "\(potato.planted.short) – \(potato.dug.short)")
            }
        }
    }
}
