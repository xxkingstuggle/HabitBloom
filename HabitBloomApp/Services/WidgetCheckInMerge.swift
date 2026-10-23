import Foundation
import SwiftData

/// 小组件（含侧载场景下只能走远程的打卡）产生的打卡动作，
/// 统一在主 App 启动时合并回 SwiftData，保证本地永远是完整真相。
enum WidgetCheckInMerge {
    @MainActor
    static func mergePendingWidgetCheckIns(into context: ModelContext) async {
        var changed = false

        // 1. 本地 App Group 队列（Mac Catalyst / 正常安装时小组件直接写入）。
        let pending = WidgetPendingCheckInStore.load()
        if !pending.isEmpty {
            let habits = (try? context.fetch(FetchDescriptor<HabitEntity>())) ?? []
            let habitsByID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })

            for checkIn in pending {
                guard let habit = habitsByID[checkIn.habitID] else { continue }
                let day = Calendar.current.startOfDay(for: checkIn.day)
                if let existing = (habit.checkIns ?? []).first(where: { $0.day == day }) {
                    if existing.isCompleted != checkIn.isCompletedToday {
                        existing.isCompleted = checkIn.isCompletedToday
                        changed = true
                    }
                } else {
                    var checkIns = habit.checkIns ?? []
                    checkIns.append(CheckInEntity(day: day, isCompleted: checkIn.isCompletedToday, habit: habit))
                    habit.checkIns = checkIns
                    changed = true
                }
            }

            if changed {
                try? context.save()
            }
            WidgetPendingCheckInStore.clear()
        }

        // 2. 远程快照（侧载时小组件打卡只更新了 Worker）。
        guard RemoteWidgetConfig.isReadable else { return }
        guard var components = URLComponents(string: RemoteWidgetConfig.baseURLString) else { return }
        components.path = "/v1/snapshot/\(RemoteWidgetConfig.deviceKey)"
        guard let url = components.url else { return }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return }
            let snapshot = try widgetJSONDecoder.decode(WidgetRemoteSnapshot.self, from: data)

            let habits = (try? context.fetch(FetchDescriptor<HabitEntity>())) ?? []
            let habitsByID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
            let today = Calendar.current.startOfDay(for: Date())
            var remoteChanged = false

            for widgetHabit in snapshot.habits {
                guard let habit = habitsByID[widgetHabit.id] else { continue }
                if let existing = (habit.checkIns ?? []).first(where: { $0.day == today }) {
                    if existing.isCompleted != widgetHabit.isCompletedToday {
                        existing.isCompleted = widgetHabit.isCompletedToday
                        remoteChanged = true
                    }
                } else if widgetHabit.isCompletedToday {
                    var checkIns = habit.checkIns ?? []
                    checkIns.append(CheckInEntity(day: today, isCompleted: true, habit: habit))
                    habit.checkIns = checkIns
                    remoteChanged = true
                }
            }

            if remoteChanged {
                try? context.save()
                let refreshed = (try? context.fetch(FetchDescriptor<HabitEntity>())) ?? []
                WidgetSnapshotWriter.scheduleWrite(habits: refreshed, delayMilliseconds: 0, backupDelayMilliseconds: 2_500)
            }
        } catch {
            // 网络不可用时静默跳过：本地队列已处理，远程下次启动再对齐。
        }
    }
}
