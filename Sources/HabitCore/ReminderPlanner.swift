import Foundation

public struct ReminderRequest: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var body: String
    public var weekday: Int
    public var hour: Int
    public var minute: Int

    public init(identifier: String, title: String, body: String, weekday: Int, hour: Int, minute: Int) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }
}

public struct ReminderPlanner: Sendable {
    public init() {}

    public func requests(for habit: Habit) -> [ReminderRequest] {
        guard habit.reminder.isEnabled else { return [] }

        return habit.reminder.activeWeekdays.sorted().map { weekday in
            ReminderRequest(
                identifier: "habit-reminder-\(habit.id.uuidString)-\(weekday)",
                title: "该打卡了",
                body: "\(habit.name) 还没有完成，今天轻轻补上吧。",
                weekday: weekday,
                hour: habit.reminder.hour,
                minute: habit.reminder.minute
            )
        }
    }
}
