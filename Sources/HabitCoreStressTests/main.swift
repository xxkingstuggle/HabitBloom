import Foundation
import HabitCore
import HabitWidgetShared

let calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return value
}()
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
    let best = calculator.bestStreak(for: habit, checkIns: checkIns)
    require(best >= stats.currentStreak, "bestStreak must be at least currentStreak")
    let priorMonthRate = calculator.monthCompletionRate(for: habit, checkIns: checkIns, in: addingDays(-60, to: today))
    require(priorMonthRate >= 0 && priorMonthRate <= 1, "prior month rate must be within [0, 1]")
    _ = ReminderPlanner().requests(for: habit)
}

let backupSampleCount = 120
let existingBackupHabits: [RemoteBackupHabit] = habits.prefix(backupSampleCount).enumerated().map { index, habit in
    let entries = (0..<40).map { offset in
        RemoteBackupCheckIn(
            day: addingDays(-offset, to: today),
            isCompleted: (offset + index) % 2 == 0,
            note: offset % 10 == 0 ? "local-\(offset)" : "",
            createdAt: addingDays(-offset, to: today)
        )
    }
    return RemoteBackupHabit(
        id: habit.id,
        name: habit.name,
        icon: habit.icon.symbolName,
        colorName: habit.color.rawValue,
        cardStyle: habit.cardStyle.rawValue,
        targetWeekdayMask: 127,
        reminderEnabled: false,
        reminderHour: 20,
        reminderMinute: 0,
        reminderWeekdayMask: 127,
        sortOrder: index,
        createdAt: habit.createdAt,
        checkIns: entries
    )
}

let importedBackupHabits: [RemoteBackupHabit] = existingBackupHabits.enumerated().map { index, existing in
    var entries = existing.checkIns
    entries.append(
        RemoteBackupCheckIn(
            day: addingDays(-5, to: today),
            isCompleted: !entries[5].isCompleted,
            note: "imported-conflict-\(index)",
            createdAt: today
        )
    )
    entries.append(
        RemoteBackupCheckIn(
            day: addingDays(-41, to: today),
            isCompleted: true,
            note: "imported-new",
            createdAt: today
        )
    )
    return RemoteBackupHabit(
        id: existing.id,
        name: existing.name,
        icon: existing.icon,
        colorName: existing.colorName,
        cardStyle: existing.cardStyle,
        targetWeekdayMask: existing.targetWeekdayMask,
        reminderEnabled: existing.reminderEnabled,
        reminderHour: existing.reminderHour,
        reminderMinute: existing.reminderMinute,
        reminderWeekdayMask: existing.reminderWeekdayMask,
        sortOrder: existing.sortOrder,
        createdAt: existing.createdAt,
        checkIns: entries
    )
}

let stressArchive = RemoteBackupArchive(
    version: 1,
    deviceKey: "stress-device-0001",
    exportedAt: today,
    habits: importedBackupHabits
)
let stressPlan = BackupImportPlanner.makePlan(
    existingHabits: existingBackupHabits,
    importedArchive: stressArchive,
    calendar: calendar
)
require(stressPlan.deduplicatedImportedCheckInCount == backupSampleCount, "stress plan should collapse duplicates across all habits")
require(stressPlan.conflictCount == backupSampleCount, "stress plan should report exact conflict count")
require(stressPlan.newCheckInCount == backupSampleCount, "stress plan should detect exact new check-in count")

let mergedStressHabits = BackupImportPlanner.merge(
    existingHabits: existingBackupHabits,
    importedArchive: stressArchive,
    strategy: .overwriteWithImported,
    calendar: calendar
)
require(mergedStressHabits.count == backupSampleCount, "merged stress habit count should stay stable")

let stressPending: [PendingWidgetCheckIn] = habits.map { habit in
    PendingWidgetCheckIn(habitID: habit.id, isCompletedToday: true, day: today, updatedAt: today)
}
let stressReconciled = WidgetCheckInReconciler.reconcile(
    localPending: stressPending,
    remoteSnapshot: nil,
    existingTodayStateByHabitID: [:],
    referenceDate: today,
    calendar: calendar
)
require(stressReconciled.count == habitCount, "stress reconciler should resolve all habits")

let formatter = NumberFormatter()
formatter.maximumFractionDigits = 3
let elapsedText = formatter.string(from: NSNumber(value: elapsed)) ?? "\(elapsed)"

print("HabitCore and HabitWidgetShared stress tests passed: \(habitCount) habits, \(checkIns.count) check-ins, widget summary in \(elapsedText)s")

func targetWeekdays(for index: Int) -> Set<Int> {
    switch index % 5 {
    case 0: return Set(1...7)
    case 1: return [2, 3, 4, 5, 6]
    case 2: return [1, 7]
    case 3: return [2, 4, 6]
    default: return [1, 3, 5]
    }
}
