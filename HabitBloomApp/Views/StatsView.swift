import SwiftUI

struct StatsView: View {
    let habits: [HabitEntity]
    let statsByHabitID: [UUID: HabitStatsViewModel]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(habits) { habit in
                    let stats = statsByHabitID[habit.id] ?? .empty
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label(habit.name, systemImage: habit.icon)
                                .font(.headline)
                            Spacer()
                            Text("\(Int(stats.monthCompletionRate * 100))%")
                                .font(.title3.weight(.bold))
                        }

                        HStack(spacing: 12) {
                            StatPill(title: "连续", value: "\(stats.currentStreak) 天")
                            StatPill(title: "累计", value: "\(stats.totalCompletedDays) 天")
                        }

                        MonthHeatmap(days: stats.monthDays, colorName: habit.colorName)
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

private struct MonthHeatmap: View {
    let days: [(date: Date, isCompleted: Bool)]
    let colorName: String

    private var accent: Color {
        (HabitPalette(rawValue: colorName) ?? .coral).accent
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(days, id: \.date) { day in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(day.isCompleted ? accent : Color.primary.opacity(0.09))
                    .frame(height: 18)
                    .accessibilityLabel(day.isCompleted ? "已完成" : "未完成")
            }
        }
    }
}
