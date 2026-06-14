import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\HabitEntity.sortOrder), SortDescriptor(\HabitEntity.createdAt)]) private var habits: [HabitEntity]
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @State private var backupMessage: String?
    @State private var isBackupBusy = false

    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
            }

            Section("数据") {
                LabeledContent("存储", value: "本地设备")
                LabeledContent("小组件", value: "Cloudflare 远程快照")
                LabeledContent("备份", value: "云端文本备份")
            }

            Section("云端备份") {
                Button {
                    uploadBackup()
                } label: {
                    Label("立即备份到服务器", systemImage: "icloud.and.arrow.up")
                }
                .disabled(isBackupBusy)

                Button {
                    restoreBackup()
                } label: {
                    Label("从服务器恢复", systemImage: "icloud.and.arrow.down")
                }
                .disabled(isBackupBusy)

                if let backupMessage {
                    Text(backupMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("说明") {
                Text("云端备份保存目标名、图标、颜色、卡片样式、频率、提醒和打卡记录；自定义图片只用于当前设备和小组件快照，不做长期备份。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
    }

    private func uploadBackup() {
        isBackupBusy = true
        backupMessage = "正在备份..."
        Task {
            do {
                let archive = try await RemoteBackupService.uploadNow(habits: habits)
                backupMessage = "已备份 \(archive.habits.count) 个目标"
            } catch {
                backupMessage = "备份失败：\(error.localizedDescription)"
            }
            isBackupBusy = false
        }
    }

    private func restoreBackup() {
        isBackupBusy = true
        backupMessage = "正在恢复..."
        Task {
            do {
                let archive = try await RemoteBackupService.download()
                let widgetSnapshot = try? await RemoteBackupService.downloadWidgetSnapshot()
                let restoredHabits = try RemoteBackupService.restore(
                    archive: archive,
                    into: modelContext,
                    existingHabits: habits,
                    widgetSnapshot: widgetSnapshot
                )
                WidgetSnapshotWriter.scheduleWrite(habits: restoredHabits, delayMilliseconds: 0)
                for reminderSnapshot in restoredHabits.map(ReminderScheduleSnapshot.init) {
                    await ReminderScheduler.reschedule(for: reminderSnapshot)
                }
                backupMessage = "已恢复 \(archive.habits.count) 个目标"
            } catch {
                backupMessage = "恢复失败：\(error.localizedDescription)"
            }
            isBackupBusy = false
        }
    }
}
