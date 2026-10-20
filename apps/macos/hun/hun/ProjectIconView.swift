import SwiftUI
import AppKit

struct ProjectIconView: View {
    let name: String
    let iconPath: String?
    let size: CGFloat
    let cornerRadius: CGFloat
    var emphasized = false
    var status: ProjectStatus?
    @Environment(\.colorScheme) private var colorScheme

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
        // Running: a thin green ring set just outside the icon, at one fixed
        // strength whether or not the row is selected.
        .overlay {
            if status == .running {
                RoundedRectangle(cornerRadius: cornerRadius + Self.ringGap, style: .continuous)
                    .strokeBorder(AppTheme.success.opacity(0.3), lineWidth: 1)
                    .padding(-Self.ringGap)
            }
        }
        .animation(.easeOut(duration: 0.16), value: status)
        .overlay(alignment: .bottomTrailing) {
            if status == .crashed {
                Circle()
                    .fill(AppTheme.danger)
                    .frame(width: max(6, size * 0.27), height: max(6, size * 0.27))
                    .overlay(Circle().stroke(AppTheme.appBackground, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
        }
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
