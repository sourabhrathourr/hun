#!/usr/bin/env swift

import AppKit

let canvasSize = NSSize(width: 660, height: 400)

guard CommandLine.arguments.count == 3,
      let scale = Int(CommandLine.arguments[2]),
      [1, 2].contains(scale)
else {
    fputs("Usage: render-dmg-background.swift OUTPUT.png SCALE(1|2)\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width) * scale,
    pixelsHigh: Int(canvasSize.height) * scale,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
bitmap.size = canvasSize

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create the DMG background graphics context.\n", stderr)
    exit(1)
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func drawCentered(
    _ text: String,
    y: CGFloat,
    font: NSFont,
    foreground: NSColor,
    tracking: CGFloat = 0
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: foreground,
        .kern: tracking,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let size = attributed.size()
    attributed.draw(
        at: NSPoint(
            x: (canvasSize.width - size.width) / 2,
            y: y
        )
    )
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

let fullRect = NSRect(origin: .zero, size: canvasSize)
color(0xf3f3f0).setFill()
NSBezierPath(rect: fullRect).fill()

for centerX in [CGFloat(170), CGFloat(490)] {
    let haloRect = NSRect(x: centerX - 82, y: 88, width: 164, height: 164)
    color(0xffffff, alpha: 0.72).setFill()
    NSBezierPath(ovalIn: haloRect).fill()
    color(0xd9d9d4).setStroke()
    let halo = NSBezierPath(ovalIn: haloRect)
    halo.lineWidth = 1
    halo.stroke()
}

let line = NSBezierPath()
line.move(to: NSPoint(x: 270, y: 170))
line.line(to: NSPoint(x: 382, y: 170))
line.lineWidth = 1.25
color(0x92928c).setStroke()
line.stroke()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 382, y: 170))
arrow.line(to: NSPoint(x: 370, y: 177))
arrow.move(to: NSPoint(x: 382, y: 170))
arrow.line(to: NSPoint(x: 370, y: 163))
arrow.lineWidth = 1.25
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
color(0x74746f).setStroke()
arrow.stroke()

drawCentered(
    "hun",
    y: 322,
    font: NSFont.systemFont(ofSize: 28, weight: .semibold),
    foreground: color(0x1c1c1a)
)
drawCentered(
    "DRAG TO INSTALL",
    y: 298,
    font: NSFont.systemFont(ofSize: 9, weight: .medium),
    foreground: color(0x74746f),
    tracking: 1.6
)
drawCentered(
    "Drag hun into Applications",
    y: 42,
    font: NSFont.systemFont(ofSize: 11, weight: .regular),
    foreground: color(0x777771)
)

color(0xd4d4cf).setStroke()
let insetBorder = NSBezierPath(
    roundedRect: fullRect.insetBy(dx: 0.5, dy: 0.5),
    xRadius: 10,
    yRadius: 10
)
insetBorder.lineWidth = 1
insetBorder.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the DMG background PNG.\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
