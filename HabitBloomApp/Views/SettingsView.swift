import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\HabitEntity.sortOrder), SortDescriptor(\HabitEntity.createdAt)]) private var habits: [HabitEntity]
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @State private var backupMessage: String?
    @State private var isBackupBusy = false
    @State private var exportDocument: BackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false

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

            Section("本地备份") {
                Button {
                    exportLocalBackup()
                } label: {
                    Label("导出 JSON 备份", systemImage: "square.and.arrow.up")
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("导入 JSON 备份", systemImage: "square.and.arrow.down")
                }
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
                Text("本地备份与云端备份都只保存目标设置、频率、提醒和打卡记录；自定义图片仅留在当前设备与小组件快照里。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "HabitBloom-备份-\(Date.now.formatted(.dateTime.year().month().day()))"
        ) { result in
            switch result {
            case .success:
                backupMessage = "本地备份已导出"
            case .failure(let error):
                backupMessage = "导出失败：\(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            importLocalBackup(result)
        }
    }

    private func exportLocalBackup() {
        do {
            let data = try RemoteBackupService.exportLocalArchive(habits: habits)
            exportDocument = BackupDocument(data: data)
            showingExporter = true
        } catch {
            backupMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importLocalBackup(_ result: Result<URL, Error>) {
        isBackupBusy = true
        backupMessage = "正在导入..."
        Task {
            defer { isBackupBusy = false }
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let restored = try RemoteBackupService.importLocalArchive(
                    data: data,
                    into: modelContext,
                    existingHabits: habits
                )
                WidgetSnapshotWriter.scheduleWrite(habits: restored, delayMilliseconds: 0)
                for reminderSnapshot in restored.map(ReminderScheduleSnapshot.init) {
                    await ReminderScheduler.reschedule(for: reminderSnapshot)
                }
                backupMessage = "本地备份已导入 \(restored.count) 个目标"
            } catch {
                backupMessage = "导入失败：\(error.localizedDescription)"
            }
        }
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

private struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
