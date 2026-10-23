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

        let snapshot = await WidgetSnapshotStore.loadSnapshot(reason: "widget toggle")
        guard let index = snapshot.habits.firstIndex(where: { $0.id == uuid }) else { return .result() }

        var habits = snapshot.habits
        habits[index].isCompletedToday.toggle()
        habits[index].updatedAt = Date()
        let updated = habits[index]

        var updatedSnapshot = snapshot
        updatedSnapshot.habits = habits
        updatedSnapshot.updatedAt = Date()
        updatedSnapshot.selectedHabitID = uuid

        // 本地：改 App Group 快照 + 写入待合并队列。
        if var localHabits = loadLocalSnapshots() {
            if let localIndex = localHabits.firstIndex(where: { $0.id == uuid }) {
                localHabits[localIndex].isCompletedToday = updated.isCompletedToday
                localHabits[localIndex].updatedAt = Date()
                saveLocalSnapshots(localHabits)
            }
        }
        WidgetPendingCheckInStore.append(
            PendingWidgetCheckIn(
                habitID: uuid,
                isCompletedToday: updated.isCompletedToday,
                day: Calendar.current.startOfDay(for: Date())
            )
        )

        // 远程：更新 Worker 快照（侧载场景下小组件与主 App 的桥）。
        await RemoteWidgetCheckInClient.postCheckIn(snapshot: updatedSnapshot)

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
    static func postCheckIn(snapshot: WidgetRemoteSnapshot) async {
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
                habitID: snapshot.selectedHabitID ?? UUID(),
                isCompletedToday: snapshot.habits.first(where: { $0.id == snapshot.selectedHabitID })?.isCompletedToday ?? false,
                snapshot: snapshot
            )
            request.httpBody = try widgetJSONEncoder.encode(body)
            _ = try await URLSession.shared.data(for: request)
        } catch {
            // 网络失败不打断打卡：本地队列已更新，主 App 启动时会再对齐远程。
        }
    }
}
