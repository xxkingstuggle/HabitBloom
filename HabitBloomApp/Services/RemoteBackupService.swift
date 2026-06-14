import Foundation
import SwiftData

struct RemoteBackupArchive: Codable, Sendable {
    var version: Int
    var deviceKey: String
    var exportedAt: Date
    var habits: [RemoteBackupHabit]
}

struct RemoteBackupHabit: Codable, Sendable {
    var id: UUID
    var name: String
    var icon: String
    var targetWeekdayMask: Int
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var reminderWeekdayMask: Int
    var sortOrder: Int
    var createdAt: Date
    var checkIns: [RemoteBackupCheckIn]
}

struct RemoteBackupCheckIn: Codable, Sendable {
    var id: UUID
    var day: Date
    var isCompleted: Bool
    var note: String
    var createdAt: Date
}

enum RemoteBackupService {
    private static let coordinator = RemoteBackupCoordinator()

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

    @MainActor
    static func restore(
        archive: RemoteBackupArchive,
        into context: ModelContext,
        existingHabits: [HabitEntity]
    ) throws -> [HabitEntity] {
        var habitsByID = Dictionary(uniqueKeysWithValues: existingHabits.map { ($0.id, $0) })

        for source in archive.habits {
            let target = habitsByID[source.id] ?? HabitEntity(id: source.id, name: source.name)
            target.name = source.name
            target.icon = source.icon
            target.targetWeekdayMask = source.targetWeekdayMask == 0 ? WeekdayMask.all : source.targetWeekdayMask
            target.reminderEnabled = source.reminderEnabled
            target.reminderHour = source.reminderHour
            target.reminderMinute = source.reminderMinute
            target.reminderWeekdayMask = source.reminderWeekdayMask == 0 ? WeekdayMask.all : source.reminderWeekdayMask
            target.sortOrder = source.sortOrder
            target.createdAt = source.createdAt

            if habitsByID[source.id] == nil {
                context.insert(target)
                habitsByID[source.id] = target
            }

            var checkIns = target.checkIns ?? []
            var checkInsByID = Dictionary(uniqueKeysWithValues: checkIns.map { ($0.id, $0) })
            for sourceCheckIn in source.checkIns {
                let normalizedDay = Calendar.current.startOfDay(for: sourceCheckIn.day)
                let checkIn = checkInsByID[sourceCheckIn.id] ?? CheckInEntity(
                    id: sourceCheckIn.id,
                    day: normalizedDay,
                    habit: target
                )
                checkIn.day = normalizedDay
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
                                RemoteBackupCheckIn(
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

    private static func request(path: String, method: String) throws -> URLRequest {
        guard RemoteWidgetConfig.isConfigured,
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

private let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

private let jsonDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

private func remoteBackupLog(_ message: String) {
    print("[HabitBloomBackup] \(Date()) \(message)")
}
