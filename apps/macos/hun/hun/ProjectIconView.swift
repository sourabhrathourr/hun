import SwiftUI
import AppKit

struct ProjectIconView: View {
    let name: String
    let iconPath: String?
    let size: CGFloat
    let cornerRadius: CGFloat
    var emphasized = false
    var status: ProjectStatus?

    private var image: NSImage? {
        ProjectIconLoader.image(at: iconPath)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(emphasized ? AppTheme.tabActive : AppTheme.searchField)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .padding(max(2, size * 0.10))
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                Text(initial)
                    .font(.system(size: max(9, size * 0.48), weight: .semibold, design: .rounded))
                    .foregroundStyle(emphasized ? AppTheme.textPrimary : AppTheme.textSecondary)
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppTheme.divider, lineWidth: 0.5)
        }
        .frame(width: size, height: size)
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
}

@MainActor
private enum ProjectIconLoader {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(at path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard FileManager.default.fileExists(atPath: path),
              let image = NSImage(contentsOfFile: path)
        else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }
}
