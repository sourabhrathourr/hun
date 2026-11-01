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
    // Fields and selector tracks are a faint ink tint in light mode, as they're
    // a faint white tint in dark: they show on every surface they sit on (the
    // sidebar, the window, a card) and the white active segment stands out.
    static let searchField = color(
        light: 0x181816,
        dark: 0xFFFFFF,
        lightOpacity: 0.045,
        darkOpacity: 0.035
    )
    static let modeSelectorBackground = color(
        light: 0x181816,
        dark: 0xFFFFFF,
        lightOpacity: 0.055,
        darkOpacity: 0.035
    )
    /// Selected rows and cards share the search field's fill.
    static let selectedFill = modeSelectorBackground
    /// Hover stays a step lighter than selection so the two never look alike.
    static let rowHover = hover.opacity(0.55)
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

    // Terracotta is Hun's one action/brand accent: bright in light mode, a
    // deeper rust in dark mode, where a bright fill glares on near-black.
    static let accent = color(light: 0xC24A1F, dark: 0xA84B2A)
    /// A primary button: solid terracotta with white text in light mode; in
    /// dark mode a faint rust wash with lifted rust text and edge.
    static let primaryFill = color(light: 0xC24A1F, dark: 0xA84B2A, darkOpacity: 0.2)
    static let primaryText = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? lifted(0xA84B2A, by: 0.35) : .white
    })
    static let primaryBorder = color(light: 0xFFFFFF, dark: 0xA84B2A, lightOpacity: 0.1, darkOpacity: 0.4)
    /// The accent as text or an icon: lifted in dark mode so rust reads on near-black.
    static let accentText = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? lifted(0xA84B2A, by: 0.25) : srgbColor(hex: 0xC24A1F, opacity: 1)
    })
    /// The newest log line's wash: the accent in light mode, a neutral band
    /// in dark mode (a rust tint turns brown on near-black).
    static let liveLogRow = NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.06)
            : srgbColor(hex: 0xC24A1F, opacity: 0.13)
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// A colour mixed toward white.
    private static func lifted(_ hex: UInt32, by amount: CGFloat) -> NSColor {
        let c = srgbColor(hex: hex, opacity: 1)
        return NSColor(
            srgbRed: c.redComponent + (1 - c.redComponent) * amount,
            green: c.greenComponent + (1 - c.greenComponent) * amount,
            blue: c.blueComponent + (1 - c.blueComponent) * amount,
            alpha: 1
        )
    }
    static let success = color(
        light: 0x27833F,
        darkRed: 0.34,
        darkGreen: 0.78,
        darkBlue: 0.45
    )
    /// The sidebar's running marker: the success green in light mode, a
    /// deeper, quieter green in dark mode (as on the menu bar's switches).
    static let liveMarker = color(light: 0x27833F, dark: 0x2A8C50)
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
    // In light mode it joins Hun's terracotta primary-action language.
    static let commitPrimaryText = color(
        light: 0xFFFFFF,
        dark: 0xFFFFFF,
        darkOpacity: 0.92
    )
    static let commitPrimaryFill = color(
        light: 0xC24A1F,
        dark: 0xFFFFFF,
        lightOpacity: 0.92,
        darkOpacity: 0.075
    )
    static let commitPrimaryFillHover = color(
        light: 0xC24A1F,
        dark: 0xFFFFFF,
        darkOpacity: 0.10
    )
    static let commitPrimaryFillPressed = color(
        light: 0xC24A1F,
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
    // White on green in dark mode; near-black on green in light mode, where
    // a white button would disappear.
    static let updateActionFill = color(
        light: 0x1A1A18,
        dark: 0xFFFFFF,
        lightOpacity: 0.9,
        darkOpacity: 0.8096
    )
    static let updateActionFillHover = color(
        light: 0x1A1A18,
        dark: 0xFFFFFF,
        lightOpacity: 1,
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
                hex: usesDarkPalette ? dark : HunPalette.light(light),
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
            return srgbColor(hex: HunPalette.light(light), opacity: lightOpacity)
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

/// Experimental layout, toggled in Settings: the main pane (header, services
/// and logs) is one rounded card inset from the window, framed by the sidebar
/// tone, instead of running edge to edge. The tabs sit above it, on the window.
enum HunLayout {
    /// The refined layout (panels as rounded cards with even margins) is on
    /// unless someone turns it off for the classic edge-to-edge layout.
    static let roundedPanelsKey = "hun.design.refreshed"
    static let roundedPanelsDefault = true
    /// The one corner radius used across the main window: the card, service
    /// cards, rows, fields, buttons and dialogs. Small controls come out as
    /// pills, which keeps a single shape language.
    static let radius: CGFloat = 12
    static let shellRadius: CGFloat = radius
    /// The card's margin on the left, right and bottom, sidebar edge included.
    static let shellInset: CGFloat = 10
    /// A taller tab row above the card, so the tabs have room to breathe.
    static let tabBarHeight: CGFloat = 52
}

extension View {
    /// Draws the view as the rounded main-pane card when the layout is on.
    @ViewBuilder
    func hunRoundedShell(
        _ enabled: Bool,
        leadingInset: CGFloat = 0,
        topInset: CGFloat = HunLayout.shellInset
    ) -> some View {
        if enabled {
            background(AppTheme.appBackground)
                .clipShape(RoundedRectangle(cornerRadius: HunLayout.shellRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: HunLayout.shellRadius, style: .continuous)
                        .strokeBorder(AppTheme.divider, lineWidth: 1)
                )
                .padding(.top, topInset)
                .padding(.trailing, HunLayout.shellInset)
                .padding(.bottom, HunLayout.shellInset)
                .padding(.leading, leadingInset)
        } else {
            self
        }
    }
}

/// The app's rounded shape: the card's corner radius, scaled down on small
/// controls (buttons, fields, rows) so they share the card's corner shape
/// instead of turning into pills.
struct HunRoundedShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(HunLayout.radius, min(inset.width, inset.height) * 0.3)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: inset)
    }

    func inset(by amount: CGFloat) -> HunRoundedShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}


/// Hun's light-mode palette, picked in Settings › Appearance. Every light
/// colour above is written in Graphite; Clay, the default, swaps them for
/// its own. Dark mode is the same in both.
nonisolated enum HunPalette: String, CaseIterable, Identifiable {
    /// The website's: warm paper and ink with a terracotta accent.
    case clay
    /// Neutral greys, with the terracotta accent.
    case graphite

    static let key = "hun.appearance.palette"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graphite: return "Graphite"
        case .clay: return "Clay"
        }
    }

    var icon: String {
        switch self {
        case .graphite: return "pencil.tip"
        case .clay: return "sun.horizon"
        }
    }

    /// Read on every colour resolve, so it's kept in memory, not looked up.
    /// Set it through `select(_:)`; tests set it directly to pin a palette.
    nonisolated(unsafe) static var current: HunPalette =
        UserDefaults.standard.string(forKey: key).flatMap(HunPalette.init) ?? .clay

    static func select(_ palette: HunPalette) {
        current = palette
        UserDefaults.standard.set(palette.rawValue, forKey: key)
    }

    /// Graphite light colour → Clay light colour.
    private static let clayLight: [UInt32: UInt32] = [
        0xF7F7F2: 0xFBF8F3, // app background, menu, dialog → a step lighter than the website's paper
        0xF2F2EC: 0xF5F0E6, // sidebar, mode selector → the website's paper
        0xFFFFFF: 0xFFFCF6, // raised: chips, buttons, fields, tabs → cream
        0x181816: 0x1F1B16, // hairlines, hover and selection tints → ink
        0x232321: 0x1F1B16, // primary text → ink
        0x62625D: 0x4F483F, // secondary text
        0x8B8B84: 0x8A8174, // tertiary text
        0x4D4D49: 0x4F483F, // log text
        0x92928B: 0x938A7D, // log timestamps
        0x27833F: 0x3E7B4F, // running green
        0x1A1A18: 0x1F1B16, // update button fill → ink
    ]

    static func light(_ hex: UInt32) -> UInt32 {
        current == .clay ? clayLight[hex] ?? hex : hex
    }


}
