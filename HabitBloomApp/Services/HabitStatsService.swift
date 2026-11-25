import Foundation

struct HabitStatsViewModel {
    var currentStreak: Int
    var bestStreak: Int = 0
    var totalCompletedDays: Int
    var monthCompletionRate: Double
    var monthDays: [(date: Date, isCompleted: Bool)]

    static let empty = HabitStatsViewModel(
        currentStreak: 0,
        bestStreak: 0,
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
    /// 与 HabitCore 共享同一套连续天数口径（今天未打卡时从昨天回溯），
    /// 这里直接对接 SwiftData 实体，避免双轨实现漂移。
    static func stats(for habit: HabitEntity, today: Date = Date(), calendar: Calendar = .current) -> HabitStatsViewModel {
        let normalizedToday = calendar.startOfDay(for: today)
        return stats(
            for: habit,
            completedDays: completedDays(for: habit, calendar: calendar),
            normalizedToday: normalizedToday,
            calendar: calendar
        )
    }

    static func isCompletedToday(_ habit: HabitEntity, today: Date = Date(), calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: today)
        return (habit.checkIns ?? []).contains { calendar.startOfDay(for: $0.day) == day && $0.isCompleted }
    }

    static func monthCompletionRate(for habit: HabitEntity, in monthDate: Date, calendar: Calendar = .current) -> Double {
        let targetWeekdays = Set(WeekdayMask.weekdays(from: habit.targetWeekdayMask))
        guard !targetWeekdays.isEmpty else { return 0 }
        let completed = completedDays(for: habit, calendar: calendar)
        let monthDays = daysInMonth(containing: calendar.startOfDay(for: monthDate), calendar: calendar)
        let expectedDays = monthDays.filter { targetWeekdays.contains(calendar.component(.weekday, from: $0)) }
        guard !expectedDays.isEmpty else { return 0 }
        let completedExpected = expectedDays.filter { completed.contains($0) }.count
        return Double(completedExpected) / Double(expectedDays.count)
    }

    static func derivedState(for habits: [HabitEntity], today: Date = Date(), calendar: Calendar = .current) -> HabitDerivedState {
        let normalizedToday = calendar.startOfDay(for: today)
        var statsByHabitID: [UUID: HabitStatsViewModel] = [:]
        var completedTodayByHabitID: [UUID: Bool] = [:]
        statsByHabitID.reserveCapacity(habits.count)
        completedTodayByHabitID.reserveCapacity(habits.count)

        for habit in habits {
            let completedDays = completedDays(for: habit, calendar: calendar)
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
                bestStreak: 0,
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
        let longestStreak = bestStreak(
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
            bestStreak: longestStreak,
            totalCompletedDays: completedDays.count,
            monthCompletionRate: rate,
            monthDays: monthDays.map { ($0, completedDays.contains($0)) }
        )
    }

    private static func completedDays(for habit: HabitEntity, calendar: Calendar) -> Set<Date> {
        var completedDays = Set<Date>()
        for checkIn in habit.checkIns ?? [] where checkIn.isCompleted {
            completedDays.insert(calendar.startOfDay(for: checkIn.day))
        }
        return completedDays
    }

    private static func bestStreak(completedDays: Set<Date>, targetWeekdays: Set<Int>, calendar: Calendar) -> Int {
        guard let earliest = completedDays.min(), let latest = completedDays.max() else { return 0 }
        var cursor = earliest
        var current = 0
        var best = 0
        while cursor <= latest {
            let weekday = calendar.component(.weekday, from: cursor)
            if targetWeekdays.contains(weekday) {
                if completedDays.contains(cursor) {
                    current += 1
                    if current > best {
                        best = current
                    }
                } else {
                    current = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return best
    }

    private static func currentStreak(endingAt today: Date, completedDays: Set<Date>, targetWeekdays: Set<Int>, calendar: Calendar) -> Int {
        var cursor = today

        // 今天尚未打卡时，不要把已积累的连续天数清零：从昨天开始回溯。
        if targetWeekdays.contains(calendar.component(.weekday, from: cursor)),
           !completedDays.contains(cursor),
           let previous = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = previous
        }

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
