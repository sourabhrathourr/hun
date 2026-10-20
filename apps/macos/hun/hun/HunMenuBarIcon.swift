import AppKit
import SwiftUI

/// Hun's menu bar mark: the app icon's toggle switch, as a glyph. It's off
/// (an outlined pill, knob on the left) when nothing runs and on (a solid
/// pill, knob cut out on the right) when something does.
enum HunMenuBarGlyph {
    /// Points; the menu bar centres it vertically.
    static let size = NSSize(width: 24, height: 16)

    private static let off = make(on: false)
    private static let on = make(on: true)

    static func image(on isOn: Bool) -> NSImage {
        isOn ? on : off
    }

    private static func make(on isOn: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            let pill = NSRect(x: 2, y: 2, width: 20, height: 12)
            let radius = pill.height / 2
            let knobRadius: CGFloat = 3.5
            NSColor.black.setFill()
            NSColor.black.setStroke()

            if isOn {
                // A solid pill with the knob knocked out on the right.
                let path = NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius)
                path.append(NSBezierPath(ovalIn: NSRect(
                    x: pill.maxX - radius - knobRadius, y: pill.midY - knobRadius,
                    width: knobRadius * 2, height: knobRadius * 2
                )))
                path.windingRule = .evenOdd
                path.fill()
            } else {
                // An outlined pill (inset half the stroke so it stays sharp)
                // with a solid knob on the left.
                let lineWidth: CGFloat = 1.5
                let outline = pill.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                let path = NSBezierPath(
                    roundedRect: outline,
                    xRadius: outline.height / 2,
                    yRadius: outline.height / 2
                )
                path.lineWidth = lineWidth
                path.stroke()
                NSBezierPath(ovalIn: NSRect(
                    x: pill.minX + radius - knobRadius, y: pill.midY - knobRadius,
                    width: knobRadius * 2, height: knobRadius * 2
                )).fill()
            }
            return true
        }
        // macOS tints template images for the menu bar's appearance.
        image.isTemplate = true
        image.accessibilityDescription = "Hun"
        return image
    }
}

/// The menu bar item: the switch is on while any project is running.
struct HunMenuBarLabel: View {
    let store: HunStore

    private var isOn: Bool {
        store.model.projects.contains { $0.status == .running || $0.status == .starting }
    }

    var body: some View {
        Image(nsImage: HunMenuBarGlyph.image(on: isOn))
            .accessibilityLabel(isOn ? "Hun, projects running" : "Hun")
    }
}
