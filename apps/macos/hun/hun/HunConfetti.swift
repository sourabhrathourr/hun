import AppKit
import QuartzCore

/// A burst of confetti over the whole screen, for unlocking Hun. Two bursts
/// from the bottom corners reach the top of the screen in about half a
/// second; the pieces (strips, triangles, dots) tumble as they drift down,
/// and are gone in about three seconds. Skipped with Reduce Motion.
///
/// Every piece's flight is worked out up front and handed to Core Animation
/// as keyframes, so the whole burst runs on the GPU and costs the main thread
/// nothing while it plays (drawing it frame by frame stalled the app).
@MainActor
enum HunConfetti {
    private static var window: NSWindow?

    static func celebrate(on screen: NSScreen? = NSApp.keyWindow?.screen ?? NSScreen.main) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              window == nil,
              let screen
        else { return }

        let size = screen.frame.size
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false

        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        window.contentView = view
        window.orderFrontRegardless()
        self.window = window

        let scale = screen.backingScaleFactor
        let flights = HunConfettiFlight.burst(in: size)
        let start = CACurrentMediaTime() + 0.02
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for flight in flights {
            view.layer?.addSublayer(flight.layer(scale: scale, beginTime: start))
        }
        CATransaction.commit()

        let longest = flights.map(\.duration).max() ?? 3
        DispatchQueue.main.asyncAfter(deadline: .now() + longest + 0.3) {
            window.orderOut(nil)
            Self.window = nil
        }
    }
}

/// One piece's path, sampled from a small physics simulation.
@MainActor
private struct HunConfettiFlight {
    enum Shape { case strip, triangle, dot }

    let shape: Shape
    let colorIndex: Int
    let size: CGFloat
    let duration: Double
    let positions: [CGPoint]
    let rotations: [CGFloat]
    let tilts: [CGFloat]
    let opacities: [CGFloat]

    static let colorHexes: [UInt32] = [0xF94860, 0xE153F3, 0x0099FE, 0xF8CF00, 0x2DCE6A]

    // Tuned against a recording: with this drag and gravity the fastest
    // pieces reach the top in ~0.5s, then everything drifts down.
    private static let gravity: CGFloat = 1000
    private static let drag: CGFloat = 3.0
    private static let piecesPerSide = 300
    private static let step: CGFloat = 1.0 / 30

    static func burst(in bounds: CGSize) -> [HunConfettiFlight] {
        let reach = 6000 * bounds.height / 1440
        var flights: [HunConfettiFlight] = []
        flights.reserveCapacity(piecesPerSide * 2)
        for side in [CGFloat(1), -1] {
            let origin = CGPoint(x: side > 0 ? -8 : bounds.width + 8, y: -8)
            let aim = (CGFloat.pi / 180) * (side > 0 ? 60 : 120)
            for _ in 0..<piecesPerSide {
                let angle = aim + CGFloat.random(in: -0.42...0.42)
                let speed = reach * CGFloat.random(in: 0.42...1.0)
                let shapes: [Shape] = [.strip, .strip, .triangle, .dot]
                flights.append(simulate(
                    from: origin,
                    velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                    shape: shapes.randomElement() ?? .strip,
                    life: CGFloat.random(in: 2.3...3.1)
                ))
            }
        }
        return flights
    }

    private static func simulate(from origin: CGPoint, velocity start: CGVector, shape: Shape, life: CGFloat) -> HunConfettiFlight {
        var position = origin
        var velocity = start
        var rotation = CGFloat.random(in: 0...(2 * .pi))
        let spin = CGFloat.random(in: -7...7)
        var tilt = CGFloat.random(in: 0...(2 * .pi))
        let tiltSpeed = CGFloat.random(in: 7...14)
        let sway = CGFloat.random(in: 0...(2 * .pi))
        let damping = exp(-drag * step)

        var positions: [CGPoint] = []
        var rotations: [CGFloat] = []
        var tilts: [CGFloat] = []
        var opacities: [CGFloat] = []
        var age: CGFloat = 0
        while age <= life {
            positions.append(position)
            rotations.append(rotation)
            tilts.append(max(0.12, abs(cos(tilt))))
            // Fade over the last stretch of the piece's life.
            let remaining: CGFloat = (life - age) / 0.7
            opacities.append(min(1, max(0, remaining)))
            age += step
            velocity.dy -= gravity * step
            velocity.dx += sin(age * 5 + sway) * 60 * step
            velocity.dx *= damping
            velocity.dy *= damping
            position.x += velocity.dx * step
            position.y += velocity.dy * step
            rotation += spin * step
            tilt += tiltSpeed * step
        }
        let pieceSize: CGFloat = shape == .dot ? CGFloat.random(in: 7...9) : CGFloat.random(in: 11...16)
        return HunConfettiFlight(
            shape: shape,
            colorIndex: Int.random(in: 0..<colorHexes.count),
            size: pieceSize,
            duration: Double(age),
            positions: positions,
            rotations: rotations,
            tilts: tilts,
            opacities: opacities
        )
    }

    /// A layer that flies this path on its own, on the render server.
    func layer(scale: CGFloat, beginTime: CFTimeInterval) -> CALayer {
        let layer = CALayer()
        let height: CGFloat = shape == .strip ? size * 0.34 : size
        layer.bounds = CGRect(x: 0, y: 0, width: size, height: height)
        layer.contentsScale = scale
        layer.contents = Self.image(shape: shape, colorIndex: colorIndex, scale: scale)
        layer.position = positions.last ?? .zero
        layer.opacity = 0

        let last = Double(max(positions.count - 1, 1))
        let times: [NSNumber] = positions.indices.map { NSNumber(value: Double($0) / last) }

        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = positions.map { NSValue(point: $0) }
        move.keyTimes = times

        var transforms: [NSValue] = []
        transforms.reserveCapacity(rotations.count)
        for index in rotations.indices {
            let rotated = CATransform3DMakeRotation(rotations[index], 0, 0, 1)
            transforms.append(NSValue(caTransform3D: CATransform3DScale(rotated, 1, tilts[index], 1)))
        }
        let turn = CAKeyframeAnimation(keyPath: "transform")
        turn.values = transforms
        turn.keyTimes = times

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = opacities.map { NSNumber(value: Double($0)) }
        fade.keyTimes = times

        let group = CAAnimationGroup()
        group.animations = [move, turn, fade]
        group.duration = duration
        group.beginTime = beginTime
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "flight")
        return layer
    }

    // One small image per shape and colour, shared by every piece.
    private static var images: [String: CGImage] = [:]

    private static func image(shape: Shape, colorIndex: Int, scale: CGFloat) -> CGImage? {
        let key = "\(shape)-\(colorIndex)-\(scale)"
        if let cached = images[key] { return cached }
        let side: CGFloat = 16
        let height: CGFloat = shape == .strip ? side * 0.34 : side
        let width = Int(ceil(side * scale))
        let pixelHeight = Int(ceil(height * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        let hex = colorHexes[colorIndex]
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        let rect = CGRect(x: 0, y: 0, width: width, height: pixelHeight)
        switch shape {
        case .strip:
            context.fill(rect)
        case .triangle:
            context.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            context.closePath()
            context.fillPath()
        case .dot:
            context.fillEllipse(in: rect)
        }
        let image = context.makeImage()
        images[key] = image
        return image
    }
}
