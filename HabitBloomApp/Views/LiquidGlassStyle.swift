import SwiftUI

struct LiquidGlassPanel: ViewModifier {
    var tint: Color = .white
    var isStrong: Bool = false
    var cornerRadius: CGFloat = 20

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.appBackgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(Color.adaptiveCardBorder(for: colorScheme, reduceTransparency: true), lineWidth: 1.2)
                        )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isStrong ? .regularMaterial : .ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.24),
                                            tint.opacity(colorScheme == .dark ? 0.10 : 0.07),
                                            Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.22 : 0.56),
                                            Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.09),
                                            Color.white.opacity(colorScheme == .dark ? 0.10 : 0.22)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? (isStrong ? 0.28 : 0.18) : (isStrong ? 0.09 : 0.05)),
                radius: isStrong ? 20 : 12,
                y: isStrong ? 10 : 6
            )
            .liquidBackgroundExtension()
    }
}

extension View {
    func liquidGlassPanel(tint: Color = .white, isStrong: Bool = false, cornerRadius: CGFloat = 20) -> some View {
        modifier(LiquidGlassPanel(tint: tint, isStrong: isStrong, cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func liquidGlassButton() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func liquidGlassProminentButton() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func liquidBackgroundExtension() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
    }
}

struct GlassSection<Content: View>: View {
    let title: String
    var tint: Color = .white
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                content
            }
            .padding(14)
            .liquidGlassPanel(tint: tint)
        }
    }
}

struct GlassInfoRow: View {
    let title: String
    let value: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }

            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}
