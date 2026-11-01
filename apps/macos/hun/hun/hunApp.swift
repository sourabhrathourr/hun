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
            license.startMonitoring()
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
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeKey && window.isRestorable {
            window.makeKeyAndOrderFront(nil)
            return
        }
        for window in NSApp.windows where window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
