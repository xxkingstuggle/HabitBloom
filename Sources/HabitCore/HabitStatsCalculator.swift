import Foundation

public struct HabitStatsCalculator: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    public func stats(for habit: Habit, checkIns: [CheckIn], today: Date = Date()) -> HabitStats {
        let completedDays = completedDaySet(for: habit, checkIns: checkIns)
        let normalizedToday = calendar.startOfDay(for: today)
        let currentStreak = streak(endingAt: normalizedToday, habit: habit, completedDays: completedDays)
        let monthDays = daysInMonth(containing: normalizedToday)
        let expectedDays = monthDays.filter { habit.targetWeekdays.contains(calendar.component(.weekday, from: $0)) }
        let completedExpectedDays = expectedDays.filter { completedDays.contains($0) }.count
        let rate = expectedDays.isEmpty ? 0 : Double(completedExpectedDays) / Double(expectedDays.count)
        let heatmap = Dictionary(uniqueKeysWithValues: monthDays.map { ($0, completedDays.contains($0)) })

        return HabitStats(
            currentStreak: currentStreak,
            totalCompletedDays: completedDays.count,
            monthCompletionRate: rate,
            monthHeatmap: heatmap
        )
    }

    public func widgetSummaries(habits: [Habit], checkIns: [CheckIn], today: Date = Date()) -> [WidgetHabitSummary] {
        let normalizedToday = calendar.startOfDay(for: today)
        let completedDaysByHabit = completedDaySetsByHabit(checkIns: checkIns)

        return habits
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
            .map { habit in
                let completedDays = completedDaysByHabit[habit.id, default: []]
                return WidgetHabitSummary(
                    id: habit.id,
                    name: habit.name,
                    iconSymbolName: habit.icon.symbolName,
                    colorName: habit.color,
                    streakDays: streak(endingAt: normalizedToday, habit: habit, completedDays: completedDays),
                    isCompletedToday: completedDays.contains(normalizedToday),
                    customImageBookmark: habit.customImageBookmark
                )
            }
    }

    private func completedDaySetsByHabit(checkIns: [CheckIn]) -> [UUID: Set<Date>] {
        var grouped: [UUID: Set<Date>] = [:]
        grouped.reserveCapacity(min(checkIns.count, 256))

        for checkIn in checkIns where checkIn.isCompleted {
            grouped[checkIn.habitID, default: []].insert(calendar.startOfDay(for: checkIn.day))
        }

        return grouped
    }

    private func completedDaySet(for habit: Habit, checkIns: [CheckIn]) -> Set<Date> {
        Set(
            checkIns
                .filter { $0.habitID == habit.id && $0.isCompleted }
                .map { calendar.startOfDay(for: $0.day) }
        )
    }

    private func streak(endingAt today: Date, habit: Habit, completedDays: Set<Date>) -> Int {
        var day = today
        var count = 0

        while true {
            let weekday = calendar.component(.weekday, from: day)
            if habit.targetWeekdays.contains(weekday) {
                guard completedDays.contains(day) else { break }
                count += 1
            }

            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        return count
    }

    private func daysInMonth(containing date: Date) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
        var days: [Date] = []
        var cursor = interval.start

        while cursor < interval.end {
            days.append(calendar.startOfDay(for: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return days
    }
}
