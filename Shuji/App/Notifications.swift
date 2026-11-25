import Foundation
import UserNotifications

/// 收工檢查：原型寫「原生版才有」的那個開關。
/// 一天最多一則，而且只在「那天還沒記」的情況下才排；記了就排明天。
/// 放手測試中、剛挖完、還沒種，都不排。連漏 3 天以上也先不排，記了下一節再恢復（.analytics/08 安靜規則 6）。
/// 穩了之後只在前一天漏掉時響，再穩兩週就退場（Comeback.swift）。
enum CheckNotification {
    static let identifier = "shuji.check"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    static func reschedule(state: AppState, today t: DayKey, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let days = state.reminderDays(today: t)
        guard !days.isEmpty else { return }

        let hour = state.settings.checkHour
        let minute = state.settings.checkMinute
        // 收工時間設在凌晨四點前的話，屬於「前一天」那一輪，落在下一個日曆日
        func fireDate(for day: DayKey) -> Date? {
            (hour < 4 ? day.adding(1) : day).date(hour: hour, minute: minute)
        }

        guard let date = days.compactMap({ fireDate(for: $0) }).first(where: { $0 > now }) else { return }

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let content = UNMutableNotificationContent()
        content.title = "薯記"
        content.body = state.reminderText
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
