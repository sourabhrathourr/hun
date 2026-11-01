import CoreText
import SwiftUI

/// Bricolage Grotesque, hun.sh's display face (SIL Open Font License),
/// for the welcome's headline. Registered for this process at launch.
enum HunFonts {
    static func register() {
        guard let url = Bundle.main.url(forResource: "BricolageGrotesque-Bold", withExtension: "woff") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func display(size: CGFloat) -> Font {
        if NSFont(name: "BricolageGrotesque96pt-Bold", size: size) != nil {
            return .custom("BricolageGrotesque96pt-Bold", size: size)
        }
        return .system(size: size, weight: .bold)
    }
}

