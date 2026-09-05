import AppKit
import SwiftUI

/// Hun's appearance follows macOS. The dark values are the original palette;
/// light mode adds a warm paper canvas with crisp white working surfaces.
nonisolated enum AppTheme {
    static let appBackground = color(light: 0xF7F7F2, dark: 0x030303)
    static let sidebar = color(light: 0xF2F2EC, dark: 0x060606)
    static let menuBackground = color(light: 0xF7F7F2, dark: 0x060606)
    static let elevated = color(
        light: 0xFFFFFF,
        darkRed: 0.105,
        darkGreen: 0.105,
        darkBlue: 0.110
    )
    static let dialogBackground = color(light: 0xF7F7F2, dark: 0x080809)
    static let dialogRaised = color(light: 0xFFFFFF, dark: 0x0D0D0F)

    static let divider = color(
        light: 0x181816,
        dark: 0xFFFFFF,
        lightOpacity: 0.07,
        darkOpacity: 0.06
    )
    static let dividerStrong = color(
        light: 0x181816,
        dark: 0xFFFFFF,
        lightOpacity: 0.12,
        darkOpacity: 0.10
    )

    static let hover = color(
        light: 0x181816,
        dark: 0xFFFFFF,
        lightOpacity: 0.035,
        darkOpacity: 0.035
    )
    static let selection = color(
        light: 0x181816,
        dark: 0xFFFFFF,
        lightOpacity: 0.06,
        darkOpacity: 0.06
    )
    static let tabActive = color(
        light: 0xFFFFFF,
        dark: 0xFFFFFF,
        darkOpacity: 0.055
    )
    static let chipFill = color(
        light: 0xFFFFFF,
        dark: 0xFFFFFF,
        darkOpacity: 0.05
    )
    static let buttonFill = color(
        light: 0xFFFFFF,
        dark: 0xFFFFFF,
        darkOpacity: 0.04
    )
    static let searchField = color(
        light: 0xFFFFFF,
        dark: 0xFFFFFF,
        darkOpacity: 0.035
    )
    static let modeSelectorBackground = color(
        light: 0xF2F2EC,
        dark: 0xFFFFFF,
        darkOpacity: 0.035
    )
    static let modeSelectorActive = color(
        light: 0xFFFFFF,
        dark: 0xFFFFFF,
        darkOpacity: 0.055
    )
    static let floatingBorder = color(
        light: 0x181816,
        dark: 0xFFFFFF,
        lightOpacity: 0.09,
        darkOpacity: 0.12
    )
    static let floatingBorderHover = color(
        light: 0x181816,
        dark: 0xFFFFFF,
        lightOpacity: 0.14,
        darkOpacity: 0.22
    )
    static let floatingShadow = color(
        light: 0x181816,
        dark: 0x000000,
        lightOpacity: 0.10,
        darkOpacity: 0.35
    )

    static let textPrimary = color(
        light: 0x232321,
        dark: 0xFFFFFF,
        darkOpacity: 0.92
    )
    static let textSecondary = color(
        light: 0x62625D,
        dark: 0xFFFFFF,
        darkOpacity: 0.55
    )
    static let textTertiary = color(
        light: 0x8B8B84,
        dark: 0xFFFFFF,
        darkOpacity: 0.36
    )

    /// Neutral used for log body text — readable but softer than primary text.
    static let logText = color(
        light: 0x4D4D49,
        dark: 0xFFFFFF,
        darkOpacity: 0.66
    )
    /// Dimmer still, for log timestamps.
    static let logTimestamp = color(
        light: 0x92928B,
        dark: 0xFFFFFF,
        darkOpacity: 0.26
    )
    static let selectedText = color(
        light: 0x232321,
        dark: 0xFFFFFF,
        darkOpacity: 0.96
    )

    // Purple remains Hun's only action/brand accent in both appearances.
    static let accent = color(
        light: 0x5E6AD2,
        darkRed: 0.369,
        darkGreen: 0.416,
        darkBlue: 0.824
    )
    static let success = color(
        light: 0x27833F,
        darkRed: 0.34,
        darkGreen: 0.78,
        darkBlue: 0.45
    )
    static let warning = color(
        light: 0xA76418,
        darkRed: 0.95,
        darkGreen: 0.66,
        darkBlue: 0.34
    )
    static let danger = color(
        light: 0xB84040,
        darkRed: 0.93,
        darkGreen: 0.45,
        darkBlue: 0.45
    )

    static let brand = textPrimary

    // The commit control was intentionally neutral in the original dark UI.
    // In light mode it joins Hun's purple primary-action language.
    static let commitPrimaryText = color(
        light: 0xFFFFFF,
        dark: 0xFFFFFF,
        darkOpacity: 0.92
    )
    static let commitPrimaryFill = color(
        light: 0x5E6AD2,
        dark: 0xFFFFFF,
        lightOpacity: 0.92,
        darkOpacity: 0.075
    )
    static let commitPrimaryFillHover = color(
        light: 0x5E6AD2,
        dark: 0xFFFFFF,
        darkOpacity: 0.10
    )
    static let commitPrimaryFillPressed = color(
        light: 0x5E6AD2,
        dark: 0xFFFFFF,
        lightOpacity: 0.78,
        darkOpacity: 0.12
    )
    static let commitPrimaryBorder = color(
        light: 0xFFFFFF,
        dark: 0xFFFFFF,
        lightOpacity: 0.10,
        darkOpacity: 0.10
    )
    static let updateActionText = color(light: 0xFFFFFF, dark: 0x030303)
    static let updateActionFill = color(
        light: 0x5E6AD2,
        dark: 0xFFFFFF,
        lightOpacity: 0.92,
        darkOpacity: 0.8096
    )
    static let updateActionFillHover = color(
        light: 0x5E6AD2,
        dark: 0xFFFFFF,
        darkOpacity: 0.92
    )

    static func nativeColor(
        light: UInt32,
        dark: UInt32,
        lightOpacity: CGFloat = 1,
        darkOpacity: CGFloat = 1
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let usesDarkPalette = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return srgbColor(
                hex: usesDarkPalette ? dark : light,
                opacity: usesDarkPalette ? darkOpacity : lightOpacity
            )
        }
    }

    static func nativeColor(
        light: UInt32,
        darkRed: CGFloat,
        darkGreen: CGFloat,
        darkBlue: CGFloat,
        lightOpacity: CGFloat = 1,
        darkOpacity: CGFloat = 1
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let usesDarkPalette = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if usesDarkPalette {
                return NSColor(
                    srgbRed: darkRed,
                    green: darkGreen,
                    blue: darkBlue,
                    alpha: darkOpacity
                )
            }
            return srgbColor(hex: light, opacity: lightOpacity)
        }
    }

    private static func color(
        light: UInt32,
        dark: UInt32,
        lightOpacity: CGFloat = 1,
        darkOpacity: CGFloat = 1
    ) -> Color {
        Color(
            nsColor: nativeColor(
                light: light,
                dark: dark,
                lightOpacity: lightOpacity,
                darkOpacity: darkOpacity
            )
        )
    }

    private static func color(
        light: UInt32,
        darkRed: CGFloat,
        darkGreen: CGFloat,
        darkBlue: CGFloat,
        lightOpacity: CGFloat = 1,
        darkOpacity: CGFloat = 1
    ) -> Color {
        Color(
            nsColor: nativeColor(
                light: light,
                darkRed: darkRed,
                darkGreen: darkGreen,
                darkBlue: darkBlue,
                lightOpacity: lightOpacity,
                darkOpacity: darkOpacity
            )
        )
    }

    private static func srgbColor(hex: UInt32, opacity: CGFloat) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: opacity
        )
    }
}
