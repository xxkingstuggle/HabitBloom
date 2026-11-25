import Foundation
import WidgetKit

enum WidgetSnapshotWriter {
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
            completedTodayByHabitID: completedTodayByHabitID,
            updatedHabitID: habitID,
            actionTimestamp: Date()
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
        completedTodayByHabitID: [UUID: Bool],
        updatedHabitID: UUID? = nil,
        actionTimestamp: Date = Date()
    ) -> [WidgetHabitSnapshotInput] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: actionTimestamp)
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
                let latestTodayUpdatedAt = (habit.checkIns ?? [])
                    .filter { calendar.isDate($0.day, inSameDayAs: today) }
                    .map(\.createdAt)
                    .max() ?? habit.createdAt
                let effectiveUpdatedAt = habit.id == updatedHabitID
                    ? max(latestTodayUpdatedAt, actionTimestamp)
                    : latestTodayUpdatedAt
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
                    updatedAt: effectiveUpdatedAt
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
    /// 远程快照：图片卡片只带指纹文件名（服务端去重），不再每次全量上传图片字节。
    static func makeRemoteSnapshot(inputs: [WidgetHabitSnapshotInput], selectedHabitID: UUID?) -> WidgetRemoteSnapshot {
        let now = Date()
        return WidgetRemoteSnapshot(
            deviceKey: RemoteWidgetConfig.deviceKey,
            updatedAt: now,
            dayKey: WidgetDayKey.string(for: now),
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
                    imageFileName: remoteImageFileName(for: input),
                    imageData: nil,
                    updatedAt: input.updatedAt
                )
            }
        )
    }

    /// 远程图片上传：只上传指纹发生变化的图片，返回本次已确认在远端的图片文件集合。
    static func remoteImageFileName(for input: WidgetHabitSnapshotInput) -> String? {
        guard let imageData = input.imageData else { return nil }
        return "\(input.id.uuidString)-\(widgetImageFingerprint(imageData)).jpg"
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

    /// 先把变化的图片上传到 Worker，再把引用文件名的快照写过去。
    private static func putRemoteSnapshot(inputs: [WidgetHabitSnapshotInput], selectedHabitID: UUID?) async {
        guard RemoteWidgetConfig.isWritable else {
            log("remote PUT skipped: RemoteWidgetConfig is not configured")
            return
        }

        await uploadChangedImages(inputs: inputs)

        let snapshot = WidgetSnapshotFactory.makeRemoteSnapshot(inputs: inputs, selectedHabitID: selectedHabitID)
        let startedAt = Date()
        log("PUT /snapshot start updatedAt=\(snapshot.updatedAt.iso8601LogString)")

        do {
            var request = try request(path: "/v1/snapshot/\(RemoteWidgetConfig.deviceKey)", method: "PUT")
            request.httpBody = try widgetJSONEncoder.encode(snapshot)
            let (_, response) = try await URLSession.shared.data(for: request)
            try validate(response: response)
            log("PUT /snapshot ok elapsed=\(Date().timeIntervalSince(startedAt))s")
        } catch {
            log("PUT /snapshot failed: \(error.localizedDescription)")
        }
    }

    private static func postRemoteCheckIn(habitID: UUID, isCompletedToday: Bool, inputs: [WidgetHabitSnapshotInput]) async {
        guard RemoteWidgetConfig.isWritable else {
            log("remote POST skipped: RemoteWidgetConfig is not configured")
            return
        }

        await uploadChangedImages(inputs: inputs)

        let startedAt = Date()
        log("POST /checkin start habitID=\(habitID.uuidString) completed=\(isCompletedToday)")

        do {
            var request = try request(path: "/v1/checkin/\(RemoteWidgetConfig.deviceKey)", method: "POST")
            let remoteSnapshot = WidgetSnapshotFactory.makeRemoteSnapshot(inputs: inputs, selectedHabitID: habitID)
            let body = RemoteCheckInRequest(
                habitID: habitID,
                isCompletedToday: isCompletedToday,
                dayKey: remoteSnapshot.dayKey,
                snapshot: remoteSnapshot
            )
            request.httpBody = try widgetJSONEncoder.encode(body)
            let (_, response) = try await URLSession.shared.data(for: request)
            try validate(response: response)
            log("POST /checkin ok elapsed=\(Date().timeIntervalSince(startedAt))s")
        } catch {
            log("POST /checkin failed: \(error.localizedDescription)")
        }
    }

    /// 只上传指纹不在远端 manifest 里的图片，并把当前有效图片清单回写，让 Worker 清理孤儿图片键。
    private static func uploadChangedImages(inputs: [WidgetHabitSnapshotInput]) async {
        let withImages = inputs.filter { $0.imageData != nil }
        let activeFiles = Set(withImages.compactMap { WidgetSnapshotFactory.remoteImageFileName(for: $0) })

        var manifest = await fetchRemoteImageManifest()
        var syncedManifest = manifest.intersection(activeFiles)
        var didUploadAny = false

        for input in withImages {
            guard let imageData = input.imageData,
                  let fileName = WidgetSnapshotFactory.remoteImageFileName(for: input)
            else { continue }
            if manifest.contains(fileName) { continue }

            do {
                var imageRequest = try request(path: "/v1/image/\(RemoteWidgetConfig.deviceKey)/\(fileName)", method: "PUT")
                imageRequest.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
                imageRequest.httpBody = imageData
                let (_, response) = try await URLSession.shared.data(for: imageRequest)
                try validate(response: response)
                manifest.insert(fileName)
                syncedManifest.insert(fileName)
                didUploadAny = true
                log("PUT /image ok file=\(fileName)")
            } catch {
                log("PUT /image failed file=\(fileName): \(error.localizedDescription)")
            }
        }

        if didUploadAny || syncedManifest != manifest {
            await putRemoteImageManifest(syncedManifest)
        }
    }

    private static func fetchRemoteImageManifest() async -> Set<String> {
        do {
            let request = try request(path: "/v1/images/\(RemoteWidgetConfig.deviceKey)", method: "GET")
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response)
            if let manifest = try? widgetJSONDecoder.decode([String: [String]].self, from: data),
               let files = manifest["files"] {
                return Set(files)
            }
            return Set((try? widgetJSONDecoder.decode([String].self, from: data)) ?? [])
        } catch {
            return []
        }
    }

    private static func putRemoteImageManifest(_ manifest: Set<String>) async {
        do {
            var request = try request(path: "/v1/images/\(RemoteWidgetConfig.deviceKey)", method: "PUT")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try widgetJSONEncoder.encode(["files": manifest.sorted()])
            let (_, response) = try await URLSession.shared.data(for: request)
            try validate(response: response)
        } catch {
            log("PUT /images manifest failed: \(error.localizedDescription)")
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

        guard let data = try? widgetJSONEncoder.encode(snapshots),
              let defaults = UserDefaults(suiteName: WidgetSharedDefaults.appGroupIdentifier)
        else { return }
        defaults.set(data, forKey: WidgetSharedDefaults.snapshotsKey)
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
        let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSharedDefaults.appGroupIdentifier)
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
        let fileName = "\(id.uuidString)-\(widgetImageFingerprint(imageData)).jpg"
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

private let logDateFormatStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

private func log(_ message: String) {
    print("[HabitBloomRemote] \(Date().iso8601LogString) \(message)")
}

private extension Date {
    var iso8601LogString: String {
        formatted(logDateFormatStyle)
    }
}
