import Foundation
import UserNotifications

struct ReminderScheduleSnapshot: Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var hour: Int
    var minute: Int
    var weekdayMask: Int

    init(habit: HabitEntity) {
        id = habit.id
        name = habit.name
        isEnabled = habit.reminderEnabled
        hour = habit.reminderHour
        minute = habit.reminderMinute
        weekdayMask = habit.reminderWeekdayMask
    }
}

enum ReminderScheduler {
    static func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("Notification authorization failed: \(error)")
        }
    }

    static func reschedule(for snapshot: ReminderScheduleSnapshot) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = (1...7).map { "habit-reminder-\(snapshot.id.uuidString)-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        guard snapshot.isEnabled else { return }
        await requestAuthorization()

        for weekday in WeekdayMask.weekdays(from: snapshot.weekdayMask) {
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
                identifier: "habit-reminder-\(snapshot.id.uuidString)-\(weekday)",
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
