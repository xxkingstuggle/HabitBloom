import SwiftUI

struct MonthCalendarView: View {
    let displayedMonth: Date
    let completedDays: Set<Date>
    let notedDays: Set<Date>
    let today: Date
    let accent: Color
    let onToggleDay: (Date) -> Void
    let onEditNote: (Date) -> Void

    private let calendar = Calendar.current
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let weeks = monthWeeks()
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date?) -> some View {
        Group {
            if let day {
                let isCompleted = completedDays.contains(day)
                let hasNote = notedDays.contains(day)
                let isFuture = day > today

                Button {
                    onToggleDay(day)
                } label: {
                    VStack(spacing: 1) {
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 12, weight: isCompleted ? .bold : .medium, design: .rounded))
                        Circle()
                            .fill(hasNote ? (isCompleted ? Color.white.opacity(0.95) : accent) : .clear)
                            .frame(width: 3, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .foregroundStyle(isCompleted ? .white : (isFuture ? Color.secondary.opacity(0.45) : .primary))
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isCompleted ? accent : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(day == today ? accent : .clear, lineWidth: 1.4)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(isCompleted ? "取消这一天打卡" : "补这一天打卡") {
                        onToggleDay(day)
                    }
                    Button(hasNote ? "编辑备注" : "添加备注") {
                        onEditNote(day)
                    }
                }
                .accessibilityLabel("\(day.formatted(date: .numeric, time: .omitted)) \(isCompleted ? "已打卡" : "未打卡")")
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
        }
    }

    private func monthWeeks() -> [[Date?]] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        var cells: [Date?] = Array(repeating: nil, count: firstWeekday - 1)

        var cursor = interval.start
        while cursor < interval.end {
            cells.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        var weeks: [[Date?]] = []
        for index in stride(from: 0, to: cells.count, by: 7) {
            weeks.append(Array(cells[index..<min(index + 7, cells.count)]))
        }
        return weeks
    }
}
