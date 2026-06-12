import Foundation
import HabitCore

let calendar = Calendar(identifier: .gregorian)
let calculator = HabitStatsCalculator(calendar: calendar)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError("Stress test failed: \(message)")
    }
}

func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    guard let value = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
        fatalError("Invalid date")
    }
    return value
}

func addingDays(_ days: Int, to base: Date) -> Date {
    guard let value = calendar.date(byAdding: .day, value: days, to: base) else {
        fatalError("Invalid date math")
    }
    return value
}

let habitCount = 300
let dayCount = 1_460
let startDay = date(2022, 6, 13)
let today = addingDays(dayCount - 1, to: startDay)

let habits = (0..<habitCount).map { index in
    Habit(
        name: "压力目标 \(index)",
        icon: HabitIcon.allCases[index % HabitIcon.allCases.count],
        color: HabitColor.allCases[index % HabitColor.allCases.count],
        cardStyle: HabitCardStyle.allCases[index % HabitCardStyle.allCases.count],
        targetWeekdays: targetWeekdays(for: index),
        reminder: ReminderRule(
            isEnabled: index % 3 != 0,
            hour: index % 24,
            minute: (index * 7) % 60,
            activeWeekdays: Set([1 + (index % 7), 1 + ((index + 2) % 7)])
        ),
        sortOrder: index,
        createdAt: addingDays(-index, to: today)
    )
}

var checkIns: [CheckIn] = []
checkIns.reserveCapacity(habitCount * dayCount / 2)

for (habitIndex, habit) in habits.enumerated() {
    for offset in 0..<dayCount {
        let day = addingDays(offset, to: startDay)
        let weekday = calendar.component(.weekday, from: day)
        guard habit.targetWeekdays.contains(weekday) else { continue }

        let shouldComplete = ((offset + habitIndex) % 5) != 0
        checkIns.append(CheckIn(habitID: habit.id, day: day, isCompleted: shouldComplete))
    }
}

let start = Date()
let summaries = calculator.widgetSummaries(habits: habits, checkIns: checkIns, today: today)
let elapsed = Date().timeIntervalSince(start)

require(summaries.count == habitCount, "summary count should match habit count")
require(Set(summaries.map(\.id)).count == habitCount, "summary IDs should be unique")
require(summaries.map(\.name).prefix(3) == ["压力目标 0", "压力目标 1", "压力目标 2"], "summaries should keep sort order")

for habit in habits.prefix(30) {
    let stats = calculator.stats(for: habit, checkIns: checkIns, today: today)
    require(stats.monthCompletionRate >= 0 && stats.monthCompletionRate <= 1, "month rate should be clamped by construction")
    require(stats.totalCompletedDays <= dayCount, "completed days should not exceed simulated day count")
    _ = ReminderPlanner().requests(for: habit)
}

let formatter = NumberFormatter()
formatter.maximumFractionDigits = 3
let elapsedText = formatter.string(from: NSNumber(value: elapsed)) ?? "\(elapsed)"

print("HabitCore stress tests passed: \(habitCount) habits, \(checkIns.count) check-ins, widget summary in \(elapsedText)s")

func targetWeekdays(for index: Int) -> Set<Int> {
    switch index % 5 {
    case 0: return Set(1...7)
    case 1: return [2, 3, 4, 5, 6]
    case 2: return [1, 7]
    case 3: return [2, 4, 6]
    default: return [1, 3, 5]
    }
}
