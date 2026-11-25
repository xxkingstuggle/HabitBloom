import AppIntents
import Foundation
import SwiftUI
import WidgetKit

private let remoteRequestTimeout: TimeInterval = 8
private let optionsRemoteRequestTimeout: TimeInterval = 1.5

struct HabitTimelineEntry: TimelineEntry {
    let date: Date
    let habits: [WidgetHabitSnapshot]
    let selectedHabitID: UUID?
    let selectedHabitName: String?

    var selectedHabit: WidgetHabitSnapshot {
        if let selectedHabitID,
           let selected = habits.first(where: { $0.id == selectedHabitID }) {
            return selected
        }
        if let selectedHabitName,
           let selected = habits.first(where: { $0.name == selectedHabitName }) {
            return selected
        }
        return habits.first ?? .placeholder
    }

    var viewIdentity: String {
        let habit = selectedHabit
        return [
            selectedHabitID?.uuidString ?? "default",
            selectedHabitName ?? "no-name",
            habit.id.uuidString,
            habit.cardStyle,
            habit.imageFileName ?? "no-image",
            String(habit.updatedAt.timeIntervalSince1970),
            habit.isCompletedToday ? "done" : "pending"
        ].joined(separator: "-")
    }
}

struct HabitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitTimelineEntry {
        HabitTimelineEntry(date: Date(), habits: [.placeholder], selectedHabitID: nil, selectedHabitName: nil)
    }

    func snapshot(for configuration: HabitSelectionIntent, in context: Context) async -> HabitTimelineEntry {
        let snapshot = await WidgetSnapshotStore.loadSnapshot(reason: "single snapshot")
        return HabitTimelineEntry(
            date: Date(),
            habits: snapshot.habits,
            selectedHabitID: configuration.habit?.uuid ?? snapshot.selectedHabitID,
            selectedHabitName: configuration.habit?.name
        )
    }

    func timeline(for configuration: HabitSelectionIntent, in context: Context) async -> Timeline<HabitTimelineEntry> {
        widgetLog("TimelineProvider start selectedID=\(configuration.habit?.id ?? "nil")")
        let snapshot = await WidgetSnapshotStore.loadSnapshot(reason: "single timeline")
        widgetLog("TimelineProvider loaded updatedAt=\(snapshot.updatedAt.iso8601LogString) selectedID=\(configuration.habit?.id ?? snapshot.selectedHabitID?.uuidString ?? "nil") habits=\(snapshot.habits.count)")
        let entry = HabitTimelineEntry(
            date: Date(),
            habits: snapshot.habits,
            selectedHabitID: configuration.habit?.uuid ?? snapshot.selectedHabitID,
            selectedHabitName: configuration.habit?.name
        )
        return widgetTimeline(with: entry)
    }
}

struct SimpleHabitProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitTimelineEntry {
        HabitTimelineEntry(date: Date(), habits: [.placeholder], selectedHabitID: nil, selectedHabitName: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitTimelineEntry) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let snapshot = await WidgetSnapshotStore.loadSnapshot(reason: "simple snapshot")
            completion(HabitTimelineEntry(date: Date(), habits: snapshot.habits, selectedHabitID: snapshot.selectedHabitID, selectedHabitName: nil))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitTimelineEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let snapshot = await WidgetSnapshotStore.loadSnapshot(reason: "simple timeline")
            let entry = HabitTimelineEntry(date: Date(), habits: snapshot.habits, selectedHabitID: snapshot.selectedHabitID, selectedHabitName: nil)
            completion(widgetTimeline(with: entry))
        }
    }
}

/// 15 分钟常规刷新 + 跨午夜后 5 秒各一个刷新点，保证 0 点后「今日」状态自动翻篇。
private func widgetTimeline(with entry: HabitTimelineEntry) -> Timeline<HabitTimelineEntry> {
    var entries = [entry]
    let calendar = Calendar.current
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())),
       let midnightEntry = calendar.date(byAdding: .second, value: 5, to: tomorrow) as Date? {
        entries.append(HabitTimelineEntry(
            date: midnightEntry,
            habits: entry.habits.map { habit in
                var copy = habit
                copy.isCompletedToday = false
                return copy
            },
            selectedHabitID: entry.selectedHabitID,
            selectedHabitName: entry.selectedHabitName
        ))
    }
    return Timeline(entries: entries, policy: .after(Date().addingTimeInterval(900)))
}

struct HabitSelectionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择目标"
    static let description = IntentDescription("选择这个小组件要显示的打卡目标。")

    @Parameter(title: "目标")
    var habit: HabitWidgetEntity?
}

struct HabitWidgetEntity: AppEntity {
    let id: String
    let name: String
    let detail: String

    var uuid: UUID? { UUID(uuidString: id) }

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "目标")
    static let defaultQuery = HabitWidgetEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }
}

struct HabitWidgetEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HabitWidgetEntity] {
        let entities = await loadWidgetEntities(reason: "entities")
        let entitiesByID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
        return identifiers.compactMap { identifier in
            if let entity = entitiesByID[identifier] {
                return entity
            }
            guard UUID(uuidString: identifier) != nil else {
                return nil
            }
            return HabitWidgetEntity(
                id: identifier,
                name: "默认目标",
                detail: "使用当前可用目标"
            )
        }
    }

    func suggestedEntities() async throws -> [HabitWidgetEntity] {
        await loadWidgetEntities(reason: "suggested")
    }

    func defaultResult() async -> HabitWidgetEntity? {
        await loadWidgetEntities(reason: "default").first
    }

    private func loadWidgetEntities(reason: String) async -> [HabitWidgetEntity] {
        let snapshot = await WidgetSnapshotStore.loadOptionsSnapshot(reason: reason)
        return snapshot.habits.map {
            HabitWidgetEntity(id: $0.id.uuidString, name: $0.name, detail: "连续 \($0.streakDays) 天")
        }
    }
}

enum WidgetSnapshotStore {
    static func loadSnapshot(reason: String) async -> WidgetRemoteSnapshot {
        let now = Date()
        let pending = WidgetPendingCheckInStore.load()

        if let remote = await RemoteWidgetClient.fetchSnapshot(reason: reason, timeout: remoteRequestTimeout) {
            let normalized = WidgetSnapshotRollover.overlayPendingCheckIns(remote, pending: pending, referenceDate: now)
            cache(normalized)
            widgetLog("using remote reason=\(reason) updatedAt=\(normalized.updatedAt.iso8601LogString) selectedID=\(normalized.selectedHabitID?.uuidString ?? "nil")")
            if !normalized.habits.isEmpty {
                return normalized
            }
            return placeholderSnapshot(reason: reason)
        }

        if let cached = cachedSnapshot(), !cached.habits.isEmpty {
            let normalized = WidgetSnapshotRollover.overlayPendingCheckIns(cached, pending: pending, referenceDate: now)
            widgetLog("using widget cache reason=\(reason) updatedAt=\(normalized.updatedAt.iso8601LogString) selectedID=\(normalized.selectedHabitID?.uuidString ?? "nil")")
            return normalized
        }

        if let appGroup = appGroupSnapshot(), !appGroup.habits.isEmpty {
            let normalized = WidgetSnapshotRollover.overlayPendingCheckIns(appGroup, pending: pending, referenceDate: now)
            widgetLog("using App Group fallback reason=\(reason) habits=\(normalized.habits.count)")
            return normalized
        }

        return placeholderSnapshot(reason: reason)
    }

    static func loadOptionsSnapshot(reason: String) async -> WidgetRemoteSnapshot {
        let now = Date()
        if let appGroup = appGroupSnapshot(), !appGroup.habits.isEmpty {
            let normalized = WidgetSnapshotRollover.rolledOver(appGroup, referenceDate: now)
            widgetLog("using App Group options reason=\(reason) habits=\(normalized.habits.count)")
            return normalized
        }

        if let cached = cachedSnapshot(), !cached.habits.isEmpty {
            let normalized = WidgetSnapshotRollover.rolledOver(cached, referenceDate: now)
            widgetLog("using widget cache options reason=\(reason) updatedAt=\(normalized.updatedAt.iso8601LogString) selectedID=\(normalized.selectedHabitID?.uuidString ?? "nil")")
            return normalized
        }

        if let remote = await RemoteWidgetClient.fetchSnapshot(reason: "options \(reason)", timeout: optionsRemoteRequestTimeout),
           !remote.habits.isEmpty {
            let normalized = WidgetSnapshotRollover.rolledOver(remote, referenceDate: now)
            cache(normalized)
            widgetLog("using remote options reason=\(reason) updatedAt=\(normalized.updatedAt.iso8601LogString) habits=\(normalized.habits.count)")
            return normalized
        }

        return placeholderSnapshot(reason: "options \(reason)")
    }

    static func saveCachedSnapshot(_ snapshot: WidgetRemoteSnapshot) {
        cache(snapshot)
    }

    private static func placeholderSnapshot(reason: String) -> WidgetRemoteSnapshot {
        let now = Date()
        widgetLog("using placeholder reason=\(reason)")
        return WidgetRemoteSnapshot(
            deviceKey: RemoteWidgetConfig.deviceKey,
            updatedAt: now,
            dayKey: WidgetDayKey.string(for: now),
            selectedHabitID: WidgetHabitSnapshot.placeholder.id,
            habits: [.placeholder]
        )
    }

    private static func cache(_ snapshot: WidgetRemoteSnapshot) {
        guard let data = try? widgetJSONEncoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: WidgetSharedDefaults.remoteSnapshotCacheKey)
    }

    private static func cachedSnapshot() -> WidgetRemoteSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: WidgetSharedDefaults.remoteSnapshotCacheKey) else { return nil }
        return try? widgetJSONDecoder.decode(WidgetRemoteSnapshot.self, from: data)
    }

    private static func appGroupSnapshot() -> WidgetRemoteSnapshot? {
        guard
            let data = WidgetSharedDefaults.suiteDefaults?.data(forKey: WidgetSharedDefaults.snapshotsKey),
            let snapshots = try? widgetJSONDecoder.decode([WidgetHabitSnapshot].self, from: data)
        else { return nil }

        return WidgetRemoteSnapshot(
            deviceKey: RemoteWidgetConfig.deviceKey,
            updatedAt: snapshots.map(\.updatedAt).max() ?? Date(),
            selectedHabitID: snapshots.first?.id,
            habits: snapshots
        )
    }
}

private enum RemoteWidgetClient {
    static func fetchSnapshot(reason: String, timeout: TimeInterval) async -> WidgetRemoteSnapshot? {
        guard RemoteWidgetConfig.isReadable else {
            widgetLog("remote GET skipped: config missing reason=\(reason)")
            return nil
        }
        guard var components = URLComponents(string: RemoteWidgetConfig.baseURLString) else {
            widgetLog("remote GET skipped: invalid base URL")
            return nil
        }

        components.path = "/v1/snapshot/\(RemoteWidgetConfig.deviceKey)"
        guard let url = components.url else {
            widgetLog("remote GET skipped: invalid URL")
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let startedAt = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                widgetLog("remote GET failed: bad status reason=\(reason)")
                return nil
            }
            let snapshot = try widgetJSONDecoder.decode(WidgetRemoteSnapshot.self, from: data)
            widgetLog("remote GET ok reason=\(reason) elapsed=\(Date().timeIntervalSince(startedAt))s updatedAt=\(snapshot.updatedAt.iso8601LogString) habits=\(snapshot.habits.count)")
            return snapshot
        } catch {
            widgetLog("remote GET failed reason=\(reason): \(error.localizedDescription)")
            return nil
        }
    }
}

struct SingleHabitWidgetView: View {
    let entry: HabitTimelineEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsContainerBackground
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var habit: WidgetHabitSnapshot { entry.selectedHabit }
    private var usesImagePresentation: Bool {
        habit.usesImageBackground
            && renderingMode == .fullColor
            && showsContainerBackground
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        WidgetIcon(systemName: habit.icon, colorName: habit.colorName, isOnImage: usesImagePresentation)
                        Spacer(minLength: 8)
                        Text(habit.isCompletedToday ? "今日已打卡" : "今日待完成")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(
                                usesImagePresentation
                                    ? .white
                                    : (habit.isCompletedToday ? color(for: habit.colorName) : .secondary)
                            )
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(widgetSurfaceFill(isOnImage: usesImagePresentation, colorScheme: colorScheme, reduceTransparency: reduceTransparency))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(widgetSurfaceStroke(isOnImage: usesImagePresentation, colorScheme: colorScheme, reduceTransparency: reduceTransparency), lineWidth: 0.8)
                            )
                        Spacer(minLength: 10)
                        WidgetCheckInButton(habit: habit, isOnImage: usesImagePresentation, size: 26)
                    }
                    Spacer(minLength: 6)
                    HStack(alignment: .bottom, spacing: 12) {
                        WidgetTextBlock(habit: habit, showsTotal: true, isOnImage: usesImagePresentation)
                        Spacer(minLength: 8)
                        DaysBlock(days: habit.streakDays, title: "连续", isOnImage: usesImagePresentation)
                    }
                    WidgetProgressBar(value: habit.effectiveCompletionRate, tintName: habit.colorName, isOnImage: usesImagePresentation)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        WidgetIcon(systemName: habit.icon, colorName: habit.colorName, isOnImage: usesImagePresentation)
                        Spacer()
                        WidgetCheckInButton(habit: habit, isOnImage: usesImagePresentation, size: 22)
                    }
                    Spacer(minLength: 8)
                    HStack(alignment: .bottom, spacing: 8) {
                        WidgetTextBlock(habit: habit, isOnImage: usesImagePresentation)
                        Spacer(minLength: 6)
                        DaysBlock(days: habit.streakDays, title: "连续", compact: true, isOnImage: usesImagePresentation)
                    }
                    WidgetProgressBar(value: habit.effectiveCompletionRate, tintName: habit.colorName, isOnImage: usesImagePresentation)
                }
            }
        }
        .padding()
    }
}

struct MultiHabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let entry: HabitTimelineEntry

    private var maxVisibleRows: Int {
        family == .systemLarge ? 6 : 3
    }

    var body: some View {
        let visibleHabits = Array(entry.habits.prefix(maxVisibleRows))
        let hiddenCount = max(0, entry.habits.count - visibleHabits.count)

        VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日打卡")
                    .font(.headline.weight(.bold))
                Spacer()
                Text("\(entry.habits.filter(\.isCompletedToday).count)/\(entry.habits.count)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ForEach(visibleHabits) { habit in
                HStack(spacing: 9) {
                    WidgetIcon(systemName: habit.icon, colorName: habit.colorName, size: family == .systemLarge ? 28 : 24, imageSize: family == .systemLarge ? 14 : 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(habit.name)
                            .font(family == .systemLarge ? .subheadline.weight(.semibold) : .footnote.weight(.semibold))
                            .lineLimit(1)
                        if family == .systemLarge {
                            Text(habit.isCompletedToday ? "今日已完成" : "待打卡")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 6)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(habit.streakDays)")
                            .font(family == .systemLarge ? .headline.weight(.bold) : .subheadline.weight(.bold))
                        Text("天")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                    WidgetCheckInButton(habit: habit, size: family == .systemLarge ? 20 : 18)
                }
                .font(.subheadline)
                .padding(.vertical, family == .systemLarge ? 5 : 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(widgetSurfaceFill(isOnImage: false, colorScheme: colorScheme, reduceTransparency: reduceTransparency))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(widgetSurfaceStroke(isOnImage: false, colorScheme: colorScheme, reduceTransparency: reduceTransparency), lineWidth: 0.8)
                )
            }

            if hiddenCount > 0 {
                Text("另有 \(hiddenCount) 项目标，打开 App 查看全部")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}

struct SummaryHabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let entry: HabitTimelineEntry

    private var completedCount: Int {
        entry.habits.filter(\.isCompletedToday).count
    }

    private var completionPercentage: Int {
        guard !entry.habits.isEmpty else { return 0 }
        return Int((Double(completedCount) / Double(entry.habits.count) * 100).rounded())
    }

    private var bestStreak: Int {
        entry.habits.map(\.streakDays).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("打卡概览")
                        .font(.headline.weight(.bold))
                    Text(family == .systemMedium ? "今日完成率 \(completionPercentage)%" : "今日已完成")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(completedCount)")
                        .font(.system(size: family == .systemMedium ? 40 : 34, weight: .bold, design: .rounded))
                    Text("/\(entry.habits.count)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }

            if family == .systemMedium {
                HStack(spacing: 8) {
                    summaryBadge(title: "最好连续", value: "\(bestStreak) 天", icon: "flame.fill", tint: .orange)
                    summaryBadge(title: "剩余目标", value: "\(max(0, entry.habits.count - completedCount)) 项", icon: "circle.dotted", tint: .teal)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                ForEach(entry.habits.prefix(family == .systemMedium ? 10 : 6)) { habit in
                    Capsule()
                        .fill(habit.isCompletedToday ? color(for: habit.colorName) : Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.14))
                        .frame(height: 8)
                }
            }
        }
        .padding()
    }

    private func summaryBadge(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(widgetSurfaceFill(isOnImage: false, colorScheme: colorScheme, reduceTransparency: reduceTransparency))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(widgetSurfaceStroke(isOnImage: false, colorScheme: colorScheme, reduceTransparency: reduceTransparency), lineWidth: 0.8)
        )
    }
}

struct WidgetBackground: View {
    let snapshot: WidgetHabitSnapshot

    var body: some View {
        WidgetStickerBackground(snapshot: snapshot)
    }
}

private struct WidgetCheckInButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let habit: WidgetHabitSnapshot
    var isOnImage = false
    var size: CGFloat = 22

    var body: some View {
        Button(intent: ToggleHabitCheckInIntent(habitID: habit.id)) {
            Image(systemName: habit.isCompletedToday ? "checkmark.circle.fill" : "circle")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(habit.isCompletedToday ? (isOnImage ? .white : .green) : (isOnImage ? .white.opacity(0.86) : .secondary))
                .symbolRenderingMode(.hierarchical)
                .frame(width: size + 14, height: size + 14)
                .background(widgetSurfaceFill(isOnImage: isOnImage, colorScheme: colorScheme, reduceTransparency: reduceTransparency), in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(widgetSurfaceStroke(isOnImage: isOnImage, colorScheme: colorScheme, reduceTransparency: reduceTransparency), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(habit.isCompletedToday ? "取消今日打卡" : "完成今日打卡")
    }
}

private struct WidgetTextBlock: View {
    let habit: WidgetHabitSnapshot
    var showsTotal = false
    var isOnImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(habit.name)
                .font(.headline.weight(.bold))
                .foregroundStyle(isOnImage ? .white : .primary)
                .lineLimit(2)
            if showsTotal {
                Text("累计 \(habit.totalDays) 天")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isOnImage ? .white.opacity(0.82) : .secondary)
            }
        }
    }
}

private struct WidgetIcon: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let systemName: String
    let colorName: String
    var size: CGFloat = 36
    var imageSize: CGFloat = 18
    var isOnImage = false

    var body: some View {
        WidgetIconGlyph(icon: systemName, size: systemName.isEmojiIcon ? imageSize + 8 : imageSize)
            .foregroundStyle(isOnImage ? .white : color(for: colorName))
            .symbolRenderingMode(.hierarchical)
            .frame(width: size, height: size)
            .background(widgetSurfaceFill(isOnImage: isOnImage, colorScheme: colorScheme, reduceTransparency: reduceTransparency), in: Circle())
            .overlay(
                Circle()
                    .strokeBorder(widgetSurfaceStroke(isOnImage: isOnImage, colorScheme: colorScheme, reduceTransparency: reduceTransparency), lineWidth: 0.8)
            )
    }
}

private struct WidgetIconGlyph: View {
    let icon: String
    var size: CGFloat

    var body: some View {
        if icon.isEmojiIcon {
            Text(icon)
                .font(.system(size: size))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
        }
    }
}

private struct DaysBlock: View {
    let days: Int
    let title: String
    var compact = false
    var isOnImage = false

    var body: some View {
        VStack(alignment: .trailing, spacing: compact ? 0 : 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(isOnImage ? .white.opacity(0.76) : .secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(days)")
                    .font(.system(size: compact ? 32 : 48, weight: .bold, design: .rounded))
                    .foregroundStyle(isOnImage ? .white : .primary)
                Text("天")
                    .font((compact ? Font.caption : Font.callout).weight(.bold))
                    .foregroundStyle(isOnImage ? .white.opacity(0.78) : .secondary)
            }
            .monospacedDigit()
        }
        .minimumScaleFactor(0.82)
    }
}

private struct WidgetProgressBar: View {
    let value: Double
    let tintName: String
    let isOnImage: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(isOnImage ? Color.white.opacity(0.24) : Color.primary.opacity(0.10))
                Capsule(style: .continuous)
                    .fill((isOnImage ? Color.white : color(for: tintName)).opacity(isOnImage ? 0.92 : 0.86))
                    .frame(width: max(8, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 7)
    }
}

private struct WidgetStickerBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: WidgetHabitSnapshot

    var body: some View {
        switch snapshot.cardStyle {
        case "glass":
            if reduceTransparency {
                Rectangle()
                    .fill(widgetSecondarySystemBackgroundColor)
                    .overlay(color(for: snapshot.colorName).opacity(colorScheme == .dark ? 0.18 : 0.12))
            } else {
                Rectangle()
                    .fill(.thinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.22),
                                color(for: snapshot.colorName).opacity(colorScheme == .dark ? 0.22 : 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        case "minimal":
            Rectangle()
                .fill(widgetSecondarySystemBackgroundColor)
                .overlay(color(for: snapshot.colorName).opacity(reduceTransparency ? 0.24 : 0.16), alignment: .leading)
        case "image":
            if let image = widgetImage(for: snapshot) {
                GeometryReader { proxy in
                    WidgetBackgroundImage(image: image)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .saturation(0.86)
                        .overlay(.black.opacity(reduceTransparency ? 0.34 : 0.20))
                        .overlay(
                            LinearGradient(
                                colors: [
                                    .black.opacity(reduceTransparency ? 0.54 : 0.36),
                                    .black.opacity(reduceTransparency ? 0.30 : 0.14),
                                    .black.opacity(reduceTransparency ? 0.62 : 0.42)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            } else {
                softBackground
            }
        default:
            softBackground
        }
    }

    private var softBackground: some View {
        Group {
            if reduceTransparency {
                Rectangle()
                    .fill(widgetSecondarySystemBackgroundColor)
                    .overlay(color(for: snapshot.colorName).opacity(colorScheme == .dark ? 0.18 : 0.12))
            } else {
                LinearGradient(
                    colors: [
                        color(for: snapshot.colorName).opacity(colorScheme == .dark ? 0.26 : 0.20),
                        color(for: snapshot.colorName).opacity(colorScheme == .dark ? 0.12 : 0.08),
                        widgetSystemBackgroundColor.opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

private struct WidgetBackgroundImage: View {
    let image: PlatformImage

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            Image(platformImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.desaturated)
        } else {
            Image(platformImage: image)
                .resizable()
        }
    }
}

struct SingleHabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SingleHabitWidget", intent: HabitSelectionIntent.self, provider: HabitProvider()) { entry in
            SingleHabitWidgetView(entry: entry)
                .id(entry.viewIdentity)
                .containerBackground(for: .widget) {
                    WidgetBackground(snapshot: entry.selectedHabit)
                }
        }
        .configurationDisplayName("单个目标")
        .description("显示一个目标和连续打卡天数，点圆圈即可打卡。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct MultiHabitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MultiHabitWidget", provider: SimpleHabitProvider()) { entry in
            MultiHabitWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground(snapshot: entry.selectedHabit)
                }
        }
        .configurationDisplayName("多个目标")
        .description("极简显示多个目标的连续天数，点圆圈即可打卡。")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct SummaryHabitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SummaryHabitWidget", provider: SimpleHabitProvider()) { entry in
            SummaryHabitWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground(snapshot: entry.selectedHabit)
                }
        }
        .configurationDisplayName("打卡概览")
        .description("显示今日完成数和整体状态。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct HabitBloomWidgetBundle: WidgetBundle {
    var body: some Widget {
        SingleHabitWidget()
        MultiHabitWidget()
        SummaryHabitWidget()
    }
}

extension WidgetHabitSnapshot {
    static let placeholder = WidgetHabitSnapshot(
        id: UUID(),
        name: "打开 App 刷新",
        icon: "arrow.triangle.2.circlepath",
        colorName: "mint",
        cardStyle: "soft",
        streakDays: 0,
        totalDays: 0,
        completionRate: 0.0,
        isCompletedToday: false,
        imageFileName: nil,
        imageData: nil,
        updatedAt: Date()
    )

    var effectiveCompletionRate: Double {
        min(max(completionRate, 0), 1)
    }

    var usesImageBackground: Bool {
        cardStyle == "image" && widgetImage(for: self) != nil
    }
}

private func color(for name: String) -> Color {
    switch name {
    case "mint": .green
    case "indigo": .indigo
    case "amber": .orange
    case "teal": .teal
    case "rose": .pink
    default: .red
    }
}

private var widgetSystemBackgroundColor: Color {
#if os(macOS)
    Color(nsColor: .windowBackgroundColor)
#else
    Color(uiColor: .systemBackground)
#endif
}

private var widgetSecondarySystemBackgroundColor: Color {
#if os(macOS)
    Color(nsColor: .controlBackgroundColor)
#else
    Color(uiColor: .secondarySystemBackground)
#endif
}

private func widgetSurfaceFill(isOnImage: Bool, colorScheme: ColorScheme, reduceTransparency: Bool) -> Color {
    if isOnImage {
        return reduceTransparency ? Color.black.opacity(0.58) : Color.black.opacity(0.30)
    }
    if reduceTransparency {
        return colorScheme == .dark ? Color.white.opacity(0.14) : widgetSystemBackgroundColor
    }
    return colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.62)
}

private func widgetSurfaceStroke(isOnImage: Bool, colorScheme: ColorScheme, reduceTransparency: Bool) -> Color {
    if isOnImage {
        return Color.white.opacity(reduceTransparency ? 0.45 : 0.24)
    }
    if reduceTransparency {
        return colorScheme == .dark ? Color.white.opacity(0.26) : Color.black.opacity(0.14)
    }
    return colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.52)
}

extension String {
    var isEmojiIcon: Bool {
        count <= 4 && unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }
}

private let widgetLogDateFormatStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

func widgetLog(_ message: String) {
    print("[HabitBloomWidgetRemote] \(Date().iso8601LogString) \(message)")
}

private extension Date {
    var iso8601LogString: String {
        formatted(widgetLogDateFormatStyle)
    }
}

private func widgetImage(for snapshot: WidgetHabitSnapshot) -> PlatformImage? {
    if let imageFileName = snapshot.imageFileName,
       let imageDirectory = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: WidgetSharedDefaults.appGroupIdentifier)?
        .appendingPathComponent("WidgetImages", isDirectory: true) {
        let imageURL = imageDirectory.appendingPathComponent(imageFileName)
        if let data = try? Data(contentsOf: imageURL),
           let image = platformImage(from: data) {
            return image
        }
    }

    return platformImage(from: snapshot.imageData)
}

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage

private func platformImage(from data: Data?) -> PlatformImage? {
    guard let data else { return nil }
    return NSImage(data: data)
}

private extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}
#else
import UIKit
typealias PlatformImage = UIImage

private func platformImage(from data: Data?) -> PlatformImage? {
    guard let data else { return nil }
    return UIImage(data: data)
}

private extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}
#endif
