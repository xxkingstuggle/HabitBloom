import PhotosUI
import SwiftData
import SwiftUI

struct HabitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\HabitEntity.sortOrder), SortDescriptor(\HabitEntity.createdAt)]) private var habits: [HabitEntity]

    let habit: HabitEntity?

    @State private var name = ""
    @State private var icon = "flame.fill"
    @State private var colorName = HabitPalette.coral.rawValue
    @State private var cardStyle = HabitCardKind.soft.rawValue
    @State private var imageData: Data?
    @State private var targetWeekdayMask = WeekdayMask.all
    @State private var reminderEnabled = false
    @State private var reminderHour = 20
    @State private var reminderMinute = 0
    @State private var reminderWeekdayMask = WeekdayMask.all
    @State private var photoItem: PhotosPickerItem?
    @State private var showingIconPicker = false

    var body: some View {
        let imageButtonTitle = imageData == nil ? "选择自定义图片" : "更换自定义图片"
        let isImageStyle = cardStyle == HabitCardKind.image.rawValue
        let selectedPalette = HabitPalette(rawValue: colorName) ?? .coral
        let selectedCardKind = HabitCardKind(rawValue: cardStyle) ?? .soft

        NavigationStack {
            Form {
                Section("实时预览") {
                    HabitEditorPreviewCard(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我的新目标" : name.trimmingCharacters(in: .whitespacesAndNewlines),
                        icon: icon,
                        palette: selectedPalette,
                        cardKind: selectedCardKind,
                        imageData: imageData,
                        scheduleSummary: WeekdayMask.summary(for: targetWeekdayMask),
                        reminderSummary: reminderEnabled ? String(format: "%02d:%02d 提醒", reminderHour, reminderMinute) : nil
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    .listRowBackground(Color.clear)
                }

                Section("目标") {
                    TextField("目标名称", text: $name)

                    Button {
                        showingIconPicker = true
                    } label: {
                        HStack {
                            Text("图标")
                            Spacer()
                            HabitIconGlyph(icon: icon, size: icon.isEmojiIcon ? 26 : 22)
                                .foregroundStyle(selectedPalette.accent)
                                .frame(width: 34, height: 34)
                                .background(selectedPalette.accent.opacity(0.14), in: Circle())
                        }
                    }
                }

                Section("样式") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("主题色")
                            Spacer()
                            Text(selectedPalette.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selectedPalette.accent)
                        }
                        PaletteSwatchRow(selectedColorName: $colorName)
                    }
                    .padding(.vertical, 4)

                    Picker("卡片", selection: $cardStyle) {
                        ForEach(HabitCardKind.allCases) { kind in
                            Text(kind.title).tag(kind.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    if isImageStyle {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(imageButtonTitle, systemImage: "photo")
                        }

                        if imageData != nil {
                            Button("移除图片", role: .destructive) {
                                imageData = nil
                            }
                        }
                    }
                }

                Section("打卡日期") {
                    WeekdayPresetRow(mask: $targetWeekdayMask, accent: selectedPalette.accent)
                    WeekdayToggleRow(mask: $targetWeekdayMask)
                }

                Section("提醒") {
                    Toggle("开启提醒", isOn: $reminderEnabled)

                    if reminderEnabled {
                        DatePicker(
                            "提醒时间",
                            selection: reminderDateBinding,
                            displayedComponents: .hourAndMinute
                        )
                        WeekdayPresetRow(mask: $reminderWeekdayMask, accent: selectedPalette.accent)
                        WeekdayToggleRow(mask: $reminderWeekdayMask)
                    }
                }
            }
            .navigationTitle(habit == nil ? "新建目标" : "编辑目标")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                loadInitialValues()
            }
            .onChange(of: photoItem) {
                Task {
                    if let data = try? await photoItem?.loadTransferable(type: Data.self) {
                        imageData = StickerImageOptimizer.optimizedData(from: data)
                    }
                    cardStyle = HabitCardKind.image.rawValue
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        .overlay {
            if showingIconPicker {
                IconPickerSheet(
                    selection: $icon,
                    closeAction: { showingIconPicker = false }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
        }
        #else
        .sheet(isPresented: $showingIconPicker) {
            IconPickerSheet(selection: $icon)
        }
        #endif
    }

    private var reminderDateBinding: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? Date()
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderHour = components.hour ?? 20
            reminderMinute = components.minute ?? 0
        }
    }

    private func loadInitialValues() {
        guard let habit else { return }
        name = habit.name
        icon = habit.icon
        colorName = habit.colorName
        cardStyle = habit.cardStyle
        imageData = habit.imageData
        targetWeekdayMask = habit.targetWeekdayMask
        reminderEnabled = habit.reminderEnabled
        reminderHour = habit.reminderHour
        reminderMinute = habit.reminderMinute
        reminderWeekdayMask = habit.reminderWeekdayMask
    }

    private func save() {
        let target = habit ?? HabitEntity(name: name)
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.icon = icon
        target.colorName = colorName
        target.cardStyle = cardStyle
        target.imageData = imageData
        target.targetWeekdayMask = targetWeekdayMask
        target.reminderEnabled = reminderEnabled
        target.reminderHour = reminderHour
        target.reminderMinute = reminderMinute
        target.reminderWeekdayMask = reminderWeekdayMask

        if habit == nil {
            target.sortOrder = (habits.map(\.sortOrder).max() ?? -1) + 1
            modelContext.insert(target)
        }

        do {
            try modelContext.save()
        } catch {
            print("[HabitBloomModel] Failed to save habit editor changes: \(error.localizedDescription)")
            return
        }
        var snapshotHabits = habits
        if !snapshotHabits.contains(where: { $0.id == target.id }) {
            snapshotHabits.append(target)
        }
        WidgetSnapshotWriter.scheduleWrite(habits: snapshotHabits, backupDelayMilliseconds: 2_500)
        let reminderSnapshot = ReminderScheduleSnapshot(habit: target)
        Task { await ReminderScheduler.reschedule(for: reminderSnapshot) }
        dismiss()
    }
}

private struct WeekdayToggleRow: View {
    @Binding var mask: Int

    private let labels = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...7, id: \.self) { weekday in
                Button {
                    mask = WeekdayMask.set(weekday, enabled: !WeekdayMask.contains(weekday, in: mask), in: mask)
                    if mask == 0 { mask = WeekdayMask.all }
                } label: {
                    Text(labels[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(WeekdayMask.contains(weekday, in: mask) ? Color.accentColor.opacity(0.86) : Color.secondary.opacity(0.13))
                        .foregroundStyle(WeekdayMask.contains(weekday, in: mask) ? .white : .primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WeekdayPresetRow: View {
    @Binding var mask: Int
    let accent: Color

    private let presets: [(title: String, mask: Int)] = [
        ("每天", WeekdayMask.all),
        ("工作日", WeekdayMask.workdays),
        ("周末", WeekdayMask.weekends)
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.title) { preset in
                let isSelected = mask == preset.mask
                Button {
                    mask = preset.mask
                } label: {
                    Text(preset.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? accent.opacity(0.20) : Color.secondary.opacity(0.10))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(isSelected ? accent.opacity(0.75) : .clear, lineWidth: 1)
                        )
                        .foregroundStyle(isSelected ? accent : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct PaletteSwatchRow: View {
    @Binding var selectedColorName: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(HabitPalette.allCases) { palette in
                let isSelected = selectedColorName == palette.rawValue
                Button {
                    selectedColorName = palette.rawValue
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(palette.gradient)
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(isSelected ? 0.92 : 0.35), lineWidth: isSelected ? 2 : 1)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(palette.accent.opacity(isSelected ? 0.85 : 0), lineWidth: 2.5)
                                        .padding(-3)
                                )
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        Text(palette.title)
                            .font(.caption2.weight(isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("主题色 \(palette.title)\(isSelected ? "，已选中" : "")")
            }
        }
    }
}

private struct HabitEditorPreviewCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let name: String
    let icon: String
    let palette: HabitPalette
    let cardKind: HabitCardKind
    let imageData: Data?
    let scheduleSummary: String
    let reminderSummary: String?

    private var decodedImage: StickerDecodedImage? {
        guard cardKind == .image else { return nil }
        return StickerImageCache.shared.image(for: imageData, maxPixelSize: 960)
    }

    private var usesImageBackground: Bool {
        decodedImage != nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            previewBackground

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(usesImageBackground
                                  ? Color.black.opacity(reduceTransparency ? 0.56 : 0.32)
                                  : Color.adaptiveChipSurface(for: colorScheme, reduceTransparency: reduceTransparency))
                            .overlay(
                                Circle().strokeBorder(
                                    usesImageBackground
                                        ? Color.white.opacity(0.35)
                                        : Color.adaptiveCardBorder(for: colorScheme, reduceTransparency: reduceTransparency),
                                    lineWidth: 1
                                )
                            )
                            .frame(width: 48, height: 48)

                        HabitIconGlyph(icon: icon, size: icon.isEmojiIcon ? 24 : 20)
                            .foregroundStyle(usesImageBackground ? .white : palette.accent)
                    }

                    Spacer(minLength: 10)

                    HStack(spacing: 6) {
                        Text(scheduleSummary)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(usesImageBackground
                                          ? Color.black.opacity(0.38)
                                          : Color.adaptiveChipSurface(for: colorScheme, reduceTransparency: reduceTransparency))
                            )
                            .foregroundStyle(usesImageBackground ? .white : .secondary)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(usesImageBackground ? .white : palette.accent)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(usesImageBackground ? .white : .primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("连续 7 天 · 累计 21 天")
                        if let reminderSummary {
                            Text("· \(reminderSummary)")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(usesImageBackground ? .white.opacity(0.84) : .secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(usesImageBackground ? Color.white.opacity(0.24) : Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10))
                        Capsule(style: .continuous)
                            .fill(usesImageBackground ? Color.white.opacity(0.92) : palette.accent.opacity(0.88))
                            .frame(width: max(20, proxy.size.width * 0.72))
                    }
                }
                .frame(height: 7)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 162)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    usesImageBackground
                        ? Color.white.opacity(0.32)
                        : Color.adaptiveCardBorder(for: colorScheme, reduceTransparency: reduceTransparency),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var previewBackground: some View {
        switch cardKind {
        case .soft:
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.appBackgroundSecondary)
                    .overlay(palette.accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
            } else {
                LinearGradient(
                    colors: [
                        palette.accent.opacity(colorScheme == .dark ? 0.28 : 0.20),
                        palette.accent.opacity(colorScheme == .dark ? 0.12 : 0.08),
                        Color.appBackgroundSecondary.opacity(0.95)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        case .glass:
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.appBackgroundSecondary)
                    .overlay(palette.accent.opacity(colorScheme == .dark ? 0.16 : 0.10))
            } else {
                Rectangle()
                    .fill(.thinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.24),
                                palette.accent.opacity(colorScheme == .dark ? 0.22 : 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        case .minimal:
            Color.appBackgroundSecondary
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(palette.accent.opacity(reduceTransparency ? 0.72 : 0.54))
                        .frame(width: 6)
                }
        case .image:
            if let decodedImage {
                GeometryReader { proxy in
                    Image(stickerImage: decodedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .saturation(0.86)
                        .overlay(
                            LinearGradient(
                                colors: [
                                    .black.opacity(reduceTransparency ? 0.56 : 0.36),
                                    .black.opacity(reduceTransparency ? 0.34 : 0.18),
                                    .black.opacity(reduceTransparency ? 0.64 : 0.46)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            } else {
                Color.appBackgroundSecondary
                    .overlay(palette.gradient.opacity(0.18))
            }
        }
    }
}
