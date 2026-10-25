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
