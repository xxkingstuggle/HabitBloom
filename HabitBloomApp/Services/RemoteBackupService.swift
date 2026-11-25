import Foundation
import SwiftData

enum RemoteBackupService {
    private static let coordinator = RemoteBackupCoordinator()

    /// 本地 JSON 备份导出：与云端同构，便于用户完全掌控数据。
    @MainActor
    static func exportLocalArchive(habits: [HabitEntity]) throws -> Data {
        let archive = makeArchive(habits: habits)
        let encoder = WidgetJSONCodec.makeEncoder(prettyPrinted: true)
        return try encoder.encode(archive)
    }

    @MainActor
    static func decodeLocalArchive(from data: Data) throws -> RemoteBackupArchive {
        try WidgetJSONCodec.makeDecoder().decode(RemoteBackupArchive.self, from: data)
    }

    @MainActor
    static func makeImportPlan(
        archive: RemoteBackupArchive,
        existingHabits: [HabitEntity],
        calendar: Calendar = .current
    ) -> BackupImportPlan {
        let localArchive = makeArchive(habits: existingHabits)
        return BackupImportPlanner.makePlan(
            existingHabits: localArchive.habits,
            importedArchive: archive,
            calendar: calendar
        )
    }

    @MainActor
    static func importLocalArchive(
        data: Data,
        into context: ModelContext,
        existingHabits: [HabitEntity],
        strategy: BackupMergeStrategy = .overwriteWithImported
    ) throws -> [HabitEntity] {
        let archive = try decodeLocalArchive(from: data)
        return try restore(
            archive: archive,
            into: context,
            existingHabits: existingHabits,
            strategy: strategy
        )
    }

    @MainActor
    static func scheduleUpload(habits: [HabitEntity], delayMilliseconds: UInt64 = 1_200) {
        coordinator.scheduleUpload(habits: habits, delayMilliseconds: delayMilliseconds)
    }

    @MainActor
    static func uploadNow(habits: [HabitEntity]) async throws -> RemoteBackupArchive {
        let archive = makeArchive(habits: habits)
        return try await RemoteBackupClient.putBackup(archive)
    }

    static func download() async throws -> RemoteBackupArchive {
        try await RemoteBackupClient.getBackup()
    }

    static func downloadWidgetSnapshot() async throws -> WidgetRemoteSnapshot {
        try await RemoteBackupClient.getWidgetSnapshot()
    }

    @MainActor
    static func restore(
        archive: RemoteBackupArchive,
        into context: ModelContext,
        existingHabits: [HabitEntity],
        widgetSnapshot: WidgetRemoteSnapshot? = nil,
        strategy: BackupMergeStrategy = .overwriteWithImported,
        calendar: Calendar = .current
    ) throws -> [HabitEntity] {
        var habitsByID = Dictionary(uniqueKeysWithValues: existingHabits.map { ($0.id, $0) })
        let widgetHabitsByID = Dictionary(
            uniqueKeysWithValues: (widgetSnapshot?.habits ?? []).map { ($0.id, $0) }
        )

        for source in archive.habits {
            let isNewHabit = habitsByID[source.id] == nil
            let target = habitsByID[source.id] ?? HabitEntity(id: source.id, name: source.name)
            let widgetHabit = widgetHabitsByID[source.id]

            if isNewHabit || strategy == .overwriteWithImported {
                target.name = source.name
                target.icon = source.icon
                target.colorName = source.colorName ?? widgetHabit?.colorName ?? target.colorName
                target.cardStyle = source.cardStyle ?? widgetHabit?.cardStyle ?? target.cardStyle
                target.targetWeekdayMask = source.targetWeekdayMask == 0 ? WeekdayMask.all : source.targetWeekdayMask
                target.reminderEnabled = source.reminderEnabled
                target.reminderHour = source.reminderHour
                target.reminderMinute = source.reminderMinute
                target.reminderWeekdayMask = source.reminderWeekdayMask == 0 ? WeekdayMask.all : source.reminderWeekdayMask
                target.sortOrder = source.sortOrder
                target.createdAt = source.createdAt
            }

            if isNewHabit {
                context.insert(target)
                habitsByID[source.id] = target
            }

            // 先对当前目标已有打卡按 normalizedDay 去重，确保 (habitID, normalizedDay) 唯一。
            var existingByDay: [Date: CheckInEntity] = [:]
            for item in target.checkIns ?? [] {
                let normalizedDay = calendar.startOfDay(for: item.day)
                item.day = normalizedDay
                if let keeper = existingByDay[normalizedDay] {
                    if item.createdAt > keeper.createdAt {
                        if item.note.isEmpty, !keeper.note.isEmpty {
                            item.note = keeper.note
                        }
                        context.delete(keeper)
                        existingByDay[normalizedDay] = item
                    } else {
                        if keeper.note.isEmpty, !item.note.isEmpty {
                            keeper.note = item.note
                        }
                        context.delete(item)
                    }
                } else {
                    existingByDay[normalizedDay] = item
                }
            }

            let (dedupedImported, _) = BackupImportPlanner.deduplicateCheckIns(source.checkIns, calendar: calendar)
            for (normalizedDay, sourceCheckIn) in dedupedImported.sorted(by: { $0.key < $1.key }) {
                if let existing = existingByDay[normalizedDay] {
                    if strategy == .overwriteWithImported {
                        existing.isCompleted = sourceCheckIn.isCompleted
                        existing.note = sourceCheckIn.note
                        existing.createdAt = max(existing.createdAt, sourceCheckIn.createdAt)
                    }
                } else {
                    let inserted = CheckInEntity(
                        id: sourceCheckIn.id,
                        day: normalizedDay,
                        isCompleted: sourceCheckIn.isCompleted,
                        note: sourceCheckIn.note,
                        createdAt: sourceCheckIn.createdAt,
                        habit: target
                    )
                    existingByDay[normalizedDay] = inserted
                }
            }

            target.checkIns = existingByDay.values.sorted { $0.day < $1.day }
        }

        try context.save()
        return Array(habitsByID.values).sorted {
            $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder
        }
    }

    @MainActor
    fileprivate static func makeArchive(habits: [HabitEntity]) -> RemoteBackupArchive {
        RemoteBackupArchive(
            version: 1,
            deviceKey: RemoteWidgetConfig.deviceKey,
            exportedAt: Date(),
            habits: habits
                .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
                .map { habit in
                    RemoteBackupHabit(
                        id: habit.id,
                        name: habit.name,
                        icon: habit.icon,
                        colorName: habit.colorName,
                        cardStyle: habit.cardStyle,
                        targetWeekdayMask: habit.targetWeekdayMask,
                        reminderEnabled: habit.reminderEnabled,
                        reminderHour: habit.reminderHour,
                        reminderMinute: habit.reminderMinute,
                        reminderWeekdayMask: habit.reminderWeekdayMask,
                        sortOrder: habit.sortOrder,
                        createdAt: habit.createdAt,
                        checkIns: BackupImportPlanner.deduplicateCheckIns(
                            (habit.checkIns ?? []).map {
                                RemoteBackupCheckIn(
                                    id: $0.id,
                                    day: Calendar.current.startOfDay(for: $0.day),
                                    isCompleted: $0.isCompleted,
                                    note: $0.note,
                                    createdAt: $0.createdAt
                                )
                            }
                        ).deduped.values.sorted { $0.day < $1.day }
                    )
                }
        )
    }
}

@MainActor
private final class RemoteBackupCoordinator {
    private var pendingTask: Task<Void, Never>?

    func scheduleUpload(habits: [HabitEntity], delayMilliseconds: UInt64) {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            if delayMilliseconds > 0 {
                try? await Task.sleep(nanoseconds: delayMilliseconds * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            let archive = RemoteBackupService.makeArchive(habits: habits)
            do {
                _ = try await RemoteBackupClient.putBackup(archive)
                remoteBackupLog("auto backup uploaded habits=\(archive.habits.count)")
            } catch {
                remoteBackupLog("auto backup failed: \(error.localizedDescription)")
            }
        }
    }
}

private enum RemoteBackupClient {
    static func getWidgetSnapshot() async throws -> WidgetRemoteSnapshot {
        guard RemoteWidgetConfig.isReadable,
              let baseURL = URL(string: RemoteWidgetConfig.baseURLString)
        else { throw RemoteBackupError.notConfigured }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/v1/snapshot/\(RemoteWidgetConfig.deviceKey)"
        guard let url = components?.url else { throw RemoteBackupError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
        return try jsonDecoder.decode(WidgetRemoteSnapshot.self, from: data)
    }

    static func putBackup(_ archive: RemoteBackupArchive) async throws -> RemoteBackupArchive {
        var request = try request(path: "/v1/backup/\(RemoteWidgetConfig.deviceKey)", method: "PUT")
        request.httpBody = try jsonEncoder.encode(archive)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
        return try jsonDecoder.decode(RemoteBackupArchive.self, from: data)
    }

    static func getBackup() async throws -> RemoteBackupArchive {
        let request = try request(path: "/v1/backup/\(RemoteWidgetConfig.deviceKey)", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
        return try jsonDecoder.decode(RemoteBackupArchive.self, from: data)
    }

    /// 远端已上传的图片文件名清单（只读鉴权用 deviceKey，不写也能查）。
    static func getImageManifest() async throws -> [String] {
        let request = try request(path: "/v1/images/\(RemoteWidgetConfig.deviceKey)", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
        if let manifest = try? jsonDecoder.decode([String: [String]].self, from: data),
           let files = manifest["files"] {
            return files
        }
        return (try? jsonDecoder.decode([String].self, from: data)) ?? []
    }

    private static func request(path: String, method: String) throws -> URLRequest {
        guard RemoteWidgetConfig.isWritable,
              let baseURL = URL(string: RemoteWidgetConfig.baseURLString)
        else { throw RemoteBackupError.notConfigured }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        guard let url = components?.url else { throw RemoteBackupError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(RemoteWidgetConfig.writeToken)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw RemoteBackupError.invalidResponse }
        guard 200..<300 ~= http.statusCode else { throw RemoteBackupError.httpStatus(http.statusCode) }
    }
}

private enum RemoteBackupError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "云端备份未配置"
        case .invalidURL: "云端备份地址无效"
        case .invalidResponse: "云端备份响应无效"
        case .httpStatus(let status): "云端备份 HTTP \(status)"
        }
    }
}

private var jsonEncoder: JSONEncoder {
    WidgetJSONCodec.makeEncoder()
}

private var jsonDecoder: JSONDecoder {
    WidgetJSONCodec.makeDecoder()
}

private func remoteBackupLog(_ message: String) {
    print("[HabitBloomBackup] \(Date()) \(message)")
}
