import Foundation

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
    public var selectedHabitID: UUID?
    public var habits: [WidgetHabitSnapshot]

    public init(deviceKey: String, updatedAt: Date, selectedHabitID: UUID?, habits: [WidgetHabitSnapshot]) {
        self.deviceKey = deviceKey
        self.updatedAt = updatedAt
        self.selectedHabitID = selectedHabitID
        self.habits = habits
    }

    private enum CodingKeys: String, CodingKey {
        case deviceKey, updatedAt, selectedHabitID, habits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceKey = try container.decodeIfPresent(String.self, forKey: .deviceKey) ?? ""
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
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
    public var snapshot: WidgetRemoteSnapshot?

    public init(habitID: UUID, isCompletedToday: Bool, snapshot: WidgetRemoteSnapshot?) {
        self.habitID = habitID
        self.isCompletedToday = isCompletedToday
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

public let widgetJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

public let widgetJSONEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

/// 小组件写本地 App Group 待合并队列；主 App 下次启动时合并进 SwiftData。
public enum WidgetPendingCheckInStore {
    public static func append(_ checkIn: PendingWidgetCheckIn) {
        var queue = load()
        queue.append(checkIn)
        guard let data = try? widgetJSONEncoder.encode(queue) else { return }
        WidgetSharedDefaults.suiteDefaults?.set(data, forKey: WidgetSharedDefaults.pendingCheckInsKey)
    }

    public static func load() -> [PendingWidgetCheckIn] {
        guard let data = WidgetSharedDefaults.suiteDefaults?.data(forKey: WidgetSharedDefaults.pendingCheckInsKey),
              let queue = try? widgetJSONDecoder.decode([PendingWidgetCheckIn].self, from: data)
        else { return [] }
        return queue
    }

    public static func clear() {
        WidgetSharedDefaults.suiteDefaults?.removeObject(forKey: WidgetSharedDefaults.pendingCheckInsKey)
    }
}

/// 图片数据指纹：与写入 App Group 文件、远程去重逻辑共用同一套哈希。
public func widgetImageFingerprint(_ data: Data) -> String {
    var hash: UInt64 = 5381
    for byte in data.prefix(4096) {
        hash = ((hash << 5) &+ hash) &+ UInt64(byte)
    }
    hash = ((hash << 5) &+ hash) &+ UInt64(data.count)
    return String(hash, radix: 16)
}
