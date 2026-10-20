import AppKit
import Testing
@testable import hun

/// Icons are measured once and drawn so they stay visible on Hun's tiles.
struct ProjectIconTraitsTests {
    private func image(width: CGFloat = 64, height: CGFloat = 64, draw: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            draw(rect)
            return true
        }
    }

    private func mark(_ color: NSColor) -> NSImage {
        image { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 14, dy: 14)).fill()
        }
    }

    private func treatment(_ image: NSImage, dark: Bool) throws -> ProjectIconTreatment {
        try #require(ProjectIconTraits.measure(image)).treatment(dark: dark)
    }

    @Test func aBlackMarkGetsABackingInDarkModeOnly() throws {
        let black = mark(.black)
        #expect(try treatment(black, dark: true) == .backed)
        #expect(try treatment(black, dark: false) == .plain)
    }

    @Test func aWhiteMarkGetsABackingInLightModeOnly() throws {
        let white = mark(.white)
        #expect(try treatment(white, dark: false) == .backed)
        #expect(try treatment(white, dark: true) == .plain)
    }

    @Test func aDarkColouredLogoGetsABackingInDarkMode() throws {
        let navy = mark(NSColor(srgbRed: 0.05, green: 0.08, blue: 0.35, alpha: 1))
        #expect(try treatment(navy, dark: true) == .backed)
        #expect(try treatment(navy, dark: false) == .plain)
    }

    @Test func aFullTileFillsAndABannerIsNotUsed() throws {
        let tile = image { rect in
            NSColor(srgbRed: 0.04, green: 0.04, blue: 0.04, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
        }
        #expect(try treatment(tile, dark: true) == .fill)

        let banner = image(width: 1200, height: 630) { rect in
            NSColor.darkGray.setFill()
            rect.fill()
        }
        #expect(try treatment(banner, dark: true) == .unusable)
        #expect(!ProjectIconTraits.isIconShaped(NSSize(width: 1200, height: 630)))
        #expect(ProjectIconTraits.isIconShaped(NSSize(width: 512, height: 512)))
    }

    @Test func aColourfulLogoIsLeftAsIs() throws {
        let orange = mark(NSColor(srgbRed: 0.95, green: 0.5, blue: 0.1, alpha: 1))
        #expect(try treatment(orange, dark: true) == .plain)
        #expect(try treatment(orange, dark: false) == .plain)
    }
}
