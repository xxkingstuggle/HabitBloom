import Foundation
import WidgetKit

struct WidgetHabitSnapshot: Identifiable, Codable, Sendable {
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
    var imageData: Data?
    var updatedAt: Date
}

struct WidgetRemoteSnapshot: Codable, Sendable {
    var deviceKey: String
    var updatedAt: Date
    var selectedHabitID: UUID?
    var habits: [WidgetHabitSnapshot]
}

enum RemoteWidgetConfig {
    static let baseURLString = infoValue(for: "HBRemoteBaseURL")
    static let deviceKey = infoValue(for: "HBRemoteDeviceKey")
    static let writeToken = infoValue(for: "HBRemoteWriteToken")

    static var isConfigured: Bool {
        baseURLString.hasPrefix("https://")
            && !baseURLString.contains("$(")
            && !deviceKey.isEmpty
            && !deviceKey.contains("$(")
            && !writeToken.isEmpty
            && !writeToken.contains("$(")
    }

    private static func infoValue(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WidgetSnapshotWriter {
    static let suiteName = "group.com.zjx.HabitBloom"
    static let snapshotsKey = "habitWidgetSnapshots"
    fileprivate static let imagesDirectoryName = "WidgetImages"
    fileprivate static let widgetKinds = ["SingleHabitWidget", "MultiHabitWidget", "SummaryHabitWidget"]
    private static let coordinator = WidgetSnapshotWriteCoordinator()

    @MainActor
    static func scheduleWrite(
        habits: [HabitEntity],
        statsByHabitID: [UUID: HabitStatsViewModel] = [:],
        completedTodayByHabitID: [UUID: Bool] = [:],
        selectedHabitID: UUID? = nil,
        delayMilliseconds: UInt64 = 80,
        backupDelayMilliseconds: UInt64? = nil
    ) {
        let inputs = snapshotInputs(
            habits: habits,
            statsByHabitID: statsByHabitID,
            completedTodayByHabitID: completedTodayByHabitID
        )
        if let backupDelayMilliseconds {
            RemoteBackupService.scheduleUpload(habits: habits, delayMilliseconds: backupDelayMilliseconds)
        }

        Task {
            await coordinator.scheduleFullSnapshot(
                inputs,
                selectedHabitID: selectedHabitID,
                delayMilliseconds: delayMilliseconds
            )
        }
    }

    @MainActor
    static func scheduleCheckIn(
        habitID: UUID,
        isCompletedToday: Bool,
        habits: [HabitEntity],
        statsByHabitID: [UUID: HabitStatsViewModel] = [:],
        completedTodayByHabitID: [UUID: Bool] = [:]
    ) {
        let inputs = snapshotInputs(
            habits: habits,
            statsByHabitID: statsByHabitID,
            completedTodayByHabitID: completedTodayByHabitID
        )
        RemoteBackupService.scheduleUpload(habits: habits, delayMilliseconds: 5_000)

        Task {
            await coordinator.writeCheckIn(
                habitID: habitID,
                isCompletedToday: isCompletedToday,
                inputs: inputs
            )
        }
    }

    @MainActor
    private static func snapshotInputs(
        habits: [HabitEntity],
        statsByHabitID: [UUID: HabitStatsViewModel],
        completedTodayByHabitID: [UUID: Bool]
    ) -> [WidgetHabitSnapshotInput] {
        let sortedHabits = habits.sorted {
            $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder
        }
        let derivedState = statsByHabitID.isEmpty || completedTodayByHabitID.isEmpty
            ? HabitStatsService.derivedState(for: sortedHabits)
            : nil

        return sortedHabits
            .map { habit in
                let stats = statsByHabitID[habit.id]
                    ?? derivedState?.statsByHabitID[habit.id]
                    ?? HabitStatsService.stats(for: habit)
                return WidgetHabitSnapshotInput(
                    id: habit.id,
                    name: habit.name,
                    icon: habit.icon,
                    colorName: habit.colorName,
                    cardStyle: habit.cardStyle,
                    streakDays: stats.currentStreak,
                    totalDays: stats.totalCompletedDays,
                    completionRate: stats.monthCompletionRate,
                    isCompletedToday: completedTodayByHabitID[habit.id]
                        ?? derivedState?.completedTodayByHabitID[habit.id]
                        ?? HabitStatsService.isCompletedToday(habit),
                    imageData: habit.cardStyle == HabitCardKind.image.rawValue ? habit.imageData : nil,
                    updatedAt: Date()
                )
            }
    }
}

private struct WidgetHabitSnapshotInput: Sendable {
    var id: UUID
    var name: String
    var icon: String
    var colorName: String
    var cardStyle: String
    var streakDays: Int
    var totalDays: Int
    var completionRate: Double
    var isCompletedToday: Bool
    var imageData: Data?
    var updatedAt: Date
}

private enum WidgetSnapshotFactory {
    static func makeRemoteSnapshot(inputs: [WidgetHabitSnapshotInput], selectedHabitID: UUID?) -> WidgetRemoteSnapshot {
        WidgetRemoteSnapshot(
            deviceKey: RemoteWidgetConfig.deviceKey,
            updatedAt: Date(),
            selectedHabitID: selectedHabitID,
            habits: inputs.map { input in
                WidgetHabitSnapshot(
                    id: input.id,
                    name: input.name,
                    icon: input.icon,
                    colorName: input.colorName,
                    cardStyle: input.cardStyle,
                    streakDays: input.streakDays,
                    totalDays: input.totalDays,
                    completionRate: input.completionRate,
                    isCompletedToday: input.isCompletedToday,
                    imageFileName: nil,
                    imageData: input.imageData,
                    updatedAt: input.updatedAt
                )
            }
        )
    }

    static func makeLocalSnapshot(input: WidgetHabitSnapshotInput, imageFileName: String?) -> WidgetHabitSnapshot {
        WidgetHabitSnapshot(
            id: input.id,
            name: input.name,
            icon: input.icon,
            colorName: input.colorName,
            cardStyle: input.cardStyle,
            streakDays: input.streakDays,
            totalDays: input.totalDays,
            completionRate: input.completionRate,
            isCompletedToday: input.isCompletedToday,
            imageFileName: imageFileName,
            imageData: nil,
            updatedAt: input.updatedAt
        )
    }
}

private actor WidgetSnapshotWriteCoordinator {
    private var pendingTask: Task<Void, Never>?

    func scheduleFullSnapshot(_ inputs: [WidgetHabitSnapshotInput], selectedHabitID: UUID?, delayMilliseconds: UInt64) {
        pendingTask?.cancel()
        pendingTask = Task.detached(priority: .utility) {
            if delayMilliseconds > 0 {
                try? await Task.sleep(nanoseconds: delayMilliseconds * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            await Self.writeFullSnapshot(inputs: inputs, selectedHabitID: selectedHabitID)
        }
    }

    func writeCheckIn(habitID: UUID, isCompletedToday: Bool, inputs: [WidgetHabitSnapshotInput]) async {
        await Self.writeLocalFallback(inputs: inputs)
        await Self.postRemoteCheckIn(habitID: habitID, isCompletedToday: isCompletedToday, inputs: inputs)
        await Self.reloadWidgets()
    }

    private static func writeFullSnapshot(inputs: [WidgetHabitSnapshotInput], selectedHabitID: UUID?) async {
        await writeLocalFallback(inputs: inputs)
        await putRemoteSnapshot(inputs: inputs, selectedHabitID: selectedHabitID)
        await reloadWidgets()
    }

    private static func putRemoteSnapshot(inputs: [WidgetHabitSnapshotInput], selectedHabitID: UUID?) async {
        guard RemoteWidgetConfig.isConfigured else {
            log("remote PUT skipped: RemoteWidgetConfig is not configured")
            return
        }

        let snapshot = WidgetSnapshotFactory.makeRemoteSnapshot(inputs: inputs, selectedHabitID: selectedHabitID)
        let startedAt = Date()
        log("PUT /snapshot start updatedAt=\(snapshot.updatedAt.iso8601LogString)")

        do {
            var request = try request(path: "/v1/snapshot/\(RemoteWidgetConfig.deviceKey)", method: "PUT")
            request.httpBody = try jsonEncoder.encode(snapshot)
            let (_, response) = try await URLSession.shared.data(for: request)
            try validate(response: response)
            log("PUT /snapshot ok elapsed=\(Date().timeIntervalSince(startedAt))s")
        } catch {
            log("PUT /snapshot failed: \(error.localizedDescription)")
        }
    }

    private static func postRemoteCheckIn(habitID: UUID, isCompletedToday: Bool, inputs: [WidgetHabitSnapshotInput]) async {
        guard RemoteWidgetConfig.isConfigured else {
            log("remote POST skipped: RemoteWidgetConfig is not configured")
            return
        }

        let startedAt = Date()
        log("POST /checkin start habitID=\(habitID.uuidString) completed=\(isCompletedToday)")

        do {
            var request = try request(path: "/v1/checkin/\(RemoteWidgetConfig.deviceKey)", method: "POST")
            let body = RemoteCheckInRequest(
                habitID: habitID,
                isCompletedToday: isCompletedToday,
                snapshot: WidgetSnapshotFactory.makeRemoteSnapshot(inputs: inputs, selectedHabitID: habitID)
            )
            request.httpBody = try jsonEncoder.encode(body)
            let (_, response) = try await URLSession.shared.data(for: request)
            try validate(response: response)
            log("POST /checkin ok elapsed=\(Date().timeIntervalSince(startedAt))s")
        } catch {
            log("POST /checkin failed: \(error.localizedDescription)")
        }
    }

    private static func request(path: String, method: String) throws -> URLRequest {
        guard let baseURL = URL(string: RemoteWidgetConfig.baseURLString) else {
            throw RemoteWidgetError.invalidBaseURL
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        guard let url = components?.url else {
            throw RemoteWidgetError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(RemoteWidgetConfig.writeToken)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw RemoteWidgetError.invalidResponse }
        guard 200..<300 ~= http.statusCode else { throw RemoteWidgetError.httpStatus(http.statusCode) }
    }

    private static func writeLocalFallback(inputs: [WidgetHabitSnapshotInput]) async {
        let imagesDirectory = widgetImagesDirectory()
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        var activeImageFileNames = Set<String>()

        let snapshots = inputs.map { input in
            let imageFileName = writeImageIfNeeded(id: input.id, imageData: input.imageData, in: imagesDirectory)
            if let imageFileName {
                activeImageFileNames.insert(imageFileName)
            }

            return WidgetSnapshotFactory.makeLocalSnapshot(input: input, imageFileName: imageFileName)
        }

        removeStaleImages(in: imagesDirectory, keeping: activeImageFileNames)

        guard let data = try? jsonEncoder.encode(snapshots),
              let defaults = UserDefaults(suiteName: WidgetSnapshotWriter.suiteName)
        else { return }
        defaults.set(data, forKey: WidgetSnapshotWriter.snapshotsKey)
        defaults.synchronize()
        log("local App Group fallback wrote habits=\(snapshots.count)")
    }

    @MainActor
    private static func reloadWidgets() {
        for kind in WidgetSnapshotWriter.widgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        log("WidgetCenter.reloadTimelines called kinds=\(WidgetSnapshotWriter.widgetKinds.joined(separator: ","))")
    }

    private static func widgetImagesDirectory() -> URL {
        let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotWriter.suiteName)
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent(WidgetSnapshotWriter.imagesDirectoryName, isDirectory: true)
    }

    private static func removeStaleImages(in directory: URL, keeping activeFileNames: Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in contents where !activeFileNames.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func writeImageIfNeeded(id: UUID, imageData: Data?, in directory: URL) -> String? {
        guard let imageData else { return nil }
        let fileName = "\(id.uuidString)-\(imageFingerprint(imageData)).jpg"
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

private struct RemoteCheckInRequest: Codable {
    var habitID: UUID
    var isCompletedToday: Bool
    var snapshot: WidgetRemoteSnapshot
}

private enum RemoteWidgetError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "Remote widget base URL is invalid"
        case .invalidResponse: "Remote widget response is invalid"
        case .httpStatus(let status): "Remote widget HTTP status \(status)"
        }
    }
}

private let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

private let logDateFormatStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

private func log(_ message: String) {
    print("[HabitBloomRemote] \(Date().iso8601LogString) \(message)")
}

private extension Date {
    var iso8601LogString: String {
        formatted(logDateFormatStyle)
    }
}
