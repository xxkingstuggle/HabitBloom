import Foundation
import SwiftData
import SwiftUI

@Model
final class HabitEntity {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "flame.fill"
    var colorName: String = "coral"
    var cardStyle: String = "soft"
    var imageData: Data?
    var targetWeekdayMask: Int = WeekdayMask.all
    var reminderEnabled: Bool = false
    var reminderHour: Int = 20
    var reminderMinute: Int = 0
    var reminderWeekdayMask: Int = WeekdayMask.all
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \CheckInEntity.habit) var checkIns: [CheckInEntity]?

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "flame.fill",
        colorName: String = "coral",
        cardStyle: String = "soft",
        imageData: Data? = nil,
        targetWeekdayMask: Int = WeekdayMask.all,
        reminderEnabled: Bool = false,
        reminderHour: Int = 20,
        reminderMinute: Int = 0,
        reminderWeekdayMask: Int = WeekdayMask.all,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        checkIns: [CheckInEntity]? = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorName = colorName
        self.cardStyle = cardStyle
        self.imageData = imageData
        self.targetWeekdayMask = targetWeekdayMask
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.reminderWeekdayMask = reminderWeekdayMask
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.checkIns = checkIns
    }
}

@Model
final class CheckInEntity {
    var id: UUID = UUID()
    var day: Date = Date()
    var isCompleted: Bool = true
    var note: String = ""
    var createdAt: Date = Date()
    var habit: HabitEntity?

    init(
        id: UUID = UUID(),
        day: Date,
        isCompleted: Bool = true,
        note: String = "",
        createdAt: Date = Date(),
        habit: HabitEntity? = nil
    ) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: day)
        self.isCompleted = isCompleted
        self.note = note
        self.createdAt = createdAt
        self.habit = habit
    }
}

enum WeekdayMask {
    static let all = (1 << 7) - 1

    static func contains(_ weekday: Int, in mask: Int) -> Bool {
        mask & (1 << max(0, weekday - 1)) != 0
    }

    static func weekdays(from mask: Int) -> [Int] {
        (1...7).filter { contains($0, in: mask) }
    }

    static func set(_ weekday: Int, enabled: Bool, in mask: Int) -> Int {
        let bit = 1 << max(0, weekday - 1)
        return enabled ? mask | bit : mask & ~bit
    }
}

enum HabitPalette: String, CaseIterable, Identifiable {
    case coral
    case mint
    case indigo
    case amber
    case teal
    case rose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coral: "珊瑚粉"
        case .mint: "薄荷绿"
        case .indigo: "靛蓝"
        case .amber: "琥珀橙"
        case .teal: "青绿色"
        case .rose: "玫瑰粉"
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var colors: [Color] {
        switch self {
        case .coral: [.red.opacity(0.86), .pink.opacity(0.72)]
        case .mint: [.green.opacity(0.72), .cyan.opacity(0.58)]
        case .indigo: [.indigo.opacity(0.84), .blue.opacity(0.58)]
        case .amber: [.yellow.opacity(0.84), .orange.opacity(0.74)]
        case .teal: [.teal.opacity(0.8), .green.opacity(0.56)]
        case .rose: [.pink.opacity(0.82), .purple.opacity(0.58)]
        }
    }

    var accent: Color { colors.first ?? .accentColor }
}

enum HabitCardKind: String, CaseIterable, Identifiable {
    case soft
    case glass
    case minimal
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft: "柔和"
        case .glass: "玻璃"
        case .minimal: "极简"
        case .image: "图片"
        }
    }
}
