import Foundation
import CryptoKit

/// 小组件快照的共享编解码层：主 App 写入，Widget 扩展读取。
/// 两份 target 都直接编译这个文件，避免两边结构漂移。
public struct WidgetHabitSnapshot: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var colorName: String
    public var cardStyle: String
    public var streakDays: Int
    public var totalDays: Int
    public var completionRate: Double
    public var isCompletedToday: Bool
    public var imageFileName: String?
    public var imageData: Data?
    public var updatedAt: Date

    public init(
        id: UUID,
        name: String,
        icon: String,
        colorName: String,
        cardStyle: String,
        streakDays: Int,
        totalDays: Int,
        completionRate: Double,
        isCompletedToday: Bool,
        imageFileName: String? = nil,
        imageData: Data? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorName = colorName
        self.cardStyle = cardStyle
        self.streakDays = streakDays
        self.totalDays = totalDays
        self.completionRate = completionRate
        self.isCompletedToday = isCompletedToday
        self.imageFileName = imageFileName
        self.imageData = imageData
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, colorName, cardStyle, streakDays, totalDays
        case completionRate, isCompletedToday, imageFileName, imageData, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "checkmark.circle.fill"
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName) ?? "mint"
        cardStyle = try container.decodeIfPresent(String.self, forKey: .cardStyle) ?? "soft"
        streakDays = try container.decodeIfPresent(Int.self, forKey: .streakDays) ?? 0
        totalDays = try container.decodeIfPresent(Int.self, forKey: .totalDays) ?? 0
        completionRate = try container.decodeIfPresent(Double.self, forKey: .completionRate) ?? 0
        isCompletedToday = try container.decodeIfPresent(Bool.self, forKey: .isCompletedToday) ?? false
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

public struct WidgetRemoteSnapshot: Codable, Sendable {
    public var deviceKey: String
    public var updatedAt: Date
    public var dayKey: String?
    public var selectedHabitID: UUID?
    public var habits: [WidgetHabitSnapshot]

    public init(
        deviceKey: String,
        updatedAt: Date,
        dayKey: String? = nil,
        selectedHabitID: UUID?,
        habits: [WidgetHabitSnapshot]
    ) {
        self.deviceKey = deviceKey
        self.updatedAt = updatedAt
        self.dayKey = dayKey
        self.selectedHabitID = selectedHabitID
        self.habits = habits
    }

    private enum CodingKeys: String, CodingKey {
        case deviceKey, updatedAt, dayKey, selectedHabitID, habits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceKey = try container.decodeIfPresent(String.self, forKey: .deviceKey) ?? ""
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        dayKey = try container.decodeIfPresent(String.self, forKey: .dayKey)
        selectedHabitID = try container.decodeIfPresent(UUID.self, forKey: .selectedHabitID)
        habits = try container.decodeIfPresent([WidgetHabitSnapshot].self, forKey: .habits) ?? []
    }
}

/// 小组件打卡请求：本地 App Group 队列和远程 POST 共用。
public struct PendingWidgetCheckIn: Codable, Sendable {
    public var habitID: UUID
    public var isCompletedToday: Bool
    public var day: Date
    public var updatedAt: Date

    public init(habitID: UUID, isCompletedToday: Bool, day: Date, updatedAt: Date = Date()) {
        self.habitID = habitID
        self.isCompletedToday = isCompletedToday
        self.day = day
        self.updatedAt = updatedAt
    }
}

public struct RemoteCheckInRequest: Codable, Sendable {
    public var habitID: UUID
    public var isCompletedToday: Bool
    public var dayKey: String?
    public var snapshot: WidgetRemoteSnapshot?

    public init(
        habitID: UUID,
        isCompletedToday: Bool,
        dayKey: String? = nil,
        snapshot: WidgetRemoteSnapshot?
    ) {
        self.habitID = habitID
        self.isCompletedToday = isCompletedToday
        self.dayKey = dayKey
        self.snapshot = snapshot
    }
}

public enum RemoteWidgetConfig {
    public static let baseURLString = infoValue(for: "HBRemoteBaseURL")
    public static let deviceKey = infoValue(for: "HBRemoteDeviceKey")
    public static let writeToken = infoValue(for: "HBRemoteWriteToken")

    /// 小组件只读快照：不需要 write token。
    public static var isReadable: Bool {
        baseURLString.hasPrefix("https://")
            && !baseURLString.contains("$(")
            && !deviceKey.isEmpty
            && !deviceKey.contains("$(")
    }

    /// 主 App 写入/备份：需要完整配置。
    public static var isWritable: Bool {
        isReadable
            && !writeToken.isEmpty
            && !writeToken.contains("$(")
    }

    private static func infoValue(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum WidgetSharedDefaults {
    public static var appGroupIdentifier: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "HBAppGroupIdentifier") as? String ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("$(") {
            return "group.com.example.HabitBloom"
        }
        return trimmed
    }

    public static let snapshotsKey = "habitWidgetSnapshots"
    public static let remoteSnapshotCacheKey = "remoteWidgetSnapshot"
    public static let pendingCheckInsKey = "pendingWidgetCheckIns"

    public static var suiteDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}

public enum WidgetDayKey {
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

public enum WidgetJSONCodec {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let raw = try? container.decode(String.self) {
                if let parsed = parseISO8601(raw) {
                    return parsed
                }
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date string: \(raw)"
                )
            }
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO-8601 date string"
            )
        }
        return decoder
    }

    public static func makeEncoder(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatISO8601(date))
        }
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return encoder
    }

    public static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    public static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public var widgetJSONDecoder: JSONDecoder {
    WidgetJSONCodec.makeDecoder()
}

public var widgetJSONEncoder: JSONEncoder {
    WidgetJSONCodec.makeEncoder()
}

/// 跨午夜翻篇：把早于今日的快照状态归零，避免次日小组件和合并逻辑误把昨日打卡当成今日已完成。
public enum WidgetSnapshotRollover {
    public static func isSameDay(
        snapshot: WidgetRemoteSnapshot,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let todayKey = WidgetDayKey.string(for: referenceDate, calendar: calendar)
        if let dayKey = snapshot.dayKey, !dayKey.isEmpty {
            return dayKey == todayKey
        }
        return calendar.isDate(snapshot.updatedAt, inSameDayAs: referenceDate)
    }

    public static func rolledOver(
        _ snapshot: WidgetRemoteSnapshot,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> WidgetRemoteSnapshot {
        let todayKey = WidgetDayKey.string(for: referenceDate, calendar: calendar)
        let snapshotMatchesToday = isSameDay(snapshot: snapshot, referenceDate: referenceDate, calendar: calendar)
        var copy = snapshot
        copy.dayKey = todayKey
        copy.habits = snapshot.habits.map { habit in
            var updatedHabit = habit
            let habitMatchesToday: Bool
            if let dayKey = snapshot.dayKey, !dayKey.isEmpty {
                habitMatchesToday = (dayKey == todayKey)
            } else {
                habitMatchesToday = snapshotMatchesToday && calendar.isDate(habit.updatedAt, inSameDayAs: referenceDate)
            }
            if !habitMatchesToday {
                updatedHabit.isCompletedToday = false
            }
            return updatedHabit
        }
        return copy
    }

    /// 把今日尚未被主 App 消费的本地待合并打卡叠加到快照上，
    /// 确保离线或远程写入失败时小组件仍立即显示用户刚点的结果。
    public static func overlayPendingCheckIns(
        _ snapshot: WidgetRemoteSnapshot,
        pending: [PendingWidgetCheckIn],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> WidgetRemoteSnapshot {
        var copy = rolledOver(snapshot, referenceDate: referenceDate, calendar: calendar)
        let today = calendar.startOfDay(for: referenceDate)

        var latestPendingByHabitID: [UUID: PendingWidgetCheckIn] = [:]
        for item in pending {
            guard calendar.startOfDay(for: item.day) == today else { continue }
            if let existing = latestPendingByHabitID[item.habitID], existing.updatedAt > item.updatedAt {
                continue
            }
            latestPendingByHabitID[item.habitID] = item
        }

        guard !latestPendingByHabitID.isEmpty else { return copy }

        for index in copy.habits.indices {
            let habitID = copy.habits[index].id
            guard let queued = latestPendingByHabitID[habitID] else { continue }
            let habitIsFromToday = calendar.isDate(copy.habits[index].updatedAt, inSameDayAs: referenceDate)
            if !habitIsFromToday || queued.updatedAt >= copy.habits[index].updatedAt {
                copy.habits[index].isCompletedToday = queued.isCompletedToday
                copy.habits[index].updatedAt = queued.updatedAt
                if queued.updatedAt > copy.updatedAt {
                    copy.updatedAt = queued.updatedAt
                }
            }
        }
        return copy
    }
}

public enum WidgetCheckInSource: String, Sendable, Equatable {
    case localQueue
    case remoteSnapshot
}

public struct LocalTodayCheckInState: Sendable, Equatable {
    public var isCompleted: Bool
    public var updatedAt: Date?

    public init(isCompleted: Bool, updatedAt: Date?) {
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
    }
}

public struct WidgetCheckInResolution: Sendable, Equatable {
    public var habitID: UUID
    public var day: Date
    public var isCompleted: Bool
    public var updatedAt: Date
    public var source: WidgetCheckInSource

    public init(
        habitID: UUID,
        day: Date,
        isCompleted: Bool,
        updatedAt: Date,
        source: WidgetCheckInSource
    ) {
        self.habitID = habitID
        self.day = day
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
        self.source = source
    }
}

/// 双通道（本地 App Group 队列 + 远端快照）合并仲裁器：
/// 1. 同一习惯同一天按最新 `updatedAt` 决胜；
/// 2. 拦截非今日的旧远端快照，杜绝跨午夜假打卡；
/// 3. 避免旧远端快照覆盖刚刚落库的本地队列或本地最新打卡状态。
public enum WidgetCheckInReconciler {
    private struct HabitDayKey: Hashable {
        let habitID: UUID
        let day: Date
    }

    public static func reconcile(
        localPending: [PendingWidgetCheckIn],
        remoteSnapshot: WidgetRemoteSnapshot?,
        existingTodayStateByHabitID: [UUID: LocalTodayCheckInState],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [WidgetCheckInResolution] {
        let today = calendar.startOfDay(for: referenceDate)
        var resolvedByKey: [HabitDayKey: WidgetCheckInResolution] = [:]

        for item in localPending.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            let normalizedDay = calendar.startOfDay(for: item.day)
            let key = HabitDayKey(habitID: item.habitID, day: normalizedDay)
            if normalizedDay == today,
               let localState = existingTodayStateByHabitID[item.habitID],
               let localUpdatedAt = localState.updatedAt,
               item.updatedAt < localUpdatedAt {
                continue
            }
            if let existing = resolvedByKey[key], existing.updatedAt > item.updatedAt {
                continue
            }
            resolvedByKey[key] = WidgetCheckInResolution(
                habitID: item.habitID,
                day: normalizedDay,
                isCompleted: item.isCompletedToday,
                updatedAt: item.updatedAt,
                source: .localQueue
            )
        }

        if let remoteSnapshot,
           WidgetSnapshotRollover.isSameDay(snapshot: remoteSnapshot, referenceDate: referenceDate, calendar: calendar) {
            let todayKey = WidgetDayKey.string(for: referenceDate, calendar: calendar)
            let trustedByDayKey = (remoteSnapshot.dayKey == todayKey)
            for widgetHabit in remoteSnapshot.habits {
                let habitUpdatedToday = trustedByDayKey || calendar.isDate(widgetHabit.updatedAt, inSameDayAs: referenceDate)
                guard habitUpdatedToday else { continue }

                let key = HabitDayKey(habitID: widgetHabit.id, day: today)
                if let queued = resolvedByKey[key] {
                    if widgetHabit.updatedAt > queued.updatedAt {
                        resolvedByKey[key] = WidgetCheckInResolution(
                            habitID: widgetHabit.id,
                            day: today,
                            isCompleted: widgetHabit.isCompletedToday,
                            updatedAt: widgetHabit.updatedAt,
                            source: .remoteSnapshot
                        )
                    }
                    continue
                }

                if let localState = existingTodayStateByHabitID[widgetHabit.id] {
                    guard localState.isCompleted != widgetHabit.isCompletedToday else { continue }
                    if let localUpdatedAt = localState.updatedAt, widgetHabit.updatedAt <= localUpdatedAt {
                        continue
                    }
                    resolvedByKey[key] = WidgetCheckInResolution(
                        habitID: widgetHabit.id,
                        day: today,
                        isCompleted: widgetHabit.isCompletedToday,
                        updatedAt: widgetHabit.updatedAt,
                        source: .remoteSnapshot
                    )
                } else if widgetHabit.isCompletedToday {
                    resolvedByKey[key] = WidgetCheckInResolution(
                        habitID: widgetHabit.id,
                        day: today,
                        isCompleted: true,
                        updatedAt: widgetHabit.updatedAt,
                        source: .remoteSnapshot
                    )
                }
            }
        }

        return resolvedByKey.values.sorted {
            if $0.day == $1.day {
                return $0.updatedAt < $1.updatedAt
            }
            return $0.day < $1.day
        }
    }
}

/// 小组件写本地 App Group 待合并队列；主 App 下次启动时合并进 SwiftData。
public enum WidgetPendingCheckInStore {
    public static func append(_ checkIn: PendingWidgetCheckIn) {
        var queue = load()
        queue.append(checkIn)
        guard let data = try? WidgetJSONCodec.makeEncoder().encode(queue) else { return }
        WidgetSharedDefaults.suiteDefaults?.set(data, forKey: WidgetSharedDefaults.pendingCheckInsKey)
    }

    public static func load() -> [PendingWidgetCheckIn] {
        guard let data = WidgetSharedDefaults.suiteDefaults?.data(forKey: WidgetSharedDefaults.pendingCheckInsKey),
              let queue = try? WidgetJSONCodec.makeDecoder().decode([PendingWidgetCheckIn].self, from: data)
        else { return [] }
        return queue
    }

    /// 仅移除已落库的条目，保留合并期间小组件新追加的打卡记录。
    public static func removeProcessed(_ processed: [PendingWidgetCheckIn]) {
        guard !processed.isEmpty else { return }
        let latestProcessedTimestamp = processed.map(\.updatedAt).max() ?? .distantPast
        let processedHabitDays = Set(processed.map { "\($0.habitID.uuidString)-\($0.updatedAt.timeIntervalSince1970)" })
        let remaining = load().filter { item in
            if item.updatedAt > latestProcessedTimestamp {
                return true
            }
            return !processedHabitDays.contains("\(item.habitID.uuidString)-\(item.updatedAt.timeIntervalSince1970)")
        }
        if remaining.isEmpty {
            clear()
        } else if let data = try? WidgetJSONCodec.makeEncoder().encode(remaining) {
            WidgetSharedDefaults.suiteDefaults?.set(data, forKey: WidgetSharedDefaults.pendingCheckInsKey)
        }
    }

    public static func clear() {
        WidgetSharedDefaults.suiteDefaults?.removeObject(forKey: WidgetSharedDefaults.pendingCheckInsKey)
    }
}

/// 图片数据指纹：与写入 App Group 文件、远程去重逻辑共用同一套哈希。
public func widgetImageFingerprint(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
}

public struct RemoteBackupArchive: Codable, Sendable, Equatable {
    public var version: Int
    public var deviceKey: String
    public var exportedAt: Date
    public var habits: [RemoteBackupHabit]

    public init(version: Int = 1, deviceKey: String, exportedAt: Date = Date(), habits: [RemoteBackupHabit]) {
        self.version = version
        self.deviceKey = deviceKey
        self.exportedAt = exportedAt
        self.habits = habits
    }

    private enum CodingKeys: String, CodingKey {
        case version, deviceKey, exportedAt, habits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        deviceKey = try container.decodeIfPresent(String.self, forKey: .deviceKey) ?? ""
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        habits = try container.decodeIfPresent([RemoteBackupHabit].self, forKey: .habits) ?? []
    }
}

public struct RemoteBackupHabit: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var colorName: String?
    public var cardStyle: String?
    public var targetWeekdayMask: Int
    public var reminderEnabled: Bool
    public var reminderHour: Int
    public var reminderMinute: Int
    public var reminderWeekdayMask: Int
    public var sortOrder: Int
    public var createdAt: Date
    public var checkIns: [RemoteBackupCheckIn]

    public init(
        id: UUID,
        name: String,
        icon: String,
        colorName: String? = nil,
        cardStyle: String? = nil,
        targetWeekdayMask: Int,
        reminderEnabled: Bool,
        reminderHour: Int,
        reminderMinute: Int,
        reminderWeekdayMask: Int,
        sortOrder: Int,
        createdAt: Date,
        checkIns: [RemoteBackupCheckIn]
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorName = colorName
        self.cardStyle = cardStyle
        self.targetWeekdayMask = targetWeekdayMask
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.reminderWeekdayMask = reminderWeekdayMask
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.checkIns = checkIns
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, colorName, cardStyle, targetWeekdayMask
        case reminderEnabled, reminderHour, reminderMinute, reminderWeekdayMask
        case sortOrder, createdAt, checkIns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "flame.fill"
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName)
        cardStyle = try container.decodeIfPresent(String.self, forKey: .cardStyle)
        targetWeekdayMask = try container.decodeIfPresent(Int.self, forKey: .targetWeekdayMask) ?? ((1 << 7) - 1)
        reminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        reminderHour = try container.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 20
        reminderMinute = try container.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        reminderWeekdayMask = try container.decodeIfPresent(Int.self, forKey: .reminderWeekdayMask) ?? ((1 << 7) - 1)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        checkIns = try container.decodeIfPresent([RemoteBackupCheckIn].self, forKey: .checkIns) ?? []
    }
}

public struct RemoteBackupCheckIn: Codable, Sendable, Equatable {
    public var id: UUID
    public var day: Date
    public var isCompleted: Bool
    public var note: String
    public var createdAt: Date

    public init(id: UUID = UUID(), day: Date, isCompleted: Bool, note: String = "", createdAt: Date = Date()) {
        self.id = id
        self.day = day
        self.isCompleted = isCompleted
        self.note = note
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, day, isCompleted, note, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        day = try container.decode(Date.self, forKey: .day)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? true
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? day
    }
}

public enum BackupMergeStrategy: String, CaseIterable, Identifiable, Sendable {
    case keepLocal
    case overwriteWithImported

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keepLocal: "保留本地优先"
        case .overwriteWithImported: "覆盖更新"
        }
    }

    public var subtitle: String {
        switch self {
        case .keepLocal: "仅补充本地缺失的目标与历史打卡，同日冲突与现有设置保持本地不变。"
        case .overwriteWithImported: "按备份更新已有目标设置，并用备份覆盖同日冲突记录。"
        }
    }
}

public struct BackupConflictItem: Identifiable, Sendable, Equatable {
    public var id: String { "\(habitID.uuidString)-\(dayKey)" }
    public var habitID: UUID
    public var habitName: String
    public var day: Date
    public var dayKey: String
    public var localCompleted: Bool
    public var importedCompleted: Bool
    public var localNote: String
    public var importedNote: String

    public init(
        habitID: UUID,
        habitName: String,
        day: Date,
        dayKey: String,
        localCompleted: Bool,
        importedCompleted: Bool,
        localNote: String,
        importedNote: String
    ) {
        self.habitID = habitID
        self.habitName = habitName
        self.day = day
        self.dayKey = dayKey
        self.localCompleted = localCompleted
        self.importedCompleted = importedCompleted
        self.localNote = localNote
        self.importedNote = importedNote
    }
}

public struct BackupImportPlan: Sendable, Equatable {
    public var newHabitCount: Int
    public var updatedHabitCount: Int
    public var newCheckInCount: Int
    public var deduplicatedImportedCheckInCount: Int
    public var conflictItems: [BackupConflictItem]
    public var importedHabitTotal: Int
    public var exportedAt: Date

    public init(
        newHabitCount: Int,
        updatedHabitCount: Int,
        newCheckInCount: Int,
        deduplicatedImportedCheckInCount: Int,
        conflictItems: [BackupConflictItem],
        importedHabitTotal: Int,
        exportedAt: Date
    ) {
        self.newHabitCount = newHabitCount
        self.updatedHabitCount = updatedHabitCount
        self.newCheckInCount = newCheckInCount
        self.deduplicatedImportedCheckInCount = deduplicatedImportedCheckInCount
        self.conflictItems = conflictItems
        self.importedHabitTotal = importedHabitTotal
        self.exportedAt = exportedAt
    }

    public var conflictCount: Int { conflictItems.count }

    public var hasChanges: Bool {
        newHabitCount > 0 || updatedHabitCount > 0 || newCheckInCount > 0 || !conflictItems.isEmpty
    }
}

/// 按 (habitID, normalizedDay) 去重并预计算导入差异计划与合并结果。
public enum BackupImportPlanner {
    public static func deduplicateCheckIns(
        _ checkIns: [RemoteBackupCheckIn],
        calendar: Calendar = .current
    ) -> (deduplicated: [Date: RemoteBackupCheckIn], collapsedCount: Int) {
        var byDay: [Date: RemoteBackupCheckIn] = [:]
        var collapsedCount = 0

        for item in checkIns {
            let normalizedDay = calendar.startOfDay(for: item.day)
            var normalized = item
            normalized.day = normalizedDay

            if let existing = byDay[normalizedDay] {
                collapsedCount += 1
                if normalized.createdAt >= existing.createdAt {
                    if normalized.note.isEmpty, !existing.note.isEmpty {
                        normalized.note = existing.note
                    }
                    byDay[normalizedDay] = normalized
                } else if existing.note.isEmpty, !normalized.note.isEmpty {
                    var updatedExisting = existing
                    updatedExisting.note = normalized.note
                    byDay[normalizedDay] = updatedExisting
                }
            } else {
                byDay[normalizedDay] = normalized
            }
        }

        return (byDay, collapsedCount)
    }

    public static func makePlan(
        existingHabits: [RemoteBackupHabit],
        importedArchive: RemoteBackupArchive,
        calendar: Calendar = .current
    ) -> BackupImportPlan {
        let existingByID = Dictionary(uniqueKeysWithValues: existingHabits.map { ($0.id, $0) })
        var newHabitCount = 0
        var updatedHabitCount = 0
        var newCheckInCount = 0
        var collapsedTotal = 0
        var conflicts: [BackupConflictItem] = []

        for source in importedArchive.habits {
            let (importedByDay, collapsed) = deduplicateCheckIns(source.checkIns, calendar: calendar)
            collapsedTotal += collapsed

            guard let local = existingByID[source.id] else {
                newHabitCount += 1
                newCheckInCount += importedByDay.count
                continue
            }

            if hasMetadataDiff(local: local, imported: source) {
                updatedHabitCount += 1
            }

            let (localByDay, _) = deduplicateCheckIns(local.checkIns, calendar: calendar)
            for (day, importedCheckIn) in importedByDay.sorted(by: { $0.key < $1.key }) {
                guard let localCheckIn = localByDay[day] else {
                    newCheckInCount += 1
                    continue
                }

                if localCheckIn.isCompleted != importedCheckIn.isCompleted || localCheckIn.note != importedCheckIn.note {
                    conflicts.append(
                        BackupConflictItem(
                            habitID: source.id,
                            habitName: local.name.isEmpty ? source.name : local.name,
                            day: day,
                            dayKey: WidgetDayKey.string(for: day, calendar: calendar),
                            localCompleted: localCheckIn.isCompleted,
                            importedCompleted: importedCheckIn.isCompleted,
                            localNote: localCheckIn.note,
                            importedNote: importedCheckIn.note
                        )
                    )
                }
            }
        }

        conflicts.sort {
            if $0.day == $1.day {
                return $0.habitName < $1.habitName
            }
            return $0.day > $1.day
        }

        return BackupImportPlan(
            newHabitCount: newHabitCount,
            updatedHabitCount: updatedHabitCount,
            newCheckInCount: newCheckInCount,
            deduplicatedImportedCheckInCount: collapsedTotal,
            conflictItems: conflicts,
            importedHabitTotal: importedArchive.habits.count,
            exportedAt: importedArchive.exportedAt
        )
    }

    public static func merge(
        existingHabits: [RemoteBackupHabit],
        importedArchive: RemoteBackupArchive,
        strategy: BackupMergeStrategy,
        calendar: Calendar = .current
    ) -> [RemoteBackupHabit] {
        var mergedByID = Dictionary(uniqueKeysWithValues: existingHabits.map { ($0.id, $0) })

        for source in importedArchive.habits {
            let (importedByDay, _) = deduplicateCheckIns(source.checkIns, calendar: calendar)
            let sortedImported = importedByDay.values.sorted { $0.day < $1.day }

            guard var local = mergedByID[source.id] else {
                var inserted = source
                inserted.checkIns = sortedImported
                mergedByID[source.id] = inserted
                continue
            }

            if strategy == .overwriteWithImported {
                local.name = source.name
                local.icon = source.icon
                local.colorName = source.colorName ?? local.colorName
                local.cardStyle = source.cardStyle ?? local.cardStyle
                local.targetWeekdayMask = source.targetWeekdayMask == 0 ? ((1 << 7) - 1) : source.targetWeekdayMask
                local.reminderEnabled = source.reminderEnabled
                local.reminderHour = source.reminderHour
                local.reminderMinute = source.reminderMinute
                local.reminderWeekdayMask = source.reminderWeekdayMask == 0 ? ((1 << 7) - 1) : source.reminderWeekdayMask
                local.sortOrder = source.sortOrder
                local.createdAt = source.createdAt
            }

            var (localByDay, _) = deduplicateCheckIns(local.checkIns, calendar: calendar)
            for (day, importedCheckIn) in importedByDay {
                if let existingCheckIn = localByDay[day] {
                    if strategy == .overwriteWithImported {
                        var replaced = existingCheckIn
                        replaced.isCompleted = importedCheckIn.isCompleted
                        replaced.note = importedCheckIn.note
                        replaced.createdAt = max(existingCheckIn.createdAt, importedCheckIn.createdAt)
                        localByDay[day] = replaced
                    }
                } else {
                    localByDay[day] = importedCheckIn
                }
            }

            local.checkIns = localByDay.values.sorted { $0.day < $1.day }
            mergedByID[source.id] = local
        }

        return mergedByID.values.sorted {
            $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder
        }
    }

    private static func hasMetadataDiff(local: RemoteBackupHabit, imported: RemoteBackupHabit) -> Bool {
        let importedTargetMask = imported.targetWeekdayMask == 0 ? ((1 << 7) - 1) : imported.targetWeekdayMask
        let importedReminderMask = imported.reminderWeekdayMask == 0 ? ((1 << 7) - 1) : imported.reminderWeekdayMask
        return local.name != imported.name
            || local.icon != imported.icon
            || (imported.colorName != nil && local.colorName != imported.colorName)
            || (imported.cardStyle != nil && local.cardStyle != imported.cardStyle)
            || local.targetWeekdayMask != importedTargetMask
            || local.reminderEnabled != imported.reminderEnabled
            || local.reminderHour != imported.reminderHour
            || local.reminderMinute != imported.reminderMinute
            || local.reminderWeekdayMask != importedReminderMask
            || local.sortOrder != imported.sortOrder
    }
}
