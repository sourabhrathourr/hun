import AppKit
import ServiceManagement
import SwiftUI

/// How Hun lives on the Mac: whether it opens at login, and whether its Dock
/// icon stays once its windows are closed. Either way it keeps running in
/// the menu bar.
@MainActor
enum HunAppBehavior {
    static let hideDockKey = "hun.app.hideDockWhenClosed"

    static var hidesDockWhenClosed: Bool { UserDefaults.standard.bool(forKey: hideDockKey) }

    /// Opens a new dashboard window when none is left to show (captured from
    /// the first one; the Dock icon may be hidden, so nothing else can).
    static var openWindow: OpenWindowAction?

    private static var observers: [NSObjectProtocol] = []

    static func install() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let closing = note.object as? NSWindow
            MainActor.assumeIsolated {
                // Count what's left once the window has gone.
                DispatchQueue.main.async { hideDockIfNoWindows(ignoring: closing) }
            }
        })
        observers.append(center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                // Not for the window a quiet login launch is hiding.
                if let window, HunQuietLaunch.isHidden(window) { return }
                showDock()
            }
        })
    }

    // MARK: Open at login

    static var loginStatus: SMAppService.Status { SMAppService.mainApp.status }

    /// Turns opening at login on or off; returns what went wrong, if anything.
    static func setOpensAtLogin(_ on: Bool) -> String? {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Dock icon

    /// The setting changed: hide the icon now if no window is open, or bring
    /// it back.
    static func applyDockSetting() {
        if hidesDockWhenClosed {
            hideDockIfNoWindows(ignoring: nil)
        } else {
            showDock()
        }
    }

    static func showDock() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
    }

    private static func hideDockIfNoWindows(ignoring closing: NSWindow?) {
        guard hidesDockWhenClosed, !hasWindows(ignoring: closing) else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Hun's own windows: the dashboard and anything like it, not the menu
    /// bar panel, alerts, or the full-screen effects.
    private static func hasWindows(ignoring closing: NSWindow?) -> Bool {
        NSApp.windows.contains { window in
            window !== closing && window.isVisible && window.canBecomeMain && !(window is NSPanel)
        }
    }
}

/// Sits in each dashboard window: keeps a way to open a window for when every
/// window is closed, and lets a quiet login launch hide the first one before
/// it's drawn.
struct HunWindowOpenerCapture: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        HunAppBehavior.openWindow = context.environment.openWindow
        return HunWindowHookView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class HunWindowHookView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { HunQuietLaunch.windowAppeared(window) }
    }
}
