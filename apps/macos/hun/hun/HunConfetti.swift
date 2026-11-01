import AppKit
import QuartzCore

/// A burst of confetti over the whole screen, for unlocking Hun. Two bursts
/// from the bottom corners reach the top of the screen in about half a
/// second; the pieces (strips, triangles, dots) tumble as they drift down,
/// and are gone in about three seconds. It draws in a click-through window
/// above everything and removes itself. Skipped with Reduce Motion.
@MainActor
enum HunConfetti {
    private static var window: NSWindow?

    static func celebrate(on screen: NSScreen? = NSApp.keyWindow?.screen ?? NSScreen.main) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              window == nil,
              let screen
        else { return }

        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false

        let view = HunConfettiView(frame: NSRect(origin: .zero, size: screen.frame.size)) {
            window.orderOut(nil)
            Self.window = nil
        }
        window.contentView = view
        window.orderFrontRegardless()
        self.window = window
        view.start()
    }
}

private final class HunConfettiView: NSView {
    private struct Piece {
        enum Shape { case strip, triangle, dot }
        var position: CGPoint
        var velocity: CGVector
        let color: NSColor
        let shape: Shape
        let size: CGFloat
        var rotation: CGFloat
        let spin: CGFloat
        var tilt: CGFloat
        let tiltSpeed: CGFloat
        let swayPhase: CGFloat
        let life: CGFloat
        var age: CGFloat = 0
    }

    private static let colorHexes: [UInt32] = [0xF94860, 0xE153F3, 0x0099FE, 0xF8CF00, 0x2DCE6A]
    private static let colors: [NSColor] = colorHexes.map(color(hex:))

    private static func color(hex: UInt32) -> NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    // Tuned against a recording: with this drag and gravity the fastest
    // pieces reach the top in ~0.5s, then everything drifts down.
    private let gravity: CGFloat = 1000
    private let drag: CGFloat = 3.0
    private let piecesPerSide = 300

    private var pieces: [Piece] = []
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private let onFinish: () -> Void

    init(frame: NSRect, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }

    func start() {
        let height = bounds.height
        let reach = 6000 * height / 1440
        for side in [CGFloat(1), -1] {
            let origin = CGPoint(x: side > 0 ? -8 : bounds.width + 8, y: -8)
            for _ in 0..<piecesPerSide {
                let angle = (CGFloat.pi / 180) * (side > 0 ? 60 : 120) + .random(in: -0.42...0.42)
                let speed = reach * .random(in: 0.42...1.0)
                let shape: Piece.Shape = [.strip, .strip, .triangle, .dot].randomElement()!
                pieces.append(Piece(
                    position: origin,
                    velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                    color: Self.colors.randomElement()!,
                    shape: shape,
                    size: shape == .dot ? .random(in: 7...9) : .random(in: 11...16),
                    rotation: .random(in: 0...(2 * .pi)),
                    spin: .random(in: -7...7),
                    tilt: .random(in: 0...(2 * .pi)),
                    tiltSpeed: .random(in: 7...14),
                    swayPhase: .random(in: 0...(2 * .pi)),
                    life: .random(in: 2.3...3.1)
                ))
            }
        }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = CGFloat(lastTime == 0 ? 1.0 / 60 : min(now - lastTime, 1.0 / 30))
        lastTime = now
        let damping = exp(-drag * dt)
        for index in pieces.indices {
            var piece = pieces[index]
            piece.age += dt
            piece.velocity.dy -= gravity * dt
            // A little side-to-side sway, like paper catching the air.
            piece.velocity.dx += sin(piece.age * 5 + piece.swayPhase) * 60 * dt
            piece.velocity.dx *= damping
            piece.velocity.dy *= damping
            piece.position.x += piece.velocity.dx * dt
            piece.position.y += piece.velocity.dy * dt
            piece.rotation += piece.spin * dt
            piece.tilt += piece.tiltSpeed * dt
            pieces[index] = piece
        }
        pieces.removeAll { $0.age >= $0.life || $0.position.y < -40 }
        needsDisplay = true
        if pieces.isEmpty {
            link.invalidate()
            self.link = nil
            onFinish()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for piece in pieces {
            // Fade over the last stretch of each piece's life.
            let alpha = min(1, max(0, (piece.life - piece.age) / 0.7))
            guard alpha > 0 else { continue }
            context.saveGState()
            context.translateBy(x: piece.position.x, y: piece.position.y)
            context.rotate(by: piece.rotation)
            // Tumbling: the piece turns edge-on and back.
            context.scaleBy(x: 1, y: max(0.12, abs(cos(piece.tilt))))
            context.setFillColor(piece.color.withAlphaComponent(alpha).cgColor)
            let s = piece.size
            switch piece.shape {
            case .strip:
                context.fill(CGRect(x: -s / 2, y: -s * 0.17, width: s, height: s * 0.34))
            case .triangle:
                context.move(to: CGPoint(x: 0, y: s / 2))
                context.addLine(to: CGPoint(x: s / 2, y: -s / 2))
                context.addLine(to: CGPoint(x: -s / 2, y: -s / 2))
                context.closePath()
                context.fillPath()
            case .dot:
                context.fillEllipse(in: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
            }
            context.restoreGState()
        }
    }
}
