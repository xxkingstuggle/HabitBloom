import SwiftUI

struct HabitIconGlyph: View {
    let icon: String
    var size: CGFloat
    var weight: Font.Weight = .bold

    var body: some View {
        if icon.isEmojiIcon {
            Text(icon)
                .font(.system(size: size))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Image(systemName: icon)
                .font(.system(size: size, weight: weight))
        }
    }
}

extension String {
    var isEmojiIcon: Bool {
        count <= 4 && unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }
}
