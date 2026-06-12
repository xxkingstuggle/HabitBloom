import Foundation

public enum HabitIcon: String, Codable, CaseIterable, Sendable {
    case flame
    case book
    case leaf
    case moon
    case bolt
    case heart
    case drop
    case star

    public var symbolName: String {
        switch self {
        case .flame: "flame.fill"
        case .book: "book.closed.fill"
        case .leaf: "leaf.fill"
        case .moon: "moon.fill"
        case .bolt: "bolt.fill"
        case .heart: "heart.fill"
        case .drop: "drop.fill"
        case .star: "star.fill"
        }
    }
}

public enum HabitColor: String, Codable, CaseIterable, Sendable {
    case coral
    case mint
    case indigo
    case amber
    case teal
    case rose
}

public enum HabitCardStyle: String, Codable, CaseIterable, Sendable {
    case soft
    case glass
    case minimal
    case image
}

public struct ReminderRule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var hour: Int
    public var minute: Int
    public var activeWeekdays: Set<Int>

    public init(
        isEnabled: Bool = false,
        hour: Int = 20,
        minute: Int = 0,
        activeWeekdays: Set<Int> = Set(1...7)
    ) {
        self.isEnabled = isEnabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.activeWeekdays = activeWeekdays.isEmpty ? Set(1...7) : activeWeekdays
    }
}

public struct Habit: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var icon: HabitIcon
    public var color: HabitColor
    public var cardStyle: HabitCardStyle
    public var customImageBookmark: String?
    public var targetWeekdays: Set<Int>
    public var reminder: ReminderRule
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        icon: HabitIcon = .flame,
        color: HabitColor = .coral,
        cardStyle: HabitCardStyle = .soft,
        customImageBookmark: String? = nil,
        targetWeekdays: Set<Int> = Set(1...7),
        reminder: ReminderRule = ReminderRule(),
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.cardStyle = cardStyle
        self.customImageBookmark = customImageBookmark
        self.targetWeekdays = targetWeekdays.isEmpty ? Set(1...7) : targetWeekdays
        self.reminder = reminder
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

public struct CheckIn: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var habitID: UUID
    public var day: Date
    public var isCompleted: Bool
    public var note: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        habitID: UUID,
        day: Date,
        isCompleted: Bool = true,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.habitID = habitID
        self.day = day
        self.isCompleted = isCompleted
        self.note = note
        self.createdAt = createdAt
    }
}

public struct HabitStats: Codable, Equatable, Sendable {
    public var currentStreak: Int
    public var totalCompletedDays: Int
    public var monthCompletionRate: Double
    public var monthHeatmap: [Date: Bool]

    public init(
        currentStreak: Int,
        totalCompletedDays: Int,
        monthCompletionRate: Double,
        monthHeatmap: [Date: Bool]
    ) {
        self.currentStreak = currentStreak
        self.totalCompletedDays = totalCompletedDays
        self.monthCompletionRate = monthCompletionRate
        self.monthHeatmap = monthHeatmap
    }
}

public struct WidgetHabitSummary: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var iconSymbolName: String
    public var colorName: HabitColor
    public var streakDays: Int
    public var isCompletedToday: Bool
    public var customImageBookmark: String?

    public init(
        id: UUID,
        name: String,
        iconSymbolName: String,
        colorName: HabitColor,
        streakDays: Int,
        isCompletedToday: Bool,
        customImageBookmark: String?
    ) {
        self.id = id
        self.name = name
        self.iconSymbolName = iconSymbolName
        self.colorName = colorName
        self.streakDays = streakDays
        self.isCompletedToday = isCompletedToday
        self.customImageBookmark = customImageBookmark
    }
}
