import Foundation
import SwiftData

struct ManualSyncArchive: Codable {
    var version: Int
    var exportedAt: Date
    var habits: [ManualSyncHabit]
}

struct ManualSyncHabit: Codable {
    var id: UUID
    var name: String
    var icon: String
    var colorName: String
    var cardStyle: String
    var imageData: Data?
    var targetWeekdayMask: Int
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var reminderWeekdayMask: Int
    var sortOrder: Int
    var createdAt: Date
    var checkIns: [ManualSyncCheckIn]
}

struct ManualSyncCheckIn: Codable {
    var id: UUID
    var day: Date
    var isCompleted: Bool
    var note: String
    var createdAt: Date
}

enum ManualFolderSyncService {
    static let archiveFileName = "habit-bloom.json"

    static func export(habits: [HabitEntity], to folderURL: URL) throws {
        let archive = ManualSyncArchive(
            version: 1,
            exportedAt: Date(),
            habits: habits
                .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
                .map { habit in
                    ManualSyncHabit(
                        id: habit.id,
                        name: habit.name,
                        icon: habit.icon,
                        colorName: habit.colorName,
                        cardStyle: habit.cardStyle,
                        imageData: habit.imageData,
                        targetWeekdayMask: habit.targetWeekdayMask,
                        reminderEnabled: habit.reminderEnabled,
                        reminderHour: habit.reminderHour,
                        reminderMinute: habit.reminderMinute,
                        reminderWeekdayMask: habit.reminderWeekdayMask,
                        sortOrder: habit.sortOrder,
                        createdAt: habit.createdAt,
                        checkIns: (habit.checkIns ?? [])
                            .sorted { $0.day < $1.day }
                            .map {
                                ManualSyncCheckIn(
                                    id: $0.id,
                                    day: $0.day,
                                    isCompleted: $0.isCompleted,
                                    note: $0.note,
                                    createdAt: $0.createdAt
                                )
                            }
                    )
                }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)
        try data.write(to: folderURL.appendingPathComponent(archiveFileName), options: [.atomic])
    }

    static func `import`(from folderURL: URL, into context: ModelContext, existingHabits: [HabitEntity]) throws {
        let data = try Data(contentsOf: folderURL.appendingPathComponent(archiveFileName))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(ManualSyncArchive.self, from: data)

        var habitsByID = Dictionary(uniqueKeysWithValues: existingHabits.map { ($0.id, $0) })

        for source in archive.habits {
            let target = habitsByID[source.id] ?? HabitEntity(id: source.id, name: source.name)
            target.name = source.name
            target.icon = source.icon
            target.colorName = source.colorName
            target.cardStyle = source.cardStyle
            target.imageData = source.imageData
            target.targetWeekdayMask = source.targetWeekdayMask
            target.reminderEnabled = source.reminderEnabled
            target.reminderHour = source.reminderHour
            target.reminderMinute = source.reminderMinute
            target.reminderWeekdayMask = source.reminderWeekdayMask
            target.sortOrder = source.sortOrder
            target.createdAt = source.createdAt

            if habitsByID[source.id] == nil {
                context.insert(target)
                habitsByID[source.id] = target
            }

            var checkIns = target.checkIns ?? []
            var checkInsByID = Dictionary(uniqueKeysWithValues: checkIns.map { ($0.id, $0) })
            for sourceCheckIn in source.checkIns {
                let checkIn = checkInsByID[sourceCheckIn.id] ?? CheckInEntity(
                    id: sourceCheckIn.id,
                    day: sourceCheckIn.day,
                    habit: target
                )
                checkIn.day = sourceCheckIn.day
                checkIn.isCompleted = sourceCheckIn.isCompleted
                checkIn.note = sourceCheckIn.note
                checkIn.createdAt = sourceCheckIn.createdAt
                checkIn.habit = target

                if checkInsByID[sourceCheckIn.id] == nil {
                    checkIns.append(checkIn)
                    checkInsByID[sourceCheckIn.id] = checkIn
                }
            }
            target.checkIns = checkIns
        }

        try context.save()
    }
}

