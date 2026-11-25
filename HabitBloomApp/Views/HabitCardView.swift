import SwiftUI

struct HabitCardView: View {
    let habit: HabitEntity
    let stats: HabitStatsViewModel
    let isCompletedToday: Bool
    var feedbackLevel = 0
    var toggle: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var bursts: [CheckInBurst] = []
    @State private var highlightSweep = false
    @State private var iconScale = 1.0
    @State private var cardScale = 1.0
    @State private var activation = 0.0
    @State private var edgeGlow = false
    @State private var progressBoost = 0.0
    @State private var isHovering = false

    private var palette: HabitPalette {
        HabitPalette(rawValue: habit.colorName) ?? .coral
    }

    private var cardKind: HabitCardKind {
        HabitCardKind(rawValue: habit.cardStyle) ?? .soft
    }

    private var cachedStickerImage: PlatformImage? {
        guard cardKind == .image else { return nil }
        return StickerImageCache.shared.image(for: habit.imageData, maxPixelSize: 960)
    }

    private var usesImageBackground: Bool {
        cachedStickerImage != nil
    }

    private var actionCapsuleFill: Color {
        if usesImageBackground {
            return reduceTransparency ? Color.black.opacity(0.62) : Color.black.opacity(0.36)
        }
        if reduceTransparency {
            return colorScheme == .dark ? Color.appSurfaceElevated : Color.appBackgroundPrimary
        }
        return colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.68)
    }

    private var actionCapsuleStroke: Color {
        if usesImageBackground {
            return Color.white.opacity(reduceTransparency ? 0.50 : 0.28)
        }
        return isCompletedToday
            ? palette.accent.opacity(reduceTransparency ? 0.72 : 0.42)
            : Color.adaptiveCardBorder(for: colorScheme, reduceTransparency: reduceTransparency)
    }

    private var iconBadgeFill: Color {
        if usesImageBackground {
            return reduceTransparency ? Color.black.opacity(0.58) : Color.black.opacity(0.32)
        }
        if reduceTransparency {
            return colorScheme == .dark ? Color.appSurfaceElevated : Color.appBackgroundPrimary
        }
        return colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.72)
    }

    private var cardBorderColor: Color {
        if isHovering {
            return (usesImageBackground ? Color.white : palette.accent).opacity(reduceTransparency ? 0.85 : 0.58)
        }
        if usesImageBackground {
            return Color.white.opacity(reduceTransparency ? 0.44 : 0.26)
        }
        if isCompletedToday {
            return palette.accent.opacity(reduceTransparency ? 0.65 : 0.36)
        }
        return Color.adaptiveCardBorder(for: colorScheme, reduceTransparency: reduceTransparency)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                background
                    .overlay(
                        RadialGradient(
                            colors: [
                                (usesImageBackground ? Color.white : palette.accent).opacity(reduceMotion ? 0 : 0.30 * activation),
                                (usesImageBackground ? Color.white : palette.accent).opacity(reduceMotion ? 0 : 0.12 * activation),
                                .clear
                            ],
                            center: .topTrailing,
                            startRadius: 8,
                            endRadius: proxy.size.width * 0.95
                        )
                    )
                    .brightness(reduceMotion ? 0 : activation * (usesImageBackground ? 0.08 : 0.045))

                if highlightSweep && !reduceMotion {
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(usesImageBackground ? 0.28 : 0.42), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .rotationEffect(.degrees(-10))
                    .offset(x: proxy.size.width * 0.38)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                if edgeGlow && !reduceMotion {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .trim(from: 0, to: 0.92)
                        .stroke(
                            AngularGradient(
                                colors: [.clear, usesImageBackground ? .white.opacity(0.76) : palette.accent.opacity(0.78), .clear],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                        )
                        .padding(1)
                        .transition(.opacity)
                }

                if !reduceMotion {
                    ForEach(bursts) { burst in
                        CheckInBurstView(burst: burst, tint: usesImageBackground ? .white : palette.accent)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        iconView
                            .scaleEffect(reduceMotion ? 1.0 : iconScale)

                        Spacer(minLength: 12)

                        Button {
                            triggerFeedback(in: proxy.size)
                            toggle()
                        } label: {
                            Image(systemName: isCompletedToday ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 27, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 50, height: 42)
                                .background(actionCapsuleFill, in: Capsule(style: .continuous))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(actionCapsuleStroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isCompletedToday ? (usesImageBackground ? .white : palette.accent) : (usesImageBackground ? .white.opacity(0.90) : .primary))
                        .accessibilityLabel(isCompletedToday ? "取消今日打卡" : "完成今日打卡")
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(habit.name)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(usesImageBackground ? .white : .primary)
                                .lineLimit(2)

                            Spacer(minLength: 4)

                            if isCompletedToday {
                                Text("已完成")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .foregroundStyle(usesImageBackground ? .white : palette.accent)
                                    .background(actionCapsuleFill, in: Capsule(style: .continuous))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(actionCapsuleStroke, lineWidth: 0.8)
                                    )
                            }
                        }

                        Text("连续 \(stats.currentStreak) 天 · 累计 \(stats.totalCompletedDays) 天")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(usesImageBackground ? .white.opacity(0.88) : .secondary)
                            .monospacedDigit()
                    }

                    CardProgressBar(value: min(1, stats.monthCompletionRate + progressBoost), tint: usesImageBackground ? .white : palette.accent, isOnImage: usesImageBackground)
                }
                .padding(16)
            }
        }
        .scaleEffect(reduceMotion ? 1.0 : (cardScale * (isHovering ? 1.008 : 1.0)))
        .aspectRatio(2.14, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(cardBorderColor, lineWidth: (isHovering || reduceTransparency) ? 1.5 : 1)
        )
        .shadow(
            color: (usesImageBackground ? Color.black : palette.accent).opacity(isHovering ? 0.18 : (colorScheme == .dark ? 0.22 : 0.11)),
            radius: isHovering ? 20 : 14,
            y: isHovering ? 10 : 7
        )
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    isHovering = hovering
                }
            }
        }
    }

    private func triggerFeedback(in size: CGSize) {
        let completing = !isCompletedToday
        CheckInFeedbackService.shared.play(completing: completing, level: feedbackLevel)

        guard !reduceMotion else { return }

        let origin = CGPoint(x: max(42, size.width - 42), y: 38)
        let intensity = completing ? 1.0 + min(Double(feedbackLevel), 8) * 0.075 : 0.62
        let burst = CheckInBurst(origin: origin, strength: intensity)

        withAnimation(.spring(response: 0.20, dampingFraction: 0.70)) {
            cardScale = completing ? 0.985 : 0.992
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.54).delay(0.05)) {
            cardScale = 1.0
            iconScale = completing ? 1.13 : 0.94
            if bursts.count >= 3 {
                bursts.removeFirst(bursts.count - 2)
            }
            bursts.append(burst)
        }
        withAnimation(.easeOut(duration: 0.32)) {
            activation = completing ? min(1, 0.72 + Double(feedbackLevel) * 0.035) : 0.24
            progressBoost = completing ? min(0.16, 0.06 + Double(feedbackLevel) * 0.01) : 0
            highlightSweep = completing
            edgeGlow = completing
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                iconScale = 1.0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            withAnimation(.easeOut(duration: 0.22)) {
                highlightSweep = false
                edgeGlow = false
            }
            withAnimation(.easeOut(duration: 0.42)) {
                activation = 0
                progressBoost = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.82) {
            bursts.removeAll { $0.id == burst.id }
        }
    }

    @ViewBuilder
    private var background: some View {
        switch cardKind {
        case .soft:
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.appBackgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(palette.accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
                    )
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.accent.opacity(colorScheme == .dark ? 0.28 : 0.20),
                                palette.accent.opacity(colorScheme == .dark ? 0.12 : 0.08),
                                Color.appBackgroundSecondary.opacity(colorScheme == .dark ? 0.96 : 0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        case .glass:
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.appBackgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(palette.accent.opacity(colorScheme == .dark ? 0.16 : 0.10))
                    )
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.26),
                                palette.accent.opacity(colorScheme == .dark ? 0.22 : 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        case .minimal:
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.appBackgroundSecondary)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(palette.accent.opacity(reduceTransparency ? 0.72 : 0.52))
                        .frame(width: 6)
                }
        case .image:
            if let image = cachedStickerImage {
                GeometryReader { proxy in
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .saturation(0.86)
                        .overlay(.black.opacity(reduceTransparency ? 0.40 : 0.22))
                        .overlay(
                            LinearGradient(
                                colors: [
                                    .black.opacity(reduceTransparency ? 0.56 : 0.36),
                                    .black.opacity(reduceTransparency ? 0.34 : 0.16),
                                    .black.opacity(reduceTransparency ? 0.66 : 0.46)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.appBackgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(palette.gradient.opacity(reduceTransparency ? 0.16 : 0.22))
                    )
            }
        }
    }

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(iconBadgeFill)
                .overlay(
                    Circle().stroke(
                        usesImageBackground
                            ? Color.white.opacity(reduceTransparency ? 0.50 : 0.32)
                            : Color.adaptiveCardBorder(for: colorScheme, reduceTransparency: reduceTransparency),
                        lineWidth: 1
                    )
                )
                .frame(width: 54, height: 54)
            HabitIconGlyph(icon: habit.icon, size: habit.icon.isEmojiIcon ? 27 : 23)
                .foregroundStyle(usesImageBackground ? .white : palette.accent)
        }
    }
}

private struct CheckInBurst: Identifiable {
    let id = UUID()
    let origin: CGPoint
    let strength: Double
}

private struct CheckInBurstView: View {
    let burst: CheckInBurst
    let tint: Color
    @State private var progress = 0.0

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(tint.opacity(max(0, 0.42 - progress * 0.36 - Double(index) * 0.07)), lineWidth: max(1, 3.6 - Double(index)))
                    .frame(width: ringSize(index), height: ringSize(index))
                    .scaleEffect(0.2 + progress * burst.strength)
                    .opacity(1 - progress)
            }

            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(tint.opacity(0.72 - progress * 0.58))
                    .frame(width: particleSize(index), height: particleSize(index))
                    .offset(particleOffset(index))
                    .scaleEffect(1 - progress * 0.35)
            }
        }
        .position(burst.origin)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.76)) {
                progress = 1
            }
        }
    }

    private func ringSize(_ index: Int) -> CGFloat {
        CGFloat(58 + index * 32)
    }

    private func particleOffset(_ index: Int) -> CGSize {
        let angle = Double(index) / 8.0 * 2.0 * Double.pi
        let radius = (32.0 + Double(index % 3) * 10.0) * progress * burst.strength
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }

    private func particleSize(_ index: Int) -> CGFloat {
        CGFloat(4 + (index % 3))
    }
}

private struct CardProgressBar: View {
    let value: Double
    let tint: Color
    let isOnImage: Bool

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(value, 0), 1)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(isOnImage ? Color.white.opacity(0.24) : Color.primary.opacity(0.10))
                Capsule(style: .continuous)
                    .fill(tint.opacity(isOnImage ? 0.92 : 0.86))
                    .frame(width: max(8, proxy.size.width * clamped))
            }
        }
        .frame(height: 7)
        .accessibilityLabel("本月完成率")
    }
}

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage

private extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}
#else
import UIKit
typealias PlatformImage = UIImage

private extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}
#endif
