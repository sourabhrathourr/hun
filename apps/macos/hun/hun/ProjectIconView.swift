import SwiftUI
import AppKit

struct ProjectIconView: View {
    let name: String
    let iconPath: String?
    let size: CGFloat
    let cornerRadius: CGFloat
    var emphasized = false
    var status: ProjectStatus?
    /// The colour around the status badge, so it reads as cut out of what's behind.
    var badgeRim: Color = AppTheme.appBackground
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HunRunningMarker.key) private var markerName = HunRunningMarker.defaultValue.rawValue
    @State private var pulsing = false

    private var marker: HunRunningMarker {
        HunRunningMarker(rawValue: markerName) ?? .defaultValue
    }

    private var loaded: ProjectIconLoader.Icon? {
        ProjectIconLoader.icon(at: iconPath)
    }

    var body: some View {
        let icon = loaded
        let treatment = icon.map { $0.traits.treatment(dark: colorScheme == .dark) }
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tileColor(for: treatment))

            if let icon, let treatment, treatment != .unusable {
                iconImage(icon.image, treatment: treatment)
            } else {
                Text(initial)
                    .font(.system(size: max(9, size * 0.48), weight: .semibold, design: .rounded))
                    .foregroundStyle(emphasized ? AppTheme.textPrimary : AppTheme.textSecondary)
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.divider, lineWidth: 0.5)
        }
        .frame(width: size, height: size)
        // Ring marker: a green ring set just outside the icon, sized in whole
        // points so it sits evenly on every side.
        .overlay {
            if marker == .ring && (status == .running || status == .starting || status == .crashed) {
                let gap: CGFloat = 2
                RoundedRectangle(cornerRadius: cornerRadius + gap, style: .continuous)
                    .strokeBorder(ringColor.opacity(0.65), lineWidth: 1.5)
                    .frame(width: size + gap * 2, height: size + gap * 2)
                    .opacity(status == .starting && pulsing ? 0.35 : 1)
                    .onAppear { startPulse() }
            }
        }
        .animation(.easeOut(duration: 0.16), value: status)
        // One family of corner badges: green running, amber starting (it
        // breathes), red crashed. The badge sits cut out of the background.
        .overlay(alignment: .bottomTrailing) {
            if let badge = badgeColor {
                Circle()
                    .fill(badge)
                    .frame(width: badgeSize, height: badgeSize)
                    .overlay(Circle().stroke(badgeRim, lineWidth: 1.5))
                    .opacity(status == .starting && pulsing ? 0.45 : 1)
                    .offset(x: 2, y: 2)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .onAppear { startPulse() }
            }
        }
    }

    private var badgeSize: CGFloat { max(6, size * 0.36) }

    /// A crash shows in the chosen marker, in red, rather than as a badge.
    private var badgeColor: Color? { nil }

    private var ringColor: Color {
        switch status {
        case .starting: return AppTheme.warning
        case .crashed: return AppTheme.danger
        default: return AppTheme.liveMarker
        }
    }

    /// A starting project's marker breathes until it's up.
    private func startPulse() {
        guard status == .starting, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulsing = true }
    }

    private var initial: String {
        String(name.prefix(1).uppercased())
    }

    @ViewBuilder
    private func iconImage(_ image: NSImage, treatment: ProjectIconTreatment) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch treatment {
        case .fill:
            // Already a complete tile: edge to edge, no frame inside a frame.
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(shape)
        case .plain, .backed, .unusable:
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .padding(max(2, size * 0.12))
                .frame(width: size, height: size)
                .clipShape(shape)
        }
    }

    private func tileColor(for treatment: ProjectIconTreatment?) -> Color {
        if treatment == .backed {
            // A soft contrasting backing for a logo that would otherwise
            // disappear; the logo keeps its own colours.
            return colorScheme == .dark ? Color(white: 0.78) : Color(white: 0.18)
        }
        return emphasized ? AppTheme.tabActive : AppTheme.searchField
    }

    /// Space between the icon and its running ring.
    private static let ringGap: CGFloat = 2
}

/// How a project icon is drawn so it stays visible on Hun's tiles.
enum ProjectIconTreatment: Equatable {
    /// On the usual tile, as is.
    case plain
    /// Fills the tile: the image is already a complete icon tile.
    case fill
    /// On a contrasting backing, because it would vanish on the tile.
    case backed
    /// Not an icon (a banner or link preview); the letter avatar is used.
    case unusable
}

/// What an icon looks like, measured once from a small thumbnail.
struct ProjectIconTraits: Equatable {
    var aspectRatio: CGFloat
    /// The corners are opaque: the image is a full tile, not a mark.
    var fillsCorners: Bool
    /// Average brightness (0–1) of the visible pixels.
    var luminance: CGFloat
    /// Average colourfulness (0–1) of the visible pixels.
    var saturation: CGFloat

    /// Far enough from square that it isn't an icon (a banner, a preview).
    static func isIconShaped(_ size: NSSize) -> Bool {
        guard size.height > 0 else { return false }
        let ratio = size.width / size.height
        return ratio <= 1.3 && ratio >= 0.77
    }

    func treatment(dark: Bool) -> ProjectIconTreatment {
        if !Self.isIconShaped(NSSize(width: aspectRatio, height: 1)) { return .unusable }
        if fillsCorners { return .fill }
        // Black, white and grey marks vanish sooner than coloured ones.
        let monochrome = saturation < 0.12
        let tooDark = dark && luminance < (monochrome ? 0.45 : 0.3)
        let tooLight = !dark && luminance > (monochrome ? 0.6 : 0.8)
        return tooDark || tooLight ? .backed : .plain
    }

    static func measure(_ image: NSImage) -> ProjectIconTraits? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let side = 24
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        // Draw it aspect-fit, as it will be shown.
        let scale = min(CGFloat(side) / image.size.width, CGFloat(side) / image.size.height)
        let drawn = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(x: (CGFloat(side) - drawn.width) / 2, y: (CGFloat(side) - drawn.height) / 2, width: drawn.width, height: drawn.height),
            from: .zero, operation: .copy, fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return nil }

        func pixel(_ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            let i = (y * side + x) * 4
            let a = CGFloat(data[i + 3]) / 255
            guard a > 0 else { return (0, 0, 0, 0) }
            // Stored premultiplied; undo that to read the true colour.
            return (CGFloat(data[i]) / 255 / a, CGFloat(data[i + 1]) / 255 / a, CGFloat(data[i + 2]) / 255 / a, a)
        }

        let inset = 3
        let corners = [(inset, inset), (side - 1 - inset, inset), (inset, side - 1 - inset), (side - 1 - inset, side - 1 - inset)]
        let fillsCorners = corners.allSatisfy { pixel($0.0, $0.1).a > 0.85 }

        var weight: CGFloat = 0, luminance: CGFloat = 0, saturation: CGFloat = 0
        for y in 0..<side {
            for x in 0..<side {
                let p = pixel(x, y)
                guard p.a > 0.2 else { continue }
                luminance += (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b) * p.a
                saturation += (max(p.r, p.g, p.b) - min(p.r, p.g, p.b)) * p.a
                weight += p.a
            }
        }
        guard weight > 0 else { return nil }
        return ProjectIconTraits(
            aspectRatio: image.size.width / image.size.height,
            fillsCorners: fillsCorners,
            luminance: luminance / weight,
            saturation: saturation / weight
        )
    }
}

@MainActor
private enum ProjectIconLoader {
    final class Icon {
        let image: NSImage
        let traits: ProjectIconTraits

        init(image: NSImage, traits: ProjectIconTraits) {
            self.image = image
            self.traits = traits
        }
    }

    private static let cache = NSCache<NSString, Icon>()

    static func icon(at path: String?) -> Icon? {
        guard let path, !path.isEmpty else { return nil }
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard FileManager.default.fileExists(atPath: path),
              let image = NSImage(contentsOfFile: path),
              let traits = ProjectIconTraits.measure(image)
        else {
            return nil
        }
        let icon = Icon(image: image, traits: traits)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

/// How the sidebar marks a running project, chosen in Settings ›
/// Appearance. Running names also read brighter and stopped ones step back.
enum HunRunningMarker: String, CaseIterable, Identifiable {
    /// A small level meter at the end of the row.
    case activity
    /// A green ring around the icon.
    case ring
    /// A tinted bar with a green stroke at the start of the row.
    case bar

    static let key = "hun.appearance.runningMarker"
    static let defaultValue = HunRunningMarker.bar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "Activity"
        case .ring: return "Ring"
        case .bar: return "Bar"
        }
    }

    var icon: String {
        switch self {
        case .activity: return "chart.bar.fill"
        case .ring: return "app"
        case .bar: return "capsule.portrait"
        }
    }
}

/// The Bar marker: a soft tint inside a green stroke.
struct HunRunningBar: View {
    let color: Color

    var body: some View {
        Capsule().fill(color.opacity(0.22))
            .overlay(Capsule().strokeBorder(color.opacity(0.85), lineWidth: 1))
            .frame(width: 5, height: 15)
            .accessibilityHidden(true)
    }
}

/// The Activity marker: three bars rising short to tall, like a level meter.
struct HunActivityBars: View {
    let color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach([4.0, 6.5, 9.0], id: \.self) { height in
                Capsule().fill(color).frame(width: 2, height: height)
            }
        }
        .frame(height: 9, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
