import SwiftUI

struct IconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var mode = IconPickerMode.emoji

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    private let emojis = [
        "📚", "💧", "🧘", "🏃", "💪", "🥗", "☕️", "🌙", "☀️", "🔥", "⭐️", "❤️",
        "📝", "💰", "🎧", "🎨", "🧹", "🪴", "🍎", "🚶", "🛌", "🧠", "🎯", "🏆",
        "🦷", "🧴", "💊", "🧘‍♂️", "🚴", "🏋️", "📖", "🧩", "🕯️", "🌿", "🍵", "🧊",
        "🍋", "🍊", "🍓", "🥑", "🥦", "🥛", "🫖", "🍽️", "🧃", "🧁", "🍫", "🥾",
        "⚽️", "🏀", "🎾", "🏊", "🧗", "⛳️", "🎹", "🎸", "📷", "🎬", "🧵", "🪡",
        "🧺", "🛁", "🪥", "🧼", "🪒", "💤", "🛏️", "⏰", "📅", "✅", "🔔", "🧭",
        "💻", "📱", "⌚️", "🧾", "📊", "📈", "📦", "🏠", "🚗", "✈️", "🗺️", "🧳",
        "🐾", "🌈", "🌧️", "❄️", "🌊", "⛰️", "🌱", "🌸", "🌻", "🪷", "✨", "💎"
    ]

    private let symbols = [
        "flame.fill", "book.closed.fill", "drop.fill", "figure.flexibility", "moon.fill", "sun.max.fill",
        "bolt.fill", "heart.fill", "leaf.fill", "star.fill", "checkmark.circle.fill", "target",
        "figure.run", "figure.walk", "dumbbell.fill", "bicycle", "brain.head.profile", "pencil.and.list.clipboard",
        "creditcard.fill", "calendar", "alarm.fill", "paintpalette.fill", "music.note", "headphones",
        "cup.and.saucer.fill", "fork.knife", "bed.double.fill", "sparkles", "timer", "chart.bar.fill"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("图标类型", selection: $mode) {
                    ForEach(IconPickerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(currentIcons, id: \.self) { icon in
                            Button {
                                selection = icon
                                dismiss()
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(selection == icon ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10))
                                    HabitIconGlyph(icon: icon, size: icon.isEmojiIcon ? 30 : 24)
                                        .foregroundStyle(selection == icon ? Color.accentColor : .primary)
                                }
                                .frame(height: 54)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(icon)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("选择图标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var currentIcons: [String] {
        switch mode {
        case .emoji: emojis
        case .symbol: symbols
        }
    }
}

private enum IconPickerMode: String, CaseIterable, Identifiable {
    case emoji
    case symbol

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emoji: "表情"
        case .symbol: "系统图标"
        }
    }
}
