import Foundation
import UserNotifications

struct ReminderScheduleSnapshot: Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var hour: Int
    var minute: Int
    var weekdayMask: Int

    init(id: UUID, name: String, isEnabled: Bool, hour: Int, minute: Int, weekdayMask: Int) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
        self.weekdayMask = weekdayMask
    }

    init(habit: HabitEntity) {
        self.init(
            id: habit.id,
            name: habit.name,
            isEnabled: habit.reminderEnabled,
            hour: habit.reminderHour,
            minute: habit.reminderMinute,
            weekdayMask: habit.reminderWeekdayMask
        )
    }
}

enum ReminderScheduler {
    private static let suppressedTodayKey = "suppressedReminderDates"

    /// 今日已打卡：把该习惯今天已排上的提醒从待触发列表里拿掉，避免「完成了还被催」。
    static func suppressTodayIfNeeded(for snapshot: ReminderScheduleSnapshot) async {
        guard snapshot.isEnabled else { return }
        let weekday = Calendar.current.component(.weekday, from: Date())
        guard WeekdayMask.contains(weekday, in: snapshot.weekdayMask) else { return }

        let identifier = reminderIdentifier(habitID: snapshot.id, weekday: weekday)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        markSuppressed(habitID: snapshot.id, on: Date())
    }

    /// 应用启动时调用：把所有「昨天及更早被抑止」的习惯提醒重新排回去。
    /// 只接收 Sendable 快照，不跨隔离域传 SwiftData 模型。
    static func restoreSuppressedReminders(snapshots: [ReminderScheduleSnapshot]) async {
        let today = Calendar.current.startOfDay(for: Date())
        var suppressed = UserDefaults.standard.dictionary(forKey: suppressedTodayKey) as? [String: Double] ?? [:]
        var changed = false

        for snapshot in snapshots where snapshot.isEnabled {
            let key = snapshot.id.uuidString
            guard let timestamp = suppressed[key] else { continue }
            let suppressedDay = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: timestamp))
            if suppressedDay < today {
                suppressed.removeValue(forKey: key)
                changed = true
                await reschedule(for: snapshot)
            }
        }

        if changed {
            UserDefaults.standard.set(suppressed, forKey: suppressedTodayKey)
        }
    }

    private static func markSuppressed(habitID: UUID, on day: Date) {
        var suppressed = UserDefaults.standard.dictionary(forKey: suppressedTodayKey) as? [String: Double] ?? [:]
        suppressed[habitID.uuidString] = Calendar.current.startOfDay(for: day).timeIntervalSince1970
        UserDefaults.standard.set(suppressed, forKey: suppressedTodayKey)
    }

    private static func reminderIdentifier(habitID: UUID, weekday: Int) -> String {
        "habit-reminder-\(habitID.uuidString)-\(weekday)"
    }

    static func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("Notification authorization failed: \(error)")
        }
    }

    static func reschedule(for snapshot: ReminderScheduleSnapshot) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = (1...7).map { reminderIdentifier(habitID: snapshot.id, weekday: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        guard snapshot.isEnabled else { return }
        await requestAuthorization()

        let today = Calendar.current.startOfDay(for: Date())
        let suppressed = UserDefaults.standard.dictionary(forKey: suppressedTodayKey) as? [String: Double] ?? [:]
        let suppressedToday = (suppressed[snapshot.id.uuidString]).map {
            Calendar.current.startOfDay(for: Date(timeIntervalSince1970: $0)) == today
        } ?? false
        let todayWeekday = Calendar.current.component(.weekday, from: Date())

        for weekday in WeekdayMask.weekdays(from: snapshot.weekdayMask) {
            // 今日已被打卡抑止：跳过今天的这一条，保留其余工作日。
            if suppressedToday && weekday == todayWeekday {
                continue
            }

            var date = DateComponents()
            date.weekday = weekday
            date.hour = snapshot.hour
            date.minute = snapshot.minute

            let content = UNMutableNotificationContent()
            content.title = "该打卡了"
            content.body = "\(snapshot.name) 还没有完成，今天轻轻补上吧。"
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(
                identifier: reminderIdentifier(habitID: snapshot.id, weekday: weekday),
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                print("Scheduling reminder failed: \(error)")
            }
        }
    }
}
