import SwiftUI

extension Color {
    static var appBackgroundPrimary: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    static var appBackgroundSecondary: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var appSurfaceElevated: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .tertiarySystemBackground)
        #endif
    }

    static func adaptiveChipSurface(for colorScheme: ColorScheme, reduceTransparency: Bool) -> Color {
        if reduceTransparency {
            return colorScheme == .dark ? Color.appSurfaceElevated : Color.appBackgroundPrimary
        }
        return colorScheme == .dark ? Color.white.opacity(0.11) : Color.white.opacity(0.74)
    }

    static func adaptiveCardBorder(for colorScheme: ColorScheme, reduceTransparency: Bool) -> Color {
        if reduceTransparency {
            return colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.16)
        }
        return colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.55)
    }
}
