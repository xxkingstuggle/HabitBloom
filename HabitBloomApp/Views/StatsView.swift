import SwiftUI

struct StatsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let habits: [HabitEntity]
    let statsByHabitID: [UUID: HabitStatsViewModel]
    let onToggleDay: (HabitEntity, Date) -> Void
    let onEditNote: (HabitEntity, Date) -> Void

    @State private var monthOffsetByHabitID: [UUID: Int] = [:]

    private let calendar = Calendar.current

    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [
                GridItem(.flexible(minimum: 300), spacing: 16),
                GridItem(.flexible(minimum: 300), spacing: 16)
            ]
        }
        return [GridItem(.flexible())]
    }

    var body: some View {
        ScrollView {
            if habits.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("暂无统计数据")
                        .font(.title3.weight(.bold))
                    Text("在首页创建目标并打卡后，这里会展示月度完成率、历史最长连续与可补卡日历。")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 96)
                .padding(.horizontal, 24)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(habits) { habit in
                        habitStatCard(for: habit)
                    }
                }
                .frame(maxWidth: 1080)
                .frame(maxWidth: .infinity)
                .padding(18)
            }
        }
        .background(AppBackground())
        .navigationTitle("统计")
    }

    @ViewBuilder
    private func habitStatCard(for habit: HabitEntity) -> some View {
        let stats = statsByHabitID[habit.id] ?? .empty
        let palette = HabitPalette(rawValue: habit.colorName) ?? .coral
        let monthOffset = monthOffsetByHabitID[habit.id] ?? 0
        let today = calendar.startOfDay(for: Date())
        let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: today) ?? today
        let selectedMonthRate = monthOffset == 0
            ? stats.monthCompletionRate
            : HabitStatsService.monthCompletionRate(for: habit, in: monthDate, calendar: calendar)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HabitIconGlyph(icon: habit.icon, size: habit.icon.isEmojiIcon ? 22 : 18)
                    .foregroundStyle(palette.accent)
                    .frame(width: 36, height: 36)
                    .background(palette.accent.opacity(colorScheme == .dark ? 0.22 : 0.13), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(monthOffset == 0 ? "本月完成率" : "\(monthDate.formatted(.dateTime.year().month())) 完成率")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int((selectedMonthRate * 100).rounded()))%")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(palette.accent)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                StatPill(title: "当前连续", value: "\(stats.currentStreak) 天")
                StatPill(title: "历史最长", value: "\(stats.bestStreak) 天")
                StatPill(title: "累计打卡", value: "\(stats.totalCompletedDays) 天")
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
                .accessibilityLabel("上一个月")

                Spacer()

                HStack(spacing: 8) {
                    Text(monthDate.formatted(.dateTime.year().month()))
                        .font(.subheadline.weight(.semibold))
                    if monthOffset < 0 {
                        Button("回本月") {
                            monthOffsetByHabitID[habit.id] = 0
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

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
                .accessibilityLabel("下一个月")
            }

            MonthCalendarView(
                displayedMonth: monthDate,
                completedDays: completedDaySet(for: habit),
                notedDays: notedDaySet(for: habit),
                today: today,
                accent: palette.accent,
                onToggleDay: { day in onToggleDay(habit, day) },
                onEditNote: { day in onEditNote(habit, day) }
            )

            Text("点按今天及以往日期可补卡或取消，右键/长按可编辑当日备注。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.appBackgroundSecondary)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.adaptiveCardBorder(for: colorScheme, reduceTransparency: reduceTransparency), lineWidth: 1)
        )
    }

    private func completedDaySet(for habit: HabitEntity) -> Set<Date> {
        Set((habit.checkIns ?? []).filter(\.isCompleted).map { calendar.startOfDay(for: $0.day) })
    }

    private func notedDaySet(for habit: HabitEntity) -> Set<Date> {
        Set((habit.checkIns ?? []).filter { !$0.note.isEmpty }.map { calendar.startOfDay(for: $0.day) })
    }
}

private struct StatPill: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.adaptiveChipSurface(for: colorScheme, reduceTransparency: reduceTransparency))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.adaptiveCardBorder(for: colorScheme, reduceTransparency: reduceTransparency).opacity(0.6), lineWidth: 0.7)
        )
    }
}
