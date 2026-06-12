import AppIntents
import SwiftUI
import WidgetKit

private let suiteName = "group.com.zjx.HabitBloom"
private let snapshotsKey = "habitWidgetSnapshots"

struct WidgetHabitSnapshot: Identifiable, Codable {
    var id: UUID
    var name: String
    var icon: String
    var colorName: String
    var cardStyle: String?
    var streakDays: Int
    var totalDays: Int
    var completionRate: Double?
    var isCompletedToday: Bool
    var imageFileName: String?
    var imageData: Data?
    var updatedAt: Date?

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
        HabitTimelineEntry(date: Date(), habits: loadSnapshots(), selectedHabitID: configuration.habit?.uuid, selectedHabitName: configuration.habit?.name)
    }

    func timeline(for configuration: HabitSelectionIntent, in context: Context) async -> Timeline<HabitTimelineEntry> {
        let entry = HabitTimelineEntry(date: Date(), habits: loadSnapshots(), selectedHabitID: configuration.habit?.uuid, selectedHabitName: configuration.habit?.name)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
    }

    private func loadSnapshots() -> [WidgetHabitSnapshot] {
        guard
            let data = UserDefaults(suiteName: suiteName)?.data(forKey: snapshotsKey),
            let snapshots = try? JSONDecoder().decode([WidgetHabitSnapshot].self, from: data),
            !snapshots.isEmpty
        else {
            return [.placeholder]
        }

        return snapshots
    }
}

struct SimpleHabitProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitTimelineEntry {
        HabitTimelineEntry(date: Date(), habits: [.placeholder], selectedHabitID: nil, selectedHabitName: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitTimelineEntry) -> Void) {
        completion(HabitTimelineEntry(date: Date(), habits: loadSnapshots(), selectedHabitID: nil, selectedHabitName: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitTimelineEntry>) -> Void) {
        let entry = HabitTimelineEntry(date: Date(), habits: loadSnapshots(), selectedHabitID: nil, selectedHabitName: nil)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
    }

    private func loadSnapshots() -> [WidgetHabitSnapshot] {
        guard
            let data = UserDefaults(suiteName: suiteName)?.data(forKey: snapshotsKey),
            let snapshots = try? JSONDecoder().decode([WidgetHabitSnapshot].self, from: data),
            !snapshots.isEmpty
        else {
            return [.placeholder]
        }

        return snapshots
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
        loadWidgetEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HabitWidgetEntity] {
        loadWidgetEntities()
    }

    func defaultResult() async -> HabitWidgetEntity? {
        loadWidgetEntities().first
    }

    private func loadWidgetEntities() -> [HabitWidgetEntity] {
        guard
            let data = UserDefaults(suiteName: suiteName)?.data(forKey: snapshotsKey),
            let snapshots = try? JSONDecoder().decode([WidgetHabitSnapshot].self, from: data)
        else {
            return [HabitWidgetEntity(id: WidgetHabitSnapshot.placeholder.id.uuidString, name: WidgetHabitSnapshot.placeholder.name, detail: "连续 \(WidgetHabitSnapshot.placeholder.streakDays) 天")]
        }

        return snapshots.map {
            HabitWidgetEntity(id: $0.id.uuidString, name: $0.name, detail: "连续 \($0.streakDays) 天")
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
                .fill(Color(.secondarySystemBackground))
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
                Color(.systemBackground).opacity(0.92)
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
        name: "晨间阅读",
        icon: "book.closed.fill",
        colorName: "mint",
        cardStyle: "soft",
        streakDays: 7,
        totalDays: 21,
        completionRate: 0.72,
        isCompletedToday: true,
        imageFileName: nil,
        imageData: nil
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

private extension String {
    var isEmojiIcon: Bool {
        count <= 4 && unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
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
