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
    @State private var store = HunStore(navigationDefaults: .standard)

    var body: some Scene {
        WindowGroup("hun", id: "dashboard") {
            ContentView()
                .environment(store)
                .frame(minWidth: 560, minHeight: 420)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Dashboard") {
                    Self.openDashboard()
                }
                .keyboardShortcut("d", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(store)
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
