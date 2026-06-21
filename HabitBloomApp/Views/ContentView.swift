import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: [SortDescriptor(\HabitEntity.sortOrder), SortDescriptor(\HabitEntity.createdAt)]) private var habits: [HabitEntity]
    @State private var showingEditor = false
    @State private var selectedHabit: HabitEntity?
    @State private var selectedTab = MainTab.home
    @State private var statsByHabitID: [UUID: HabitStatsViewModel] = [:]
    @State private var completedTodayByHabitID: [UUID: Bool] = [:]

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                homeContent
                    .navigationTitle("首页")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingEditor = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("新建目标")
                        }
                    }
            }
            .tabItem {
                Label("首页", systemImage: "house")
            }
            .tag(MainTab.home)

            NavigationStack {
                StatsView(habits: habits, statsByHabitID: statsByHabitID)
            }
            .tabItem {
                Label("统计", systemImage: "chart.bar.xaxis")
            }
            .tag(MainTab.stats)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
            .tag(MainTab.settings)
        }
        .tint(.accentColor)
        #if targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $showingEditor, onDismiss: {
            refreshDerivedStateAndWidgets()
        }) {
            HabitEditorView(habit: nil)
        }
        .fullScreenCover(item: $selectedHabit, onDismiss: {
            refreshDerivedStateAndWidgets()
        }) { habit in
            HabitEditorView(habit: habit)
        }
        #else
        .sheet(isPresented: $showingEditor, onDismiss: {
            refreshDerivedStateAndWidgets()
        }) {
            HabitEditorView(habit: nil)
        }
        .sheet(item: $selectedHabit, onDismiss: {
            refreshDerivedStateAndWidgets()
        }) { habit in
            HabitEditorView(habit: habit)
        }
        #endif
        .task {
            refreshDerivedStateAndWidgets()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshDerivedStateAndWidgets()
            } else if phase == .background {
                refreshDerivedStateAndWidgets(delayMilliseconds: 0)
            }
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        if habits.isEmpty {
            EmptyHabitView {
                showingEditor = true
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    TodaySummaryHeader(
                        totalCount: habits.count,
                        completedToday: habits.filter { completedTodayByHabitID[$0.id] == true }.count,
                        bestStreak: habits.compactMap { statsByHabitID[$0.id]?.currentStreak }.max() ?? 0
                    )

                    ForEach(Array(habits.enumerated()), id: \.element.id) { index, habit in
                        HabitCardView(
                            habit: habit,
                            stats: statsByHabitID[habit.id] ?? .empty,
                            isCompletedToday: completedTodayByHabitID[habit.id] ?? false,
                            feedbackLevel: index
                        ) {
                            toggleToday(for: habit)
                        }
                        .onTapGesture {
                            selectedHabit = habit
                        }
                        .contextMenu {
                            Button("编辑") { selectedHabit = habit }
                            Button("上移") { move(habit, by: -1) }
                                .disabled(index == 0)
                            Button("下移") { move(habit, by: 1) }
                                .disabled(index == habits.count - 1)
                            Button("删除", role: .destructive) { delete(habit) }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
        }
    }

    private func toggleToday(for habit: HabitEntity) {
        let today = Calendar.current.startOfDay(for: Date())
        let willComplete: Bool
        if let existing = (habit.checkIns ?? []).first(where: { $0.day == today }) {
            existing.isCompleted.toggle()
            willComplete = existing.isCompleted
        } else {
            var checkIns = habit.checkIns ?? []
            checkIns.append(CheckInEntity(day: today, habit: habit))
            habit.checkIns = checkIns
            willComplete = true
        }

        guard saveModelContext(action: "toggle today") else { return }
        let derived = refreshDerivedState(habits: habits)
        WidgetSnapshotWriter.scheduleCheckIn(
            habitID: habit.id,
            isCompletedToday: willComplete,
            habits: habits,
            statsByHabitID: derived.stats,
            completedTodayByHabitID: derived.completedToday
        )
    }

    private func move(_ habit: HabitEntity, by offset: Int) {
        var orderedHabits = habits
        guard
            let currentIndex = orderedHabits.firstIndex(where: { $0.id == habit.id }),
            orderedHabits.indices.contains(currentIndex + offset)
        else { return }

        orderedHabits.swapAt(currentIndex, currentIndex + offset)
        for (index, habit) in orderedHabits.enumerated() {
            habit.sortOrder = index
        }

        guard saveModelContext(action: "move habit") else { return }
        refreshDerivedStateAndWidgets(habits: orderedHabits, delayMilliseconds: 0, backupDelayMilliseconds: 2_500)
    }

    private func delete(_ habit: HabitEntity) {
        modelContext.delete(habit)
        guard saveModelContext(action: "delete habit") else { return }
        refreshDerivedStateAndWidgets(delayMilliseconds: 0, backupDelayMilliseconds: 2_500)
    }

    private func refreshDerivedStateAndWidgets(
        habits sourceHabits: [HabitEntity]? = nil,
        delayMilliseconds: UInt64 = 80,
        backupDelayMilliseconds: UInt64? = nil
    ) {
        let sourceHabits = sourceHabits ?? habits
        let derived = refreshDerivedState(habits: sourceHabits)
        WidgetSnapshotWriter.scheduleWrite(
            habits: sourceHabits,
            statsByHabitID: derived.stats,
            completedTodayByHabitID: derived.completedToday,
            delayMilliseconds: delayMilliseconds,
            backupDelayMilliseconds: backupDelayMilliseconds
        )
    }

    @discardableResult
    private func refreshDerivedState(habits sourceHabits: [HabitEntity]) -> (stats: [UUID: HabitStatsViewModel], completedToday: [UUID: Bool]) {
        let derived = HabitStatsService.derivedState(for: sourceHabits)
        statsByHabitID = derived.statsByHabitID
        completedTodayByHabitID = derived.completedTodayByHabitID
        return (derived.statsByHabitID, derived.completedTodayByHabitID)
    }

    private func saveModelContext(action: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            print("[HabitBloomModel] Failed to save during \(action): \(error.localizedDescription)")
            return false
        }
    }

}

private enum MainTab: Hashable {
    case home
    case stats
    case settings
}

private struct EmptyHabitView: View {
    var action: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "sparkles")
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(.yellow, .pink)

            VStack(spacing: 8) {
                Text("开始第一张打卡卡片")
                    .font(.title2.weight(.bold))
                Text("设置目标、颜色、图标和提醒，然后把它放到桌面小组件里。")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320)
            }

            Button(action: action) {
                Label("新建目标", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            .liquidGlassProminentButton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
    }
}

private struct TodaySummaryHeader: View {
    let totalCount: Int
    let completedToday: Int
    let bestStreak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今日")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(Date.now.formatted(date: .complete, time: .omitted))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.yellow, .cyan)
            }

            HStack(spacing: 12) {
                SummaryChip(title: "完成", value: "\(completedToday)/\(totalCount)", icon: "checkmark.circle.fill", tint: .green)
                SummaryChip(title: "最好连续", value: "\(bestStreak) 天", icon: "flame.fill", tint: .orange)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.12),
                            Color.mint.opacity(0.06),
                            Color(.systemBackground).opacity(0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.26), lineWidth: 1)
        )
        .shadow(color: Color.cyan.opacity(0.09), radius: 16, y: 8)
    }
}

private struct SummaryChip: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.headline)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.weight(.bold))
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color.appBackgroundPrimary
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.035),
                    Color.clear,
                    Color.appBackgroundSecondary.opacity(0.65)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}
