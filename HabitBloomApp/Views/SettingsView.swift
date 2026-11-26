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
    @State private var pendingImport: PendingBackupImport?
    @State private var selectedMergeStrategy: BackupMergeStrategy = .overwriteWithImported

    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
            }

            Section("同步与数据状态") {
                RemoteConnectionStatusRow()
                LabeledContent("本地存储", value: "SwiftData（共 \(habits.count) 个目标）")
                LabeledContent("小组件通道", value: RemoteWidgetConfig.isReadable ? "本地共享 + Cloudflare 远程快照" : "仅本地共享")
                LabeledContent("备份格式", value: "同构 JSON（按目标+日期自动去重）")
            }

            Section("本地备份") {
                Button {
                    exportLocalBackup()
                } label: {
                    Label("导出 JSON 备份", systemImage: "square.and.arrow.up")
                }
                .disabled(isBackupBusy)

                Button {
                    showingImporter = true
                } label: {
                    Label("导入 JSON 备份（含冲突预览）", systemImage: "square.and.arrow.down")
                }
                .disabled(isBackupBusy)
            }

            Section("云端备份") {
                Button {
                    uploadBackup()
                } label: {
                    Label("立即备份到服务器", systemImage: "icloud.and.arrow.up")
                }
                .disabled(isBackupBusy || !RemoteWidgetConfig.isWritable)

                Button {
                    restoreBackup()
                } label: {
                    Label("从服务器恢复（含冲突预览）", systemImage: "icloud.and.arrow.down")
                }
                .disabled(isBackupBusy || !RemoteWidgetConfig.isWritable)

                if !RemoteWidgetConfig.isWritable {
                    Text("当前构建未配置完整的远程 Worker 地址、设备标识或写入密钥，云端备份与恢复已禁用；本地 JSON 导入导出仍可正常使用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

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

            Section("关于 HabitBloom") {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.72)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("HabitBloom")
                                .font(.headline)
                            Text("v\(Self.appVersion)")
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.14)))
                        }
                        Text("由 张家鑫 · Xin (@xxkingstuggle) 设计与开发")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Link(destination: URL(string: "https://myzjx.com")!) {
                    HStack {
                        Label("官方网站", systemImage: "globe")
                        Spacer()
                        Text("myzjx.com")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                Link(destination: URL(string: "https://myzjx.com/software/habitbloom/")!) {
                    HStack {
                        Label("产品主页", systemImage: "sparkles")
                        Spacer()
                        Text("myzjx.com/software/habitbloom/")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                Link(destination: URL(string: "https://github.com/xxkingstuggle")!) {
                    HStack {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        Spacer()
                        Text("@xxkingstuggle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text("© 2026 Xin (@xxkingstuggle)")
                    .font(.caption)
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
            prepareLocalImport(result)
        }
        .sheet(item: $pendingImport) { item in
            BackupImportPreviewSheet(
                pendingImport: item,
                selectedStrategy: $selectedMergeStrategy,
                onConfirm: { strategy in
                    applyPendingImport(item, strategy: strategy)
                }
            )
        }
    }

    private static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let build, !build.isEmpty, build != short {
            return "\(short) (\(build))"
        }
        return short
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

    private func prepareLocalImport(_ result: Result<URL, Error>) {
        isBackupBusy = true
        backupMessage = "正在解析本地备份并计算差异..."
        Task {
            defer { isBackupBusy = false }
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let archive = try RemoteBackupService.decodeLocalArchive(from: data)
                let plan = RemoteBackupService.makeImportPlan(archive: archive, existingHabits: habits)
                selectedMergeStrategy = plan.conflictItems.isEmpty ? .overwriteWithImported : .keepLocal
                pendingImport = PendingBackupImport(
                    sourceTitle: "本地 JSON 备份",
                    archive: archive,
                    widgetSnapshot: nil,
                    plan: plan
                )
                backupMessage = nil
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
        backupMessage = "正在下载云端备份并计算差异..."
        Task {
            do {
                let archive = try await RemoteBackupService.download()
                let widgetSnapshot = try? await RemoteBackupService.downloadWidgetSnapshot()
                let plan = RemoteBackupService.makeImportPlan(archive: archive, existingHabits: habits)
                selectedMergeStrategy = plan.conflictItems.isEmpty ? .overwriteWithImported : .keepLocal
                pendingImport = PendingBackupImport(
                    sourceTitle: "云端备份",
                    archive: archive,
                    widgetSnapshot: widgetSnapshot,
                    plan: plan
                )
                backupMessage = nil
            } catch {
                backupMessage = "下载恢复预览失败：\(error.localizedDescription)"
            }
            isBackupBusy = false
        }
    }

    private func applyPendingImport(_ item: PendingBackupImport, strategy: BackupMergeStrategy) {
        pendingImport = nil
        isBackupBusy = true
        backupMessage = "正在按「\(strategy.title)」合并..."
        Task {
            defer { isBackupBusy = false }
            do {
                let restoredHabits = try RemoteBackupService.restore(
                    archive: item.archive,
                    into: modelContext,
                    existingHabits: habits,
                    widgetSnapshot: item.widgetSnapshot,
                    strategy: strategy
                )
                WidgetSnapshotWriter.scheduleWrite(habits: restoredHabits, delayMilliseconds: 0)
                for reminderSnapshot in restoredHabits.map(ReminderScheduleSnapshot.init) {
                    await ReminderScheduler.reschedule(for: reminderSnapshot)
                }
                backupMessage = "\(item.sourceTitle)合并完成（\(strategy.title)）：共 \(restoredHabits.count) 个目标，新增 \(item.plan.newHabitCount) 个目标、\(item.plan.newCheckInCount) 条打卡"
            } catch {
                backupMessage = "恢复失败：\(error.localizedDescription)"
            }
        }
    }
}

private struct PendingBackupImport: Identifiable {
    let id = UUID()
    let sourceTitle: String
    let archive: RemoteBackupArchive
    let widgetSnapshot: WidgetRemoteSnapshot?
    let plan: BackupImportPlan
}

private struct RemoteConnectionStatusRow: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var statusInfo: (title: String, detail: String, tint: Color, icon: String) {
        let host = URL(string: RemoteWidgetConfig.baseURLString)?.host ?? "未配置域名"
        if RemoteWidgetConfig.isWritable {
            return ("已连接云端", host, .green, "checkmark.shield.fill")
        }
        if RemoteWidgetConfig.isReadable {
            return ("仅只读快照", host, .orange, "eye.circle.fill")
        }
        return ("本地离线模式", "未启用远程 Worker", .secondary, "internaldrive")
    }

    var body: some View {
        let status = statusInfo
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("连接状态")
                    .font(.body)
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.caption.weight(.bold))
                Text(status.title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(status.tint == .secondary ? Color.primary : status.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        reduceTransparency
                            ? (colorScheme == .dark ? Color.appSurfaceElevated : Color.appBackgroundSecondary)
                            : status.tint.opacity(colorScheme == .dark ? 0.22 : 0.14)
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(status.tint.opacity(reduceTransparency ? 0.65 : 0.35), lineWidth: 1)
            )
        }
        .padding(.vertical, 2)
    }
}

private struct BackupImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let pendingImport: PendingBackupImport
    @Binding var selectedStrategy: BackupMergeStrategy
    let onConfirm: (BackupMergeStrategy) -> Void

    var body: some View {
        let plan = pendingImport.plan

        NavigationStack {
            List {
                Section("备份概览") {
                    LabeledContent("来源", value: pendingImport.sourceTitle)
                    LabeledContent("导出时间", value: plan.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("备份包含目标", value: "\(plan.importedHabitTotal) 个")

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ImportMetricTile(title: "新增目标", value: "\(plan.newHabitCount)", tint: .green)
                        ImportMetricTile(title: "更新目标", value: "\(plan.updatedHabitCount)", tint: .blue)
                        ImportMetricTile(title: "新增打卡", value: "\(plan.newCheckInCount)", tint: .teal)
                        ImportMetricTile(title: "同日冲突", value: "\(plan.conflictCount)", tint: plan.conflictCount > 0 ? .orange : .secondary)
                    }
                    .padding(.vertical, 4)

                    if plan.deduplicatedImportedCheckInCount > 0 {
                        Label("已在预览阶段自动折叠备份内 \(plan.deduplicatedImportedCheckInCount) 条同日重复记录。", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("合并策略") {
                    Picker("冲突处理", selection: $selectedStrategy) {
                        ForEach(BackupMergeStrategy.allCases) { strategy in
                            Text(strategy.title).tag(strategy)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(selectedStrategy.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !plan.conflictItems.isEmpty {
                    Section("同日冲突明细（\(plan.conflictItems.count) 项）") {
                        ForEach(plan.conflictItems.prefix(20)) { conflict in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(conflict.habitName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(conflict.dayKey)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 12) {
                                    Text("本地：\(conflict.localCompleted ? "已打卡" : "未打卡")\(conflict.localNote.isEmpty ? "" : " · 有备注")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("备份：\(conflict.importedCompleted ? "已打卡" : "未打卡")\(conflict.importedNote.isEmpty ? "" : " · 有备注")")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        if plan.conflictItems.count > 20 {
                            Text("其余 \(plan.conflictItems.count - 20) 项冲突将按同一策略处理。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("冲突检查") {
                        Label("未检测到同日打卡冲突，可直接安全合并。", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("备份冲突预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认合并") {
                        onConfirm(selectedStrategy)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 460)
    }
}

private struct ImportMetricTile: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint == .secondary ? Color.primary : tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.adaptiveChipSurface(for: colorScheme, reduceTransparency: reduceTransparency))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.adaptiveCardBorder(for: colorScheme, reduceTransparency: reduceTransparency).opacity(0.65), lineWidth: 0.8)
        )
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
