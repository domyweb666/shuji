import SwiftUI
import UIKit
import WidgetKit

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

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("薯記 · " + statusText)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                if let s = snap, status != .empty {
                    Text("如果\(s.trigger)，我就\(s.floor)。")
                        .font(.headline)
                        .lineLimit(2)
                }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("開關")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let s = snap, status != .empty {
                    (Text("如果") + Text(s.trigger).bold() + Text("，我就") + Text(s.floor).bold() + Text("。"))
                        .font(family == .systemSmall ? .subheadline : .title3)
                        .lineLimit(family == .systemSmall ? 4 : 3)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("打開薯記，種一個習慣。")
                        .font(.subheadline)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusIsDone ? Color.purple : Color.secondary.opacity(0.35))
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption.weight(statusIsDone ? .semibold : .regular))
                        .foregroundStyle(statusIsDone ? Color.primary : Color.secondary)
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
                    Color(uiColor: .secondarySystemGroupedBackground)
                }
        }
        .configurationDisplayName("薯記")
        .description("開關句，和今天記了沒。記一節還是要進 app 按住。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
