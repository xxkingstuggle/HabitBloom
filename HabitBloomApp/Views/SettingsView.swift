import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\HabitEntity.sortOrder), SortDescriptor(\HabitEntity.createdAt)]) private var habits: [HabitEntity]
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("syncFolderBookmark") private var syncFolderBookmark = Data()
    @AppStorage("syncFolderName") private var syncFolderName = ""
    @State private var showingFolderPicker = false
    @State private var syncMessage: String?

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
                LabeledContent("小组件共享", value: "本地 App Group")
            }

            Section("手动同步") {
                LabeledContent("同步文件夹", value: syncFolderName.isEmpty ? "未选择" : syncFolderName)

                Button {
                    showingFolderPicker = true
                } label: {
                    Label(syncFolderName.isEmpty ? "选择 iCloud Drive 文件夹" : "更换同步文件夹", systemImage: "folder")
                }

                Button {
                    exportToSelectedFolder()
                } label: {
                    Label("导出到文件夹", systemImage: "square.and.arrow.up")
                }
                .disabled(syncFolderBookmark.isEmpty)

                Button {
                    importFromSelectedFolder()
                } label: {
                    Label("从文件夹导入", systemImage: "square.and.arrow.down")
                }
                .disabled(syncFolderBookmark.isEmpty)

                if let syncMessage {
                    Text(syncMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("说明") {
                Text("当前版本不使用 CloudKit。你可以选择 iCloud Drive 里的文件夹做手动同步，App 会在其中读写 habit-bloom.json。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
        }
    }

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            syncFolderBookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            syncFolderName = url.lastPathComponent
            syncMessage = "已选择 \(url.lastPathComponent)"
        } catch {
            syncMessage = "选择失败：\(error.localizedDescription)"
        }
    }

    private func exportToSelectedFolder() {
        do {
            let url = try resolvedSyncFolderURL()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            try ManualFolderSyncService.export(habits: habits, to: url)
            syncMessage = "已导出 \(habits.count) 个目标"
        } catch {
            syncMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importFromSelectedFolder() {
        do {
            let url = try resolvedSyncFolderURL()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            try ManualFolderSyncService.import(from: url, into: modelContext, existingHabits: habits)
            WidgetSnapshotWriter.write(habits: habits)
            syncMessage = "导入完成"
        } catch {
            syncMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func resolvedSyncFolderURL() throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: syncFolderBookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            syncFolderBookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }

        return url
    }
}
