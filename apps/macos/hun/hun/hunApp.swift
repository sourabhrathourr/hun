//
//  hunApp.swift
//  hun
//
//  Created by Sourabh Rathour on 02/05/26.
//

import SwiftUI
import AppKit

@main
struct hunApp: App {
    @NSApplicationDelegateAdaptor(HunAppDelegate.self) private var appDelegate
    @State private var store: HunStore
    @State private var updater = HunUpdater()
    @State private var license: HunLicenseManager

    init() {
        HunOnboarding.checkForReinstall()
        HunFonts.register()
        let store = HunStore(navigationDefaults: .standard, startAutomatically: false)
        let license = HunLicenseManager()
        _store = State(initialValue: store)
        _license = State(initialValue: license)
        // NSApp exists once the app is running: apply the saved theme and add
        // the menu bar item then.
        DispatchQueue.main.async {
            HunTheme.saved.apply()
            HunStatusItemController.install(store: store, license: license)
            HunAppBehavior.install()
            // Notes, before the welcome can finish, whether this Mac was
            // already set up: a fresh install's first launch isn't an update.
            _ = HunWhatsNew.shared
            license.startMonitoring()
            // Opened quietly at login: show the window only if the license
            // needs the person.
            HunQuietLaunch.watchLicense(license)
        }
        #if DEBUG
        HunDebugHooks.install(store: store, license: license)
        #endif
        DispatchQueue.global(qos: .utility).async {
            HunCLILinker.linkBundledCLI()
        }
    }

    var body: some Scene {
        WindowGroup("hun", id: "dashboard") {
            HunLicensedRootView()
                .environment(store)
                .environment(updater)
                .environment(license)
                .frame(minWidth: 560, minHeight: 420)
                .background(HunWindowOpenerCapture().frame(width: 0, height: 0))
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            HunTerminalCommands()
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Dashboard") {
                    Self.openDashboard()
                }
                .keyboardShortcut("d", modifiers: .command)
            }
        }
    }

    /// Colours resolve per appearance, so a palette change only shows once
    /// the appearance changes. This steps every window to dark and straight
    /// back, laying each out at both steps so SwiftUI resolves its colours
    /// again, all inside one Core Animation transaction: only the final state
    /// reaches the screen, so there's no dark frame. (A step to high contrast
    /// doesn't make SwiftUI re-resolve, and stepping across run loop turns
    /// either doesn't either or shows the dark frame.)
    static func redrawColors() {
        let saved = NSApp.appearance
        let current = saved ?? NSApp.effectiveAppearance
        let dark = current.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let views = NSApp.windows.compactMap(\.contentView)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSApp.appearance = NSAppearance(named: dark ? .aqua : .darkAqua)
        views.forEach { $0.layoutSubtreeIfNeeded() }
        NSApp.appearance = saved
        views.forEach { $0.layoutSubtreeIfNeeded() }
        CATransaction.commit()
    }

    static func openDashboard() {
        // The Dock icon may be hidden while no window is open.
        HunAppBehavior.showDock()
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeKey && window.isRestorable {
            window.makeKeyAndOrderFront(nil)
            return
        }
        for window in NSApp.windows where window.canBecomeKey && !(window is NSPanel) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Every window was closed: open a new one.
        HunAppBehavior.openWindow?(id: "dashboard")
    }
}
