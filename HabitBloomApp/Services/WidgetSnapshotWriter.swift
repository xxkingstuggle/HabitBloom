import Foundation
import WidgetKit

struct WidgetHabitSnapshot: Identifiable, Codable {
    var id: UUID
    var name: String
    var icon: String
    var colorName: String
    var cardStyle: String
    var streakDays: Int
    var totalDays: Int
    var completionRate: Double
    var isCompletedToday: Bool
    var imageFileName: String?
    var updatedAt: Date
}

enum WidgetSnapshotWriter {
    static let suiteName = "group.com.zjx.HabitBloom"
    static let snapshotsKey = "habitWidgetSnapshots"
    private static let imagesDirectoryName = "WidgetImages"

    static func write(habits: [HabitEntity]) {
        let imagesDirectory = widgetImagesDirectory()
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        var activeImageFileNames = Set<String>()

        let snapshots = habits
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
            .map { habit in
                let stats = HabitStatsService.stats(for: habit)
                let imageFileName = writeImageIfNeeded(for: habit, in: imagesDirectory)
                if let imageFileName {
                    activeImageFileNames.insert(imageFileName)
                }

                return WidgetHabitSnapshot(
                    id: habit.id,
                    name: habit.name,
                    icon: habit.icon,
                    colorName: habit.colorName,
                    cardStyle: habit.cardStyle,
                    streakDays: stats.currentStreak,
                    totalDays: stats.totalCompletedDays,
                    completionRate: stats.monthCompletionRate,
                    isCompletedToday: HabitStatsService.isCompletedToday(habit),
                    imageFileName: imageFileName,
                    updatedAt: Date()
                )
            }

        removeStaleImages(in: imagesDirectory, keeping: activeImageFileNames)

        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: snapshotsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func widgetImagesDirectory() -> URL {
        let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent(imagesDirectoryName, isDirectory: true)
    }

    private static func removeStaleImages(in directory: URL, keeping activeFileNames: Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in contents {
            if !activeFileNames.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func writeImageIfNeeded(for habit: HabitEntity, in directory: URL) -> String? {
        guard habit.cardStyle == HabitCardKind.image.rawValue, let imageData = habit.imageData else { return nil }
        let fileName = "\(habit.id.uuidString)-\(imageFingerprint(imageData)).jpg"
        let fileURL = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileName
        }
        do {
            try imageData.write(to: fileURL, options: [.atomic])
            return fileName
        } catch {
            return nil
        }
    }

    private static func imageFingerprint(_ data: Data) -> String {
        var hash: UInt64 = 5381
        for byte in data.prefix(4096) {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        hash = ((hash << 5) &+ hash) &+ UInt64(data.count)
        return String(hash, radix: 16)
    }
}
