import Foundation
import HabitCore

let calendar = Calendar(identifier: .gregorian)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError("Smoke test failed: \(message)")
    }
}

func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    guard let value = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
        fatalError("Invalid date")
    }
    return value
}

let dailyHabit = Habit(name: "阅读", targetWeekdays: Set(1...7))
let today = date(2026, 6, 11)
let dailyCheckIns = [
    CheckIn(habitID: dailyHabit.id, day: today),
    CheckIn(habitID: dailyHabit.id, day: date(2026, 6, 10)),
    CheckIn(habitID: dailyHabit.id, day: date(2026, 6, 9))
]
let dailyStats = HabitStatsCalculator(calendar: calendar).stats(for: dailyHabit, checkIns: dailyCheckIns, today: today)
require(dailyStats.currentStreak == 3, "daily streak should be 3")
require(dailyStats.totalCompletedDays == 3, "total completed days should be 3")

// 今天还没打卡时，连续天数不能清零——从昨天开始回溯。
let pendingStats = HabitStatsCalculator(calendar: calendar).stats(for: dailyHabit, checkIns: dailyCheckIns, today: date(2026, 6, 12))
require(pendingStats.currentStreak == 3, "streak must survive an unchecked today")
require(pendingStats.totalCompletedDays == 3, "unchecked today must not change total days")

// 今天不是目标日时不回溯，连续天数按既有目标日累计。
let weekendHabit = Habit(name: "周末", targetWeekdays: [1, 7])
let weekendCheckIns = [CheckIn(habitID: weekendHabit.id, day: date(2026, 6, 7))]
let weekendStats = HabitStatsCalculator(calendar: calendar).stats(for: weekendHabit, checkIns: weekendCheckIns, today: date(2026, 6, 8))
require(weekendStats.currentStreak == 1, "streak on non-target day must keep counting prior target days")

let weekdayHabit = Habit(name: "运动", targetWeekdays: Set(2...6))
let weekdayCheckIns = [
    CheckIn(habitID: weekdayHabit.id, day: date(2026, 6, 8)),
    CheckIn(habitID: weekdayHabit.id, day: date(2026, 6, 5))
]
let weekdayStats = HabitStatsCalculator(calendar: calendar).stats(for: weekdayHabit, checkIns: weekdayCheckIns, today: date(2026, 6, 8))
require(weekdayStats.currentStreak == 2, "weekday streak should skip weekend")

let reminderHabit = Habit(
    name: "喝水",
    reminder: ReminderRule(isEnabled: true, hour: 19, minute: 30, activeWeekdays: [2, 4, 6])
)
let requests = ReminderPlanner().requests(for: reminderHabit)
require(requests.count == 3, "reminder count should match active weekdays")
require(requests.map(\.weekday) == [2, 4, 6], "reminder weekdays should be sorted")

print("HabitCore smoke tests passed")
