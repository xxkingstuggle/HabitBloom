import SwiftUI

struct StatsView: View {
    let habits: [HabitEntity]
    let statsByHabitID: [UUID: HabitStatsViewModel]
    let onToggleDay: (HabitEntity, Date) -> Void
    let onEditNote: (HabitEntity, Date) -> Void

    @State private var monthOffsetByHabitID: [UUID: Int] = [:]

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(habits) { habit in
                    let stats = statsByHabitID[habit.id] ?? .empty
                    let monthOffset = monthOffsetByHabitID[habit.id] ?? 0
                    let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            HabitIconGlyph(icon: habit.icon, size: habit.icon.isEmojiIcon ? 22 : 18)
                                .foregroundStyle((HabitPalette(rawValue: habit.colorName) ?? .coral).accent)
                                .frame(width: 34, height: 34)
                                .background(Color.secondary.opacity(0.10), in: Circle())
                            Text(habit.name)
                                .font(.headline)
                            Spacer()
                            Text("\(Int(stats.monthCompletionRate * 100))%")
                                .font(.title3.weight(.bold))
                        }

                        HStack(spacing: 12) {
                            StatPill(title: "连续", value: "\(stats.currentStreak) 天")
                            StatPill(title: "累计", value: "\(stats.totalCompletedDays) 天")
                        }

                        HStack {
                            Button {
                                monthOffsetByHabitID[habit.id] = monthOffset - 1
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.subheadline.weight(.bold))
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Text(monthDate.formatted(.dateTime.year().month()))
                                .font(.subheadline.weight(.semibold))

                            Spacer()

                            Button {
                                monthOffsetByHabitID[habit.id] = monthOffset + 1
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.weight(.bold))
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .disabled(monthOffset >= 0)
                            .opacity(monthOffset >= 0 ? 0.35 : 1)
                        }

                        MonthCalendarView(
                            displayedMonth: monthDate,
                            completedDays: completedDaySet(for: habit),
                            notedDays: notedDaySet(for: habit),
                            today: calendar.startOfDay(for: Date()),
                            accent: (HabitPalette(rawValue: habit.colorName) ?? .coral).accent,
                            onToggleDay: { day in onToggleDay(habit, day) },
                            onEditNote: { day in onEditNote(habit, day) }
                        )

                        Text("点按任意日期可补卡或取消打卡，长按可写当日备注。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle("统计")
    }

    private func completedDaySet(for habit: HabitEntity) -> Set<Date> {
        Set((habit.checkIns ?? []).filter(\.isCompleted).map { calendar.startOfDay(for: $0.day) })
    }

    private func notedDaySet(for habit: HabitEntity) -> Set<Date> {
        Set((habit.checkIns ?? []).filter { !$0.note.isEmpty }.map { calendar.startOfDay(for: $0.day) })
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
