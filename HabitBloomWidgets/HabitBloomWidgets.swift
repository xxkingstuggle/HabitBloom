import AppIntents
import Foundation
import SwiftUI
import WidgetKit

private let suiteName = "group.com.zjx.HabitBloom"
private let snapshotsKey = "habitWidgetSnapshots"
private let remoteSnapshotCacheKey = "remoteWidgetSnapshot"
private let remoteRequestTimeout: TimeInterval = 8
private let optionsRemoteRequestTimeout: TimeInterval = 1.5

private enum RemoteWidgetConfig {
    static let baseURLString = infoValue(for: "HBRemoteBaseURL")
    static let deviceKey = infoValue(for: "HBRemoteDeviceKey")

    static var isConfigured: Bool {
        baseURLString.hasPrefix("https://")
            && !baseURLString.contains("$(")
            && !deviceKey.isEmpty
            && !deviceKey.contains("$(")
    }

    private static func infoValue(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WidgetRemoteSnapshot: Codable {
    var deviceKey: String
    var updatedAt: Date
    var selectedHabitID: UUID?
    var habits: [WidgetHabitSnapshot]
}

struct WidgetHabitSnapshot: Identifiable, Codable {
    var id: UUID
    var name: String
    var icon: String
    var colorName: String
    var cardStyle: String? = nil
    var streakDays: Int
    var totalDays: Int
    var completionRate: Double? = nil
    var isCompletedToday: Bool
    var imageFileName: String? = nil
    var imageData: Data? = nil
    var updatedAt: Date? = nil

    var effectiveCardStyle: String {
        cardStyle ?? "soft"
    }

    var effectiveCompletionRate: Double {
        min(max(completionRate ?? 0, 0), 1)
    }
}

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
            habit.effectiveCardStyle,
            habit.imageFileName ?? "no-image",
            String(habit.updatedAt?.timeIntervalSince1970 ?? 0)
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
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
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
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
        }
    }
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

private enum WidgetSnapshotStore {
    static func loadSnapshot(reason: String) async -> WidgetRemoteSnapshot {
        if let remote = await RemoteWidgetClient.fetchSnapshot(reason: reason, timeout: remoteRequestTimeout) {
            cache(remote)
            widgetLog("using remote reason=\(reason) updatedAt=\(remote.updatedAt.iso8601LogString) selectedID=\(remote.selectedHabitID?.uuidString ?? "nil")")
            if !remote.habits.isEmpty {
                return remote
            }
            return placeholderSnapshot(reason: reason)
        }

        if let cached = cachedSnapshot(), !cached.habits.isEmpty {
            widgetLog("using widget cache reason=\(reason) updatedAt=\(cached.updatedAt.iso8601LogString) selectedID=\(cached.selectedHabitID?.uuidString ?? "nil")")
            return cached
        }

        if let appGroup = appGroupSnapshot(), !appGroup.habits.isEmpty {
            widgetLog("using App Group fallback reason=\(reason) habits=\(appGroup.habits.count)")
            return appGroup
        }

        return placeholderSnapshot(reason: reason)
    }

    static func loadOptionsSnapshot(reason: String) async -> WidgetRemoteSnapshot {
        if let appGroup = appGroupSnapshot(), !appGroup.habits.isEmpty {
            widgetLog("using App Group options reason=\(reason) habits=\(appGroup.habits.count)")
            return appGroup
        }

        if let cached = cachedSnapshot(), !cached.habits.isEmpty {
            widgetLog("using widget cache options reason=\(reason) updatedAt=\(cached.updatedAt.iso8601LogString) selectedID=\(cached.selectedHabitID?.uuidString ?? "nil")")
            return cached
        }

        if let remote = await RemoteWidgetClient.fetchSnapshot(reason: "options \(reason)", timeout: optionsRemoteRequestTimeout),
           !remote.habits.isEmpty {
            cache(remote)
            widgetLog("using remote options reason=\(reason) updatedAt=\(remote.updatedAt.iso8601LogString) habits=\(remote.habits.count)")
            return remote
        }

        return placeholderSnapshot(reason: "options \(reason)")
    }

    private static func placeholderSnapshot(reason: String) -> WidgetRemoteSnapshot {
        widgetLog("using placeholder reason=\(reason)")
        return WidgetRemoteSnapshot(
            deviceKey: RemoteWidgetConfig.deviceKey,
            updatedAt: Date(),
            selectedHabitID: WidgetHabitSnapshot.placeholder.id,
            habits: [.placeholder]
        )
    }

    private static func cache(_ snapshot: WidgetRemoteSnapshot) {
        guard let data = try? widgetJSONEncoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: remoteSnapshotCacheKey)
    }

    private static func cachedSnapshot() -> WidgetRemoteSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: remoteSnapshotCacheKey) else { return nil }
        return try? widgetJSONDecoder.decode(WidgetRemoteSnapshot.self, from: data)
    }

    private static func appGroupSnapshot() -> WidgetRemoteSnapshot? {
        guard
            let data = UserDefaults(suiteName: suiteName)?.data(forKey: snapshotsKey),
            let snapshots = try? widgetJSONDecoder.decode([WidgetHabitSnapshot].self, from: data)
        else { return nil }

        return WidgetRemoteSnapshot(
            deviceKey: RemoteWidgetConfig.deviceKey,
            updatedAt: snapshots.map(\.updatedAt).compactMap { $0 }.max() ?? Date(),
            selectedHabitID: snapshots.first?.id,
            habits: snapshots
        )
    }
}

private enum RemoteWidgetClient {
    static func fetchSnapshot(reason: String, timeout: TimeInterval) async -> WidgetRemoteSnapshot? {
        guard RemoteWidgetConfig.isConfigured else {
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

    private var habit: WidgetHabitSnapshot { entry.selectedHabit }

    var body: some View {
        ZStack(alignment: .topLeading) {
            WidgetStickerBackground(snapshot: habit)

            Group {
                if family == .systemMedium {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            WidgetIcon(systemName: habit.icon, colorName: habit.colorName, isOnImage: habit.usesImageBackground)
                            Spacer(minLength: 10)
                            CompletionDot(isCompleted: habit.isCompletedToday, isOnImage: habit.usesImageBackground)
                        }
                        Spacer(minLength: 6)
                        HStack(alignment: .bottom, spacing: 12) {
                            WidgetTextBlock(habit: habit, showsTotal: true)
                            Spacer(minLength: 8)
                            DaysBlock(days: habit.streakDays, title: "连续", isOnImage: habit.usesImageBackground)
                        }
                        WidgetProgressBar(value: habit.effectiveCompletionRate, tintName: habit.colorName, isOnImage: habit.usesImageBackground)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            WidgetIcon(systemName: habit.icon, colorName: habit.colorName, isOnImage: habit.usesImageBackground)
                            Spacer()
                            CompletionDot(isCompleted: habit.isCompletedToday, isOnImage: habit.usesImageBackground)
                        }
                        Spacer(minLength: 8)
                        HStack(alignment: .bottom, spacing: 8) {
                            WidgetTextBlock(habit: habit)
                            Spacer(minLength: 6)
                            DaysBlock(days: habit.streakDays, title: "连续", compact: true, isOnImage: habit.usesImageBackground)
                        }
                        WidgetProgressBar(value: habit.effectiveCompletionRate, tintName: habit.colorName, isOnImage: habit.usesImageBackground)
                    }
                }
            }
            .padding()
        }
    }
}

struct MultiHabitWidgetView: View {
    let entry: HabitTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日打卡")
                    .font(.headline.weight(.bold))
                Spacer()
                Text("\(entry.habits.filter(\.isCompletedToday).count)/\(entry.habits.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            ForEach(entry.habits.prefix(5)) { habit in
                HStack(spacing: 10) {
                    WidgetIcon(systemName: habit.icon, colorName: habit.colorName, size: 28, imageSize: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(habit.name)
                            .lineLimit(1)
                        Text(habit.isCompletedToday ? "今日已完成" : "今日未完成")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(habit.streakDays)")
                            .font(.headline.weight(.bold))
                        Text("天")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
                .font(.subheadline)
                .padding(.vertical, 5)
                .padding(.horizontal, 7)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding()
    }
}

struct SummaryHabitWidgetView: View {
    let entry: HabitTimelineEntry

    private var completedCount: Int {
        entry.habits.filter(\.isCompletedToday).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("打卡概览")
                        .font(.headline.weight(.bold))
                    Text("今日已完成")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(completedCount)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("/\(entry.habits.count)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(entry.habits.prefix(8)) { habit in
                    Capsule()
                        .fill(habit.isCompletedToday ? color(for: habit.colorName) : Color.secondary.opacity(0.22))
                        .frame(height: 8)
                }
            }
        }
        .padding()
    }
}

struct WidgetBackground: View {
    let snapshot: WidgetHabitSnapshot

    var body: some View {
        WidgetStickerBackground(snapshot: snapshot)
    }
}

private struct WidgetTextBlock: View {
    let habit: WidgetHabitSnapshot
    var showsTotal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(habit.name)
                .font(.headline.weight(.bold))
                .foregroundStyle(habit.usesImageBackground ? .white : .primary)
                .lineLimit(2)
            if showsTotal {
                Text("累计 \(habit.totalDays) 天")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(habit.usesImageBackground ? .white.opacity(0.82) : .secondary)
            }
        }
    }
}

private struct WidgetIcon: View {
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
            .background((isOnImage ? Color.black.opacity(0.26) : Color.white.opacity(0.28)), in: Circle())
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

private struct CompletionDot: View {
    let isCompleted: Bool
    var isOnImage = false

    var body: some View {
        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isCompleted ? (isOnImage ? .white : .green) : (isOnImage ? .white.opacity(0.86) : .secondary))
            .symbolRenderingMode(.hierarchical)
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
    let snapshot: WidgetHabitSnapshot

    var body: some View {
        switch snapshot.effectiveCardStyle {
        case "glass":
            Rectangle()
                .fill(.thinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), color(for: snapshot.colorName).opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case "minimal":
            Rectangle()
                .fill(widgetSecondarySystemBackgroundColor)
                .overlay(color(for: snapshot.colorName).opacity(0.16), alignment: .leading)
        case "image":
            if let image = widgetImage(for: snapshot) {
                GeometryReader { proxy in
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .saturation(0.86)
                        .overlay(.black.opacity(0.20))
                        .overlay(
                            LinearGradient(
                                colors: [.black.opacity(0.36), .black.opacity(0.14), .black.opacity(0.42)],
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
        LinearGradient(
            colors: [
                color(for: snapshot.colorName).opacity(0.20),
                color(for: snapshot.colorName).opacity(0.08),
                widgetSystemBackgroundColor.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
        .description("显示一个目标和连续打卡天数。")
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
        .description("极简显示多个目标的连续天数。")
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

private extension WidgetHabitSnapshot {
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

    var usesImageBackground: Bool {
        effectiveCardStyle == "image" && widgetImage(for: self) != nil
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

private extension String {
    var isEmojiIcon: Bool {
        count <= 4 && unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }
}

private let widgetJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

private let widgetJSONEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

private let widgetLogDateFormatStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

private func widgetLog(_ message: String) {
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
        .containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
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
