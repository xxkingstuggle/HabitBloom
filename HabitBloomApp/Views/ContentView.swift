import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: [SortDescriptor(\HabitEntity.sortOrder), SortDescriptor(\HabitEntity.createdAt)]) private var habits: [HabitEntity]
    @State private var showingEditor = false
    @State private var selectedHabit: HabitEntity?
    @State private var selectedTab = MainTab.home
    @State private var statsByHabitID: [UUID: HabitStatsViewModel] = [:]
    @State private var completedTodayByHabitID: [UUID: Bool] = [:]
    @State private var noteDraft: NoteDraft?
    @State private var today = Calendar.current.startOfDay(for: Date())

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
                                Label("新建目标", systemImage: "plus")
                            }
                            .keyboardShortcut("n", modifiers: .command)
                            .accessibilityLabel("新建目标")
                        }
                    }
            }
            .tabItem {
                Label("首页", systemImage: "house")
            }
            .tag(MainTab.home)

            NavigationStack {
                StatsView(
                    habits: habits,
                    statsByHabitID: statsByHabitID,
                    onToggleDay: toggleCheckIn,
                    onEditNote: { habit, day in
                        noteDraft = NoteDraft(habit: habit, day: day, note: note(for: habit, on: day))
                    }
                )
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
        .sheet(item: $noteDraft, onDismiss: {
            refreshDerivedStateAndWidgets(delayMilliseconds: 0, backupDelayMilliseconds: 2_500)
        }) { draft in
            DayNoteEditorView(day: draft.day, habitName: draft.habit.name, initialNote: draft.note) { newNote in
                saveNote(newNote, for: draft.habit, on: draft.day)
            }
        }
        .task {
            let mergeResult = await StartupSyncCoordinator.shared.ensureInitialSync(using: modelContext)
            today = Calendar.current.startOfDay(for: Date())
            refreshDerivedStateAndWidgets(
                delayMilliseconds: mergeResult.didChange ? 0 : 80,
                backupDelayMilliseconds: mergeResult.didChange ? 2_500 : nil
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .habitBloomDidMergeWidgetCheckIns)) { _ in
            today = Calendar.current.startOfDay(for: Date())
            refreshDerivedState(habits: habits)
        }
        .onReceive(NotificationCenter.default.publisher(for: .habitBloomRequestNewHabit)) { _ in
            selectedTab = .home
            showingEditor = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .habitBloomSelectTab)) { notification in
            if let rawValue = notification.object as? Int,
               let target = MainTab(rawValue: rawValue) {
                selectedTab = target
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = Calendar.current.startOfDay(for: Date())
            refreshDerivedStateAndWidgets()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    let mergeResult = await StartupSyncCoordinator.shared.performForegroundSync(using: modelContext)
                    today = Calendar.current.startOfDay(for: Date())
                    refreshDerivedStateAndWidgets(
                        delayMilliseconds: mergeResult.didChange ? 0 : 80,
                        backupDelayMilliseconds: mergeResult.didChange ? 2_500 : nil
                    )
                }
            } else if phase == .background {
                refreshDerivedStateAndWidgets(delayMilliseconds: 0)
            }
        }
    }

    private var cardGridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [
                GridItem(.flexible(minimum: 280), spacing: 16),
                GridItem(.flexible(minimum: 280), spacing: 16)
            ]
        }
        return [GridItem(.flexible())]
    }

    @ViewBuilder
    private var homeContent: some View {
        if habits.isEmpty {
            EmptyHabitView(
                onCreateCustom: { showingEditor = true },
                onCreateTemplate: createHabit(from:)
            )
        } else {
            let dueToday = habitsDueToday
            let restingToday = habitsRestingToday
            let completedDueToday = dueToday.filter { completedTodayByHabitID[$0.id] == true }.count

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TodaySummaryHeader(
                        today: today,
                        totalCount: dueToday.count,
                        completedToday: completedDueToday,
                        bestStreak: habits.compactMap { statsByHabitID[$0.id]?.currentStreak }.max() ?? 0
                    )

                    if !dueToday.isEmpty {
                        LazyVGrid(columns: cardGridColumns, spacing: 16) {
                            ForEach(Array(dueToday.enumerated()), id: \.element.id) { index, habit in
                                habitCard(habit, feedbackLevel: index)
                            }
                        }
                    }

                    if !restingToday.isEmpty {
                        HStack(spacing: 8) {
                            Text("今日休息")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("今天不是这些目标的打卡日")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 6)

                        LazyVGrid(columns: cardGridColumns, spacing: 16) {
                            ForEach(Array(restingToday.enumerated()), id: \.element.id) { index, habit in
                                habitCard(habit, feedbackLevel: index, isResting: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: 1080)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(AppBackground())
        }
    }

    @ViewBuilder
    private func habitCard(_ habit: HabitEntity, feedbackLevel: Int, isResting: Bool = false) -> some View {
        let isCompleted = completedTodayByHabitID[habit.id] ?? false
        HabitCardView(
            habit: habit,
            stats: statsByHabitID[habit.id] ?? .empty,
            isCompletedToday: isCompleted,
            feedbackLevel: feedbackLevel
        ) {
            toggleToday(for: habit)
        }
        .opacity(isResting ? 0.62 : 1)
        .saturation(isResting ? 0.72 : 1)
        .onTapGesture {
            selectedHabit = habit
        }
        .contextMenu {
            let currentIndex = habits.firstIndex(where: { $0.id == habit.id })
            Button {
                toggleToday(for: habit)
            } label: {
                Label(isCompleted ? "取消今日打卡" : "完成今日打卡", systemImage: isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }
            Button {
                selectedHabit = habit
            } label: {
                Label("编辑目标", systemImage: "pencil")
            }
            Button {
                noteDraft = NoteDraft(habit: habit, day: today, note: note(for: habit, on: today))
            } label: {
                Label("今日备注", systemImage: "note.text")
            }
            Divider()
            Button {
                move(habit, by: -1)
            } label: {
                Label("上移", systemImage: "arrow.up")
            }
                .disabled(currentIndex == nil || currentIndex == 0)
            Button {
                move(habit, by: 1)
            } label: {
                Label("下移", systemImage: "arrow.down")
            }
                .disabled(currentIndex == nil || currentIndex == habits.count - 1)
            Divider()
            Button(role: .destructive) {
                delete(habit)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var habitsDueToday: [HabitEntity] {
        let weekday = Calendar.current.component(.weekday, from: today)
        return habits.filter { WeekdayMask.contains(weekday, in: $0.targetWeekdayMask) }
    }

    private var habitsRestingToday: [HabitEntity] {
        let weekday = Calendar.current.component(.weekday, from: today)
        return habits.filter { !WeekdayMask.contains(weekday, in: $0.targetWeekdayMask) }
    }

    private func toggleToday(for habit: HabitEntity) {
        toggleCheckIn(for: habit, on: today)
    }

    private func toggleCheckIn(for habit: HabitEntity, on day: Date) {
        let calendar = Calendar.current
        let normalizedDay = calendar.startOfDay(for: day)
        let now = Date()
        let willComplete: Bool
        let sameDayRecords = (habit.checkIns ?? []).filter { calendar.startOfDay(for: $0.day) == normalizedDay }
        if let keeper = sameDayRecords.max(by: { $0.createdAt < $1.createdAt }) {
            keeper.day = normalizedDay
            for duplicate in sameDayRecords where duplicate.id != keeper.id {
                if keeper.note.isEmpty, !duplicate.note.isEmpty {
                    keeper.note = duplicate.note
                }
                modelContext.delete(duplicate)
            }
            keeper.isCompleted.toggle()
            keeper.createdAt = now
            willComplete = keeper.isCompleted
        } else {
            var checkIns = habit.checkIns ?? []
            checkIns.append(CheckInEntity(day: normalizedDay, createdAt: now, habit: habit))
            habit.checkIns = checkIns
            willComplete = true
        }

        guard saveModelContext(action: "toggle check-in") else { return }
        let derived = refreshDerivedState(habits: habits)

        if normalizedDay == today {
            WidgetSnapshotWriter.scheduleCheckIn(
                habitID: habit.id,
                isCompletedToday: willComplete,
                habits: habits,
                statsByHabitID: derived.stats,
                completedTodayByHabitID: derived.completedToday
            )
            if willComplete {
                Task { await ReminderScheduler.suppressTodayIfNeeded(for: ReminderScheduleSnapshot(habit: habit)) }
            } else {
                Task { await ReminderScheduler.restoreTodayIfNeeded(for: ReminderScheduleSnapshot(habit: habit)) }
            }
        } else {
            refreshDerivedStateAndWidgets(delayMilliseconds: 0, backupDelayMilliseconds: 2_500)
        }
    }

    private func note(for habit: HabitEntity, on day: Date) -> String {
        let calendar = Calendar.current
        let normalizedDay = calendar.startOfDay(for: day)
        return (habit.checkIns ?? [])
            .filter { calendar.startOfDay(for: $0.day) == normalizedDay }
            .max(by: { $0.createdAt < $1.createdAt })?
            .note ?? ""
    }

    private func saveNote(_ note: String, for habit: HabitEntity, on day: Date) {
        let calendar = Calendar.current
        let normalizedDay = calendar.startOfDay(for: day)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let sameDay = (habit.checkIns ?? []).filter { calendar.startOfDay(for: $0.day) == normalizedDay }
        if let keeper = sameDay.max(by: { $0.createdAt < $1.createdAt }) {
            keeper.day = normalizedDay
            for duplicate in sameDay where duplicate.id != keeper.id {
                modelContext.delete(duplicate)
            }
            keeper.note = trimmed
        } else {
            var checkIns = habit.checkIns ?? []
            checkIns.append(CheckInEntity(day: normalizedDay, isCompleted: false, note: trimmed, habit: habit))
            habit.checkIns = checkIns
        }

        guard saveModelContext(action: "save day note") else { return }
        refreshDerivedState(habits: habits)
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
        let habitID = habit.id
        let remainingHabits = habits.filter { $0.id != habitID }
        modelContext.delete(habit)
        guard saveModelContext(action: "delete habit") else { return }
        ReminderScheduler.removeReminders(for: habitID)
        refreshDerivedStateAndWidgets(habits: remainingHabits, delayMilliseconds: 0, backupDelayMilliseconds: 2_500)
    }

    private func createHabit(from template: QuickHabitTemplate) {
        let nextSortOrder = (habits.map(\.sortOrder).max() ?? -1) + 1
        let created = HabitEntity(
            name: template.name,
            icon: template.icon,
            colorName: template.palette.rawValue,
            cardStyle: template.cardKind.rawValue,
            targetWeekdayMask: template.targetWeekdayMask,
            sortOrder: nextSortOrder
        )
        modelContext.insert(created)
        guard saveModelContext(action: "create template habit") else { return }
        var updatedHabits = habits
        updatedHabits.append(created)
        refreshDerivedStateAndWidgets(habits: updatedHabits, delayMilliseconds: 0, backupDelayMilliseconds: 2_500)
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

private enum MainTab: Int, Hashable {
    case home = 0
    case stats = 1
    case settings = 2
}

private struct QuickHabitTemplate: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let palette: HabitPalette
    let cardKind: HabitCardKind
    let targetWeekdayMask: Int

    static let presets: [QuickHabitTemplate] = [
        QuickHabitTemplate(
            id: "morning-water",
            name: "晨间喝水",
            subtitle: "每天 · 唤醒身体",
            icon: "drop.fill",
            palette: .teal,
            cardKind: .soft,
            targetWeekdayMask: WeekdayMask.all
        ),
        QuickHabitTemplate(
            id: "focus-reading",
            name: "专注阅读 20 分钟",
            subtitle: "每天 · 长期复利",
            icon: "book.fill",
            palette: .indigo,
            cardKind: .glass,
            targetWeekdayMask: WeekdayMask.all
        ),
        QuickHabitTemplate(
            id: "outdoor-walk",
            name: "户外快走",
            subtitle: "工作日 · 保持活力",
            icon: "figure.walk",
            palette: .mint,
            cardKind: .soft,
            targetWeekdayMask: WeekdayMask.workdays
        ),
        QuickHabitTemplate(
            id: "daily-review",
            name: "睡前复盘",
            subtitle: "每天 · 留痕沉淀",
            icon: "sparkles",
            palette: .amber,
            cardKind: .minimal,
            targetWeekdayMask: WeekdayMask.all
        )
    ]
}

private struct NoteDraft: Identifiable {
    let habit: HabitEntity
    let day: Date
    let note: String

    var id: String { "\(habit.id.uuidString)-\(day.timeIntervalSince1970)" }
}

private struct EmptyHabitView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var onCreateCustom: () -> Void
    var onCreateTemplate: (QuickHabitTemplate) -> Void

    private let templateColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.22), Color.pink.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 86, height: 86)
                        Image(systemName: "sparkles")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.orange, .pink)
                    }

                    VStack(spacing: 8) {
                        Text("开始第一张打卡卡片")
                            .font(.title2.weight(.bold))
                        Text("挑选一个常用模板快速起步，或自定义专属图标、配色、贴纸与桌面小组件。")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 420)
                    }

                    Button(action: onCreateCustom) {
                        Label("自定义新建目标", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                    .liquidGlassProminentButton()
                }
                .padding(.top, 28)

                VStack(alignment: .leading, spacing: 12) {
                    Text("一键快速模板")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: templateColumns, spacing: 12) {
                        ForEach(QuickHabitTemplate.presets) { template in
                            Button {
                                onCreateTemplate(template)
                            } label: {
                                HStack(spacing: 12) {
                                    HabitIconGlyph(icon: template.icon, size: 20)
                                        .foregroundStyle(template.palette.accent)
                                        .frame(width: 40, height: 40)
                                        .background(template.palette.accent.opacity(colorScheme == .dark ? 0.22 : 0.14), in: Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.primary)
                                        Text(template.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 4)

                                    Image(systemName: "plus.circle")
                                        .font(.title3)
                                        .foregroundStyle(template.palette.accent)
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.adaptiveChipSurface(for: colorScheme, reduceTransparency: reduceTransparency))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(Color.adaptiveCardBorder(for: colorScheme, reduceTransparency: reduceTransparency), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 720)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(AppBackground())
    }
}

private struct TodaySummaryHeader: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let today: Date
    let totalCount: Int
    let completedToday: Int
    let bestStreak: Int

    private var completionRatio: Double {
        guard totalCount > 0 else { return 0 }
        return min(max(Double(completedToday) / Double(totalCount), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今日")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(today.formatted(date: .complete, time: .omitted))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: completionRatio)
                        .stroke(
                            AngularGradient(colors: [.teal, .green, .cyan, .teal], center: .center),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((completionRatio * 100).rounded()))%")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
                .frame(width: 50, height: 50)
                .accessibilityLabel("今日完成进度 \(Int((completionRatio * 100).rounded()))%")
            }

            HStack(spacing: 12) {
                SummaryChip(title: "今日完成", value: "\(completedToday)/\(totalCount)", icon: "checkmark.circle.fill", tint: .green)
                SummaryChip(title: "最好连续", value: "\(bestStreak) 天", icon: "flame.fill", tint: .orange)
            }
        }
        .padding(18)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.appBackgroundSecondary)
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(colorScheme == .dark ? 0.22 : 0.14),
                                Color.mint.opacity(colorScheme == .dark ? 0.14 : 0.08),
                                Color.appBackgroundSecondary.opacity(colorScheme == .dark ? 0.96 : 0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.adaptiveCardBorder(for: colorScheme, reduceTransparency: reduceTransparency), lineWidth: 1)
        )
        .shadow(color: Color.cyan.opacity(colorScheme == .dark ? 0.16 : 0.09), radius: 16, y: 8)
    }
}

private struct SummaryChip: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

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
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.adaptiveChipSurface(for: colorScheme, reduceTransparency: reduceTransparency))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.adaptiveCardBorder(for: colorScheme, reduceTransparency: reduceTransparency).opacity(0.7), lineWidth: 0.8)
        )
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
