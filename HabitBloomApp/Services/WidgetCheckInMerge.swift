import Foundation
import SwiftData

extension Notification.Name {
    static let habitBloomDidMergeWidgetCheckIns = Notification.Name("habitBloomDidMergeWidgetCheckIns")
}

struct WidgetCheckInMergeResult: Sendable {
    let didChange: Bool
    let mergedCount: Int
}

/// 序列化应用启动与回到前台的同步流程：
/// 先恢复/清理提醒并完成小组件双通道打卡合并，再允许 UI 上传最新快照，彻底消除启动竞态。
@MainActor
final class StartupSyncCoordinator {
    static let shared = StartupSyncCoordinator()

    private var initialSyncTask: Task<WidgetCheckInMergeResult, Never>?
    private var foregroundSyncTask: Task<WidgetCheckInMergeResult, Never>?
    private var hasCompletedInitialSync = false

    private init() {}

    @discardableResult
    func ensureInitialSync(using context: ModelContext) async -> WidgetCheckInMergeResult {
        if hasCompletedInitialSync {
            return WidgetCheckInMergeResult(didChange: false, mergedCount: 0)
        }
        if let existingTask = initialSyncTask {
            return await existingTask.value
        }
        let task = Task { @MainActor in
            let result = await performFullSync(using: context)
            hasCompletedInitialSync = true
            initialSyncTask = nil
            return result
        }
        initialSyncTask = task
        return await task.value
    }

    @discardableResult
    func performForegroundSync(using context: ModelContext) async -> WidgetCheckInMergeResult {
        if !hasCompletedInitialSync {
            return await ensureInitialSync(using: context)
        }
        if let existingTask = foregroundSyncTask {
            return await existingTask.value
        }
        let task = Task { @MainActor in
            let result = await performFullSync(using: context)
            foregroundSyncTask = nil
            return result
        }
        foregroundSyncTask = task
        return await task.value
    }

    private func performFullSync(using context: ModelContext) async -> WidgetCheckInMergeResult {
        let habits = (try? context.fetch(FetchDescriptor<HabitEntity>())) ?? []
        let snapshots = habits.map(ReminderScheduleSnapshot.init)
        let validHabitIDs = Set(habits.map(\.id))
        await ReminderScheduler.restoreSuppressedReminders(snapshots: snapshots)
        await ReminderScheduler.pruneOrphanedReminders(validHabitIDs: validHabitIDs)
        return await WidgetCheckInMerge.mergePendingWidgetCheckIns(into: context)
    }
}

/// 小组件（含侧载场景下只能走远程的打卡）产生的打卡动作，
/// 统一在主 App 启动或切回前台时按时间戳双通道仲裁合并回 SwiftData，保证本地永远是完整真相。
enum WidgetCheckInMerge {
    @MainActor
    @discardableResult
    static func mergePendingWidgetCheckIns(into context: ModelContext) async -> WidgetCheckInMergeResult {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let pending = WidgetPendingCheckInStore.load()
        let remoteSnapshot = await fetchRemoteSnapshot()

        guard !pending.isEmpty || remoteSnapshot != nil else {
            return WidgetCheckInMergeResult(didChange: false, mergedCount: 0)
        }

        let habits = (try? context.fetch(FetchDescriptor<HabitEntity>())) ?? []
        let habitsByID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })

        var existingTodayStateByHabitID: [UUID: LocalTodayCheckInState] = [:]
        for habit in habits {
            let todayEntries = (habit.checkIns ?? []).filter { calendar.startOfDay(for: $0.day) == today }
            if let latestToday = todayEntries.max(by: { $0.createdAt < $1.createdAt }) {
                existingTodayStateByHabitID[habit.id] = LocalTodayCheckInState(
                    isCompleted: latestToday.isCompleted,
                    updatedAt: latestToday.createdAt
                )
            }
        }

        let resolutions = WidgetCheckInReconciler.reconcile(
            localPending: pending,
            remoteSnapshot: remoteSnapshot,
            existingTodayStateByHabitID: existingTodayStateByHabitID,
            referenceDate: now,
            calendar: calendar
        )

        var didChange = false
        var mergedCount = 0
        var reminderUpdates: [(ReminderScheduleSnapshot, Bool)] = []

        for resolution in resolutions {
            guard let habit = habitsByID[resolution.habitID] else { continue }
            let normalizedDay = calendar.startOfDay(for: resolution.day)

            let existingForDay = (habit.checkIns ?? []).filter { calendar.startOfDay(for: $0.day) == normalizedDay }
            if let keeper = existingForDay.max(by: { $0.createdAt < $1.createdAt }) {
                keeper.day = normalizedDay
                for duplicate in existingForDay where duplicate.id != keeper.id {
                    if keeper.note.isEmpty, !duplicate.note.isEmpty {
                        keeper.note = duplicate.note
                    }
                    context.delete(duplicate)
                    didChange = true
                }
                if keeper.isCompleted != resolution.isCompleted {
                    keeper.isCompleted = resolution.isCompleted
                    keeper.createdAt = max(keeper.createdAt, resolution.updatedAt)
                    didChange = true
                    mergedCount += 1
                    if normalizedDay == today {
                        reminderUpdates.append((ReminderScheduleSnapshot(habit: habit), resolution.isCompleted))
                    }
                } else if resolution.updatedAt > keeper.createdAt {
                    keeper.createdAt = resolution.updatedAt
                    didChange = true
                }
            } else if resolution.isCompleted || resolution.source == .localQueue {
                var checkIns = habit.checkIns ?? []
                checkIns.append(
                    CheckInEntity(
                        day: normalizedDay,
                        isCompleted: resolution.isCompleted,
                        createdAt: resolution.updatedAt,
                        habit: habit
                    )
                )
                habit.checkIns = checkIns
                didChange = true
                mergedCount += 1
                if normalizedDay == today {
                    reminderUpdates.append((ReminderScheduleSnapshot(habit: habit), resolution.isCompleted))
                }
            }
        }

        if didChange {
            do {
                try context.save()
            } catch {
                print("[HabitBloomMerge] Failed to save merged widget check-ins; keeping local queue intact: \(error.localizedDescription)")
                return WidgetCheckInMergeResult(didChange: false, mergedCount: 0)
            }
        }

        // 只有在未报错（且有变动时 context.save() 已真正落盘）后，才清理本次处理过的本地队列条目。
        if !pending.isEmpty {
            WidgetPendingCheckInStore.removeProcessed(pending)
        }

        for (reminderSnapshot, completedToday) in reminderUpdates {
            if completedToday {
                await ReminderScheduler.suppressTodayIfNeeded(for: reminderSnapshot)
            } else {
                await ReminderScheduler.restoreTodayIfNeeded(for: reminderSnapshot)
            }
        }

        if didChange {
            NotificationCenter.default.post(name: .habitBloomDidMergeWidgetCheckIns, object: nil)
        }

        return WidgetCheckInMergeResult(didChange: didChange, mergedCount: mergedCount)
    }

    private static func fetchRemoteSnapshot() async -> WidgetRemoteSnapshot? {
        guard RemoteWidgetConfig.isReadable else { return nil }
        guard var components = URLComponents(string: RemoteWidgetConfig.baseURLString) else { return nil }
        components.path = "/v1/snapshot/\(RemoteWidgetConfig.deviceKey)"
        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            return try widgetJSONDecoder.decode(WidgetRemoteSnapshot.self, from: data)
        } catch {
            return nil
        }
    }
}
