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
    @State private var store = HunStore(
        navigationDefaults: .standard,
        startAutomatically: false
    )
    @State private var updater = HunUpdater()
    @State private var license = HunLicenseManager()

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

        MenuBarExtra {
            HunLicenseMenuBarView()
                .environment(store)
                .environment(license)
        } label: {
            Image(systemName: "rectangle.badge.sparkles.fill")
        }
        .menuBarExtraStyle(.window)
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
