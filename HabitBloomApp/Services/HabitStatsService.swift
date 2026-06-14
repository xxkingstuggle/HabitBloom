import Foundation

struct HabitStatsViewModel {
    var currentStreak: Int
    var totalCompletedDays: Int
    var monthCompletionRate: Double
    var monthDays: [(date: Date, isCompleted: Bool)]

    static let empty = HabitStatsViewModel(
        currentStreak: 0,
        totalCompletedDays: 0,
        monthCompletionRate: 0,
        monthDays: []
    )
}

struct HabitDerivedState {
    var statsByHabitID: [UUID: HabitStatsViewModel]
    var completedTodayByHabitID: [UUID: Bool]
}

enum HabitStatsService {
    static func stats(for habit: HabitEntity, today: Date = Date(), calendar: Calendar = .current) -> HabitStatsViewModel {
        let normalizedToday = calendar.startOfDay(for: today)
        return stats(
            for: habit,
            completedDays: completedDays(for: habit),
            normalizedToday: normalizedToday,
            calendar: calendar
        )
    }

    static func isCompletedToday(_ habit: HabitEntity, today: Date = Date(), calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: today)
        return (habit.checkIns ?? []).contains { $0.day == day && $0.isCompleted }
    }

    static func derivedState(for habits: [HabitEntity], today: Date = Date(), calendar: Calendar = .current) -> HabitDerivedState {
        let normalizedToday = calendar.startOfDay(for: today)
        var statsByHabitID: [UUID: HabitStatsViewModel] = [:]
        var completedTodayByHabitID: [UUID: Bool] = [:]
        statsByHabitID.reserveCapacity(habits.count)
        completedTodayByHabitID.reserveCapacity(habits.count)

        for habit in habits {
            let completedDays = completedDays(for: habit)
            statsByHabitID[habit.id] = stats(
                for: habit,
                completedDays: completedDays,
                normalizedToday: normalizedToday,
                calendar: calendar
            )
            completedTodayByHabitID[habit.id] = completedDays.contains(normalizedToday)
        }

        return HabitDerivedState(
            statsByHabitID: statsByHabitID,
            completedTodayByHabitID: completedTodayByHabitID
        )
    }

    private static func stats(
        for habit: HabitEntity,
        completedDays: Set<Date>,
        normalizedToday: Date,
        calendar: Calendar
    ) -> HabitStatsViewModel {
        let targetWeekdays = Set(WeekdayMask.weekdays(from: habit.targetWeekdayMask))
        guard !targetWeekdays.isEmpty else {
            return HabitStatsViewModel(
                currentStreak: 0,
                totalCompletedDays: completedDays.count,
                monthCompletionRate: 0,
                monthDays: daysInMonth(containing: normalizedToday, calendar: calendar).map { ($0, completedDays.contains($0)) }
            )
        }
        let streak = currentStreak(
            endingAt: normalizedToday,
            completedDays: completedDays,
            targetWeekdays: targetWeekdays,
            calendar: calendar
        )
        let monthDays = daysInMonth(containing: normalizedToday, calendar: calendar)
        let expectedDays = monthDays.filter { targetWeekdays.contains(calendar.component(.weekday, from: $0)) }
        let completedExpected = expectedDays.filter { completedDays.contains($0) }.count
        let rate = expectedDays.isEmpty ? 0 : Double(completedExpected) / Double(expectedDays.count)

        return HabitStatsViewModel(
            currentStreak: streak,
            totalCompletedDays: completedDays.count,
            monthCompletionRate: rate,
            monthDays: monthDays.map { ($0, completedDays.contains($0)) }
        )
    }

    private static func completedDays(for habit: HabitEntity) -> Set<Date> {
        var completedDays = Set<Date>()
        for checkIn in habit.checkIns ?? [] where checkIn.isCompleted {
            completedDays.insert(checkIn.day)
        }
        return completedDays
    }

    private static func currentStreak(endingAt today: Date, completedDays: Set<Date>, targetWeekdays: Set<Int>, calendar: Calendar) -> Int {
        var cursor = today
        var count = 0

        while true {
            let weekday = calendar.component(.weekday, from: cursor)
            if targetWeekdays.contains(weekday) {
                guard completedDays.contains(cursor) else { break }
                count += 1
            }

            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return count
    }

    private static func daysInMonth(containing date: Date, calendar: Calendar) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
        var days: [Date] = []
        var cursor = interval.start

        while cursor < interval.end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return days
    }
}
