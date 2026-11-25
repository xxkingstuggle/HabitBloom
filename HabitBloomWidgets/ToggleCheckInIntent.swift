import AppIntents
import Foundation
import WidgetKit

/// 小组件一键打卡：
/// - App Group 可用时（正常安装 / Mac Catalyst）直接改快照并入队，主 App 启动后合并进 SwiftData；
/// - App Group 不可用时（侧载）只更新远程 Worker，主 App 启动后从远程对齐。
struct ToggleHabitCheckInIntent: AppIntent {
    static let title: LocalizedStringResource = "切换今日打卡"
    static let description = IntentDescription("在小组件上直接完成或取消今日打卡。")

    @Parameter(title: "目标 ID")
    var habitID: String

    init() {
        habitID = ""
    }

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: habitID) else { return .result() }

        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let todayKey = WidgetDayKey.string(for: now, calendar: calendar)

        let loadedSnapshot = await WidgetSnapshotStore.loadSnapshot(reason: "widget toggle")
        let rolledSnapshot = WidgetSnapshotRollover.rolledOver(loadedSnapshot, referenceDate: now, calendar: calendar)
        guard let index = rolledSnapshot.habits.firstIndex(where: { $0.id == uuid }) else { return .result() }

        var habits = rolledSnapshot.habits
        habits[index].isCompletedToday.toggle()
        habits[index].updatedAt = now
        let updated = habits[index]

        var updatedSnapshot = rolledSnapshot
        updatedSnapshot.habits = habits
        updatedSnapshot.updatedAt = now
        updatedSnapshot.dayKey = todayKey
        updatedSnapshot.selectedHabitID = uuid

        // 本地：先按今日翻篇再更新 App Group 快照与扩展缓存，同时写入待合并队列。
        if var localHabits = loadLocalSnapshots() {
            let localWrapper = WidgetRemoteSnapshot(
                deviceKey: RemoteWidgetConfig.deviceKey,
                updatedAt: localHabits.map(\.updatedAt).max() ?? now,
                dayKey: nil,
                selectedHabitID: uuid,
                habits: localHabits
            )
            localHabits = WidgetSnapshotRollover.rolledOver(localWrapper, referenceDate: now, calendar: calendar).habits
            if let localIndex = localHabits.firstIndex(where: { $0.id == uuid }) {
                localHabits[localIndex].isCompletedToday = updated.isCompletedToday
                localHabits[localIndex].updatedAt = now
            }
            saveLocalSnapshots(localHabits)
        }
        WidgetSnapshotStore.saveCachedSnapshot(updatedSnapshot)
        WidgetPendingCheckInStore.append(
            PendingWidgetCheckIn(
                habitID: uuid,
                isCompletedToday: updated.isCompletedToday,
                day: today,
                updatedAt: now
            )
        )

        // 远程：更新 Worker 快照（侧载场景下小组件与主 App 的桥）。
        await RemoteWidgetCheckInClient.postCheckIn(
            habitID: uuid,
            isCompletedToday: updated.isCompletedToday,
            dayKey: todayKey,
            snapshot: updatedSnapshot
        )

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }

    private func loadLocalSnapshots() -> [WidgetHabitSnapshot]? {
        guard let data = WidgetSharedDefaults.suiteDefaults?.data(forKey: WidgetSharedDefaults.snapshotsKey) else { return nil }
        return try? widgetJSONDecoder.decode([WidgetHabitSnapshot].self, from: data)
    }

    private func saveLocalSnapshots(_ snapshots: [WidgetHabitSnapshot]) {
        guard let data = try? widgetJSONEncoder.encode(snapshots) else { return }
        WidgetSharedDefaults.suiteDefaults?.set(data, forKey: WidgetSharedDefaults.snapshotsKey)
    }
}

enum RemoteWidgetCheckInClient {
    static func postCheckIn(
        habitID: UUID,
        isCompletedToday: Bool,
        dayKey: String,
        snapshot: WidgetRemoteSnapshot
    ) async {
        guard RemoteWidgetConfig.isReadable else { return }
        guard var components = URLComponents(string: RemoteWidgetConfig.baseURLString) else { return }
        components.path = "/v1/checkin/\(RemoteWidgetConfig.deviceKey)"
        guard let url = components.url else { return }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 8
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !RemoteWidgetConfig.writeToken.isEmpty, !RemoteWidgetConfig.writeToken.contains("$(") {
                request.setValue("Bearer \(RemoteWidgetConfig.writeToken)", forHTTPHeaderField: "Authorization")
            }
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let body = RemoteCheckInRequest(
                habitID: habitID,
                isCompletedToday: isCompletedToday,
                dayKey: dayKey,
                snapshot: snapshot
            )
            request.httpBody = try widgetJSONEncoder.encode(body)
            _ = try await URLSession.shared.data(for: request)
        } catch {
            // 网络失败不打断打卡：本地队列已更新，主 App 启动时会再对齐远程。
        }
    }
}
