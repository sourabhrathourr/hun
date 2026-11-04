import AppKit
import Darwin
import ServiceManagement
import SwiftUI

/// Opened at login, Hun starts quietly in the menu bar: no dashboard window,
/// and, with "Hide Dock icon when windows are closed" on, no Dock icon. The
/// dashboard is a click away ("Open Hun" in the menu bar, or the Dock icon).
/// Opened any other way, Hun opens its window as always. If it needs the
/// person (the welcome isn't done, or the license needs attention), it shows
/// the window anyway.
///
/// macOS doesn't say plainly that an app was opened at login, so Hun infers
/// it: Open at login is on, and Hun started within `loginGrace` of the
/// person's login (when their loginwindow started). A miss fails safe: the
/// window shows, as before.
@MainActor
enum HunQuietLaunch {
    static let loginGrace: TimeInterval = 120
    /// Debug builds: pretend this launch was at login (read at launch).
    static let simulateKey = "hun.debug.simulateLoginLaunch"

    /// Decided once, as Hun starts.
    static let isActive: Bool = decide()
    private static var hidFirstWindow = false

    private static func decide() -> Bool {
        // A Mac that hasn't finished the welcome needs the window.
        guard UserDefaults.standard.bool(forKey: HunOnboarding.completedKey) else { return false }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: simulateKey) { return true }
        #endif
        guard SMAppService.mainApp.status == .enabled, let since = secondsSinceLogin() else { return false }
        return since >= 0 && since < loginGrace
    }

    /// The dashboard window SwiftUI opens at launch: on a quiet launch it's
    /// made invisible before it's drawn, then closed. It still had to exist:
    /// it's how Hun gets the means to open a window later.
    static func windowAppeared(_ window: NSWindow) {
        guard isActive, !hidFirstWindow else { return }
        hidFirstWindow = true
        window.alphaValue = 0
        DispatchQueue.main.async { window.close() }
    }

    /// Whether the window is the one being hidden, which shouldn't bring the
    /// Dock icon back.
    static func isHidden(_ window: NSWindow) -> Bool {
        isActive && window.alphaValue == 0
    }

    /// Once the license check settles, shows the window if the license needs
    /// the person (the welcome is where they sort it out).
    static func watchLicense(_ license: HunLicenseManager) {
        guard isActive else { return }
        Task {
            for _ in 0..<120 {
                switch license.state {
                case .checking, .activating:
                    try? await Task.sleep(for: .milliseconds(500))
                    continue
                default:
                    break
                }
                break
            }
            if !license.isLicensed {
                hunApp.openDashboard()
            }
        }
    }

    /// Seconds since the person logged in: since their loginwindow, which
    /// starts with each login session, began. Nil if it can't be found.
    nonisolated static func secondsSinceLogin() -> TimeInterval? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 16)
        size = processes.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &processes, &size, nil, 0) == 0 else { return nil }

        var latest: Date?
        for index in 0..<(size / MemoryLayout<kinfo_proc>.stride) {
            var process = processes[index]
            let name = withUnsafeBytes(of: &process.kp_proc.p_comm) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            guard name == "loginwindow" else { continue }
            let start = process.kp_proc.p_starttime
            let date = Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
            if latest.map({ date > $0 }) ?? true { latest = date }
        }
        return latest.map { Date().timeIntervalSince($0) }
    }
}

/// Hun's application delegate, alongside SwiftUI's: on a quiet launch with
/// the Dock icon hidden, Hun becomes menu-bar-only before it finishes
/// launching, so the icon never flashes.
@MainActor
final class HunAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if HunQuietLaunch.isActive && HunAppBehavior.hidesDockWhenClosed {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
