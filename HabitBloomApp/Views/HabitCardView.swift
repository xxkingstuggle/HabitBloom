import SwiftUI

struct HabitCardView: View {
    let habit: HabitEntity
    var feedbackLevel = 0
    var toggle: () -> Void
    @State private var bursts: [CheckInBurst] = []
    @State private var highlightSweep = false
    @State private var iconScale = 1.0
    @State private var cardScale = 1.0
    @State private var activation = 0.0
    @State private var edgeGlow = false
    @State private var progressBoost = 0.0

    private var palette: HabitPalette {
        HabitPalette(rawValue: habit.colorName) ?? .coral
    }

    private var cardKind: HabitCardKind {
        HabitCardKind(rawValue: habit.cardStyle) ?? .soft
    }

    private var stats: HabitStatsViewModel {
        HabitStatsService.stats(for: habit)
    }

    private var isCompletedToday: Bool {
        HabitStatsService.isCompletedToday(habit)
    }

    private var usesImageBackground: Bool {
        cardKind == .image && platformImage(from: habit.imageData) != nil
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                background
                    .overlay(
                        RadialGradient(
                            colors: [
                                (usesImageBackground ? Color.white : palette.accent).opacity(0.30 * activation),
                                (usesImageBackground ? Color.white : palette.accent).opacity(0.12 * activation),
                                .clear
                            ],
                            center: .topTrailing,
                            startRadius: 8,
                            endRadius: proxy.size.width * 0.95
                        )
                    )
                    .brightness(activation * (usesImageBackground ? 0.08 : 0.045))

                if highlightSweep {
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(usesImageBackground ? 0.28 : 0.42), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .rotationEffect(.degrees(-10))
                    .offset(x: proxy.size.width * 0.38)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                if edgeGlow {
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

                ForEach(bursts) { burst in
                    CheckInBurstView(burst: burst, tint: usesImageBackground ? .white : palette.accent)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        iconView
                            .scaleEffect(iconScale)

                        Spacer(minLength: 12)

                        Button {
                            triggerFeedback(in: proxy.size)
                            toggle()
                        } label: {
                            Image(systemName: isCompletedToday ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 27, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 50, height: 42)
                                .background((usesImageBackground ? Color.black.opacity(0.30) : Color.white.opacity(0.30)), in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isCompletedToday ? (usesImageBackground ? .white : palette.accent) : (usesImageBackground ? .white.opacity(0.90) : .primary))
                        .accessibilityLabel(isCompletedToday ? "取消今日打卡" : "完成今日打卡")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(habit.name)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                        Text("连续 \(stats.currentStreak) 天 · 累计 \(stats.totalCompletedDays) 天")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(usesImageBackground ? .white.opacity(0.82) : .secondary)
                    }

                    CardProgressBar(value: min(1, stats.monthCompletionRate + progressBoost), tint: usesImageBackground ? .white : palette.accent, isOnImage: usesImageBackground)
                }
                .padding(16)
            }
        }
        .scaleEffect(cardScale)
        .aspectRatio(2.14, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.26), lineWidth: 1)
        )
        .shadow(color: palette.accent.opacity(0.11), radius: 18, y: 9)
    }

    private func triggerFeedback(in size: CGSize) {
        let completing = !isCompletedToday
        let origin = CGPoint(x: max(42, size.width - 42), y: 38)
        let intensity = completing ? 1.0 + min(Double(feedbackLevel), 8) * 0.075 : 0.62
        let burst = CheckInBurst(origin: origin, strength: intensity)

        CheckInFeedbackService.shared.play(completing: completing, level: feedbackLevel)

        withAnimation(.spring(response: 0.20, dampingFraction: 0.70)) {
            cardScale = completing ? 0.985 : 0.992
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.54).delay(0.05)) {
            cardScale = 1.0
            iconScale = completing ? 1.13 : 0.94
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
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.accent.opacity(0.20),
                            palette.accent.opacity(0.08),
                            Color(.systemBackground).opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .glass:
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), palette.accent.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .minimal:
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(palette.accent.opacity(0.16), alignment: .leading)
        case .image:
            if let image = platformImage(from: habit.imageData) {
                GeometryReader { proxy in
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .saturation(0.86)
                        .overlay(.black.opacity(0.20))
                        .overlay(
                            LinearGradient(
                                colors: [
                                    .black.opacity(0.36),
                                    .black.opacity(0.14),
                                    .black.opacity(0.42)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(palette.gradient.opacity(0.18))
                    .background(.regularMaterial)
            }
        }
    }

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.30))
                .overlay(Circle().stroke(Color.white.opacity(0.32), lineWidth: 1))
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

private func platformImage(from data: Data?) -> PlatformImage? {
    guard let data else { return nil }
    return NSImage(data: data)
}

private extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}
#else
import UIKit
typealias PlatformImage = UIImage

private func platformImage(from data: Data?) -> PlatformImage? {
    guard let data else { return nil }
    return UIImage(data: data)
}

private extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}
#endif
