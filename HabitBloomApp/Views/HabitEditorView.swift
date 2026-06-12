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

        NavigationStack {
            Form {
                Section("目标") {
                    TextField("目标名称", text: $name)

                    Button {
                        showingIconPicker = true
                    } label: {
                        HStack {
                            Text("图标")
                            Spacer()
                            HabitIconGlyph(icon: icon, size: icon.isEmojiIcon ? 26 : 22)
                                .frame(width: 34, height: 34)
                                .background(Color.secondary.opacity(0.12), in: Circle())
                        }
                    }
                }

                Section("样式") {
                    Picker("颜色", selection: $colorName) {
                        ForEach(HabitPalette.allCases) { palette in
                            Text(palette.title).tag(palette.rawValue)
                        }
                    }

                    Picker("卡片", selection: $cardStyle) {
                        ForEach(HabitCardKind.allCases) { kind in
                            Text(kind.title).tag(kind.rawValue)
                        }
                    }

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
            .sheet(isPresented: $showingIconPicker) {
                IconPickerSheet(selection: $icon)
            }
        }
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
            modelContext.insert(target)
        }

        try? modelContext.save()
        var snapshotHabits = habits
        if !snapshotHabits.contains(where: { $0.id == target.id }) {
            snapshotHabits.append(target)
        }
        WidgetSnapshotWriter.write(habits: snapshotHabits)
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
