import Foundation
import UserNotifications

/// Lokale Erinnerungen (Wasser, Wiegen, Mahlzeiten, Supplements, Zyklus).
enum NotificationManager {
    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Plant eine tägliche bzw. wöchentliche Erinnerung.
    /// - Parameter weekdays: 1 = Sonntag … 7 = Samstag. `nil` = täglich.
    static func schedule(id: String, title: String, body: String, hour: Int, minute: Int, weekdays: [Int]? = nil) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        if let weekdays, !weekdays.isEmpty {
            for day in weekdays {
                var comps = DateComponents()
                comps.hour = hour
                comps.minute = minute
                comps.weekday = day
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                center.add(UNNotificationRequest(identifier: "\(id).\(day)", content: content, trigger: trigger))
            }
        } else {
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    /// Einmalige Erinnerung nach einer Verzögerung (z. B. Pausentimer im Hintergrund).
    static func scheduleOnce(id: String, title: String, body: String, after seconds: TimeInterval) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Entfernt alle geplanten Erinnerungen, deren ID mit `prefix` beginnt.
    static func cancel(prefix: String) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
