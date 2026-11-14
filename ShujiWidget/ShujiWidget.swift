import SwiftUI

import UIKit
import WidgetKit

/// 小工具跟 app 用同一套 Domy 代號（Shared/DomyTokens.swift），產品色梅紫
private let brand = DomyTheme.plum
private typealias Ty = DomyTokens.TypeScale

/// 桌面與鎖定畫面的小工具：開關句＋今天記了沒。
/// 沒有按鈕。原型說「開關要在生活裡，不在手機裡」，小工具是被動看到，跟這句不衝突；加按鈕就衝突了。
struct ShujiEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
    let today: DayKey
}

struct ShujiProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShujiEntry {
        ShujiEntry(date: Date(), snap: .sample, today: DayKey.today())
    }

    func getSnapshot(in context: Context, completion: @escaping (ShujiEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    /// 一條時間線只有現在這一格；下一次換日（凌晨四點）再重算，記了或請假就變回「還沒記」
    func getTimeline(in context: Context, completion: @escaping (Timeline<ShujiEntry>) -> Void) {
        let entry = current()
        let next = entry.today.adding(1).date(hour: 4, minute: 0) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func current() -> ShujiEntry {
        ShujiEntry(date: Date(), snap: WidgetSnapshot.read(), today: DayKey.today())
    }
}

struct ShujiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShujiEntry

    private var snap: WidgetSnapshot? { entry.snap }
    private var status: WidgetSnapshot.Status { snap?.display(today: entry.today) ?? .empty }

    private var statusText: String {
        let n = snap?.nodes ?? 0
        switch status {
        case .empty: return "還沒種東西"
        case .dug: return "挖出來了，種下一個"
        case .letgo: return "放手測試中，不用記"
        case .done: return "今天記了 · 第 \(n) 節"
        case .leave: return "今天請假"
        case .none: return "今天還沒記 · 第 \(n) 節"
        }
    }

    private var statusIsDone: Bool { status == .done }

    private var locked: Bool { snap.map { $0.full != true && $0.status != .empty } ?? false }

    var body: some View {
        if locked {
            lockedView
        } else {
            mainView
        }
    }

    @ViewBuilder
    private var lockedView: some View {
        switch family {
        case .accessoryInline:
            Text("薯記 · 完整版才有小工具")
        case .accessoryRectangular:
            Text("小工具是薯記完整版的功能")
                .font(Ty.caption.font)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: DomyTokens.Space.s2) {
                Text("薯記").font(Ty.caption.font).foregroundStyle(DomyTokens.Neutral.textSecondary)
                Text("小工具是完整版的功能。打開薯記，設定頁可以看看。")
                    .font(Ty.subheadline.font)
                    .foregroundStyle(DomyTokens.Neutral.textPrimary)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var mainView: some View {
        switch family {
        case .accessoryInline:
            Text("薯記 · " + statusText)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: DomyTokens.Space.s1 / 2) {
                if let s = snap, status != .empty {
                    Text("如果\(s.trigger)，我就\(s.floor)。")
                        .font(Ty.headline.font)
                        .lineLimit(2)
                }
                Text(statusText)
                    .font(Ty.caption.font)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: DomyTokens.Space.s2) {
                Text("開關")
                    .font(Ty.caption.font)
                    .foregroundStyle(brand.strong)
                if let s = snap, status != .empty {
                    (Text("如果") + Text(s.trigger).bold() + Text("，我就") + Text(s.floor).bold() + Text("。"))
                        .font(family == .systemSmall ? Ty.subheadline.font : Ty.title3.font.weight(.regular))
                        .foregroundStyle(DomyTokens.Neutral.textPrimary)
                        .lineLimit(family == .systemSmall ? 4 : 3)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("打開薯記，種一個習慣。")
                        .font(Ty.subheadline.font)
                        .foregroundStyle(DomyTokens.Neutral.textPrimary)
                }
                Spacer(minLength: 0)
                HStack(spacing: DomyTokens.Space.s1) {
                    Image(systemName: statusIsDone ? "checkmark.circle.fill" : "circle")
                        .font(Ty.caption.font)
                        .foregroundStyle(statusIsDone ? brand.accent : DomyTokens.Neutral.textTertiary)
                    Text(statusText)
                        .font(Ty.caption.font.weight(statusIsDone ? .semibold : .regular))
                        .foregroundStyle(statusIsDone ? brand.strong : DomyTokens.Neutral.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

@main
struct ShujiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShujiWidget", provider: ShujiProvider()) { entry in
            ShujiWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    DomyTokens.Neutral.surface
                }
        }
        .configurationDisplayName("薯記")
        .description("開關句，和今天記了沒。記一節還是要進 app 按住。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
