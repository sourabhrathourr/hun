#if DEBUG
import AppKit
import Foundation

/// Debug builds only: lets scripts drive the same flows a person would, for
/// testing and screenshots without clicking through the UI.
///
///   sh.hun.debug.addProject   object: a folder path   (as ⌘N would)
///   sh.hun.debug.selectProject object: a folder path
///   sh.hun.debug.ask          object: "<folder path>\n<request>"
///   sh.hun.debug.snapshot     object: a PNG path; draws the main window into it
///                             (works while the display is asleep or locked)
enum HunDebugHooks {
    private static var observers: [NSObjectProtocol] = []

    @MainActor
    static func install(store: HunStore, license: HunLicenseManager) {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: .init("sh.hun.debug.addProject"), object: nil, queue: .main) { note in
            guard let path = note.object as? String else { return }
            Task { @MainActor in await store.addProject(at: URL(fileURLWithPath: path, isDirectory: true)) }
        })
        observers.append(center.addObserver(forName: .init("sh.hun.debug.selectProject"), object: nil, queue: .main) { note in
            guard let path = note.object as? String else { return }
            Task { @MainActor in
                if let project = store.model.projects.first(where: { $0.path == path }) {
                    store.selectProject(project.id)
                }
            }
        })
        observers.append(center.addObserver(forName: .init("sh.hun.debug.ask"), object: nil, queue: .main) { note in
            guard let text = note.object as? String, let split = text.firstIndex(of: "\n") else { return }
            let path = String(text[..<split])
            let request = String(text[text.index(after: split)...])
            Task { @MainActor in
                if let project = store.model.projects.first(where: { $0.path == path }) {
                    store.sendAgentMessage(request, for: project)
                }
            }
        })
        observers.append(center.addObserver(forName: .init("sh.hun.debug.paneTab"), object: nil, queue: .main) { note in
            guard let text = note.object as? String, let split = text.firstIndex(of: "\n") else { return }
            let path = String(text[..<split])
            let tab: HunPaneTab = text[text.index(after: split)...] == "setup" ? .setup : .logs
            Task { @MainActor in store.paneTabs[path] = tab }
        })
        observers.append(center.addObserver(forName: .init("sh.hun.debug.steer"), object: nil, queue: .main) { note in
            guard let text = note.object as? String, let split = text.firstIndex(of: "\n") else { return }
            let path = String(text[..<split])
            let request = String(text[text.index(after: split)...])
            Task { @MainActor in
                if let project = store.model.projects.first(where: { $0.path == path }) {
                    store.steerAgent(request, for: project)
                }
            }
        })
        observers.append(center.addObserver(forName: .init("sh.hun.debug.hideAgent"), object: nil, queue: .main) { note in
            let hide = (note.object as? String) == "yes"
            Task { @MainActor in
                store.debugHidesAgent = hide
                await store.recheckAgent()
            }
        })
        observers.append(center.addObserver(forName: .init("sh.hun.debug.resetOnboarding"), object: nil, queue: .main) { _ in
            UserDefaults.standard.set(false, forKey: HunOnboarding.completedKey)
        })
        // object: "light graphite", "light clay", "dark" or "system". Not saved.
        observers.append(center.addObserver(forName: .init("sh.hun.debug.theme"), object: nil, queue: .main) { note in
            let words = ((note.object as? String) ?? "").split(separator: " ").map(String.init)
            Task { @MainActor in
                if let palette = words.dropFirst().first.flatMap(HunPalette.init(rawValue:)) {
                    HunPalette.current = palette
                }
                (words.first.flatMap(HunTheme.init(rawValue:)) ?? .system).apply()
                hunApp.redrawColors()
            }
        })
        observers.append(center.addObserver(forName: .init("sh.hun.debug.run"), object: nil, queue: .main) { note in
            guard let path = note.object as? String else { return }
            Task { @MainActor in
                if let project = store.model.projects.first(where: { $0.path == path }) {
                    store.selectProject(project.id)
                    store.run(project)
                }
            }
        })
        observers.append(center.addObserver(forName: .init("sh.hun.debug.confetti"), object: nil, queue: .main) { _ in
            Task { @MainActor in HunConfetti.celebrate() }
        })
        observers.append(center.addObserver(forName: .init("sh.hun.debug.menu"), object: nil, queue: .main) { _ in
            Task { @MainActor in HunStatusItemController.debugToggle() }
        })
        // object: "on", "off", "play", "pause" or "skip".
        observers.append(center.addObserver(forName: .init("sh.hun.debug.music"), object: nil, queue: .main) { note in
            let word = (note.object as? String) ?? ""
            Task { @MainActor in
                let music = HunMenuMusic.shared
                switch word {
                case "on": UserDefaults.standard.set(true, forKey: HunMenuMusic.enabledKey)
                case "off":
                    UserDefaults.standard.set(false, forKey: HunMenuMusic.enabledKey)
                    music.stop()
                case "play": music.play()
                case "pause": music.pause()
                case "skip": music.skip()
                default: break
                }
            }
        })
        // object: "focus", "focus:<a stand-in project name>", "multitask" or
        // "off". Only the menu's sky changes; the daemon is not touched.
        observers.append(center.addObserver(forName: .init("sh.hun.debug.menuPreview"), object: nil, queue: .main) { note in
            let text = (note.object as? String) ?? ""
            Task { @MainActor in
                let preview = HunMenuPreview.shared
                let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
                switch parts.first {
                case "focus":
                    preview.mode = .focus
                    preview.focusName = parts.count > 1 ? parts[1] : nil
                case "multitask":
                    preview.mode = .multitask
                    preview.focusName = nil
                default:
                    preview.mode = nil
                    preview.focusName = nil
                }
            }
        })
        // What's new: "card:<version>", "notice:<version>", "since:<version>"
        // (as if updated from that version), "preview:<path to a draft
        // release JSON>", or "reset".
        observers.append(center.addObserver(forName: .init("sh.hun.debug.whatsNew"), object: nil, queue: .main) { note in
            let text = (note.object as? String) ?? ""
            Task { @MainActor in
                let whatsNew = HunWhatsNew.shared
                let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
                let version = parts.count > 1 ? parts[1] : whatsNew.currentVersion
                let release = whatsNew.releases.filter { $0.version == version }
                switch parts.first {
                case "card": whatsNew.presentation = release.isEmpty ? nil : .card(release)
                case "notice": whatsNew.presentation = release.isEmpty ? nil : .notice(release)
                case "since": whatsNew.present(whatsNew.releases(after: version))
                case "reset": UserDefaults.standard.removeObject(forKey: HunWhatsNew.lastSeenKey)
                case "preview":
                    // A draft entry for a release not in the changelog yet.
                    if let data = FileManager.default.contents(atPath: version),
                       let draft = try? JSONDecoder().decode(HunRelease.self, from: data) {
                        whatsNew.presentation = .card([draft])
                    }
                default: whatsNew.dismiss()
                }
            }
        })
        // object: a folder path. Force-stops that project's pending action,
        // as clicking its spinner does once it offers to.
        observers.append(center.addObserver(forName: .init("sh.hun.debug.forceStop"), object: nil, queue: .main) { note in
            guard let path = note.object as? String else { return }
            Task { @MainActor in
                if let project = store.model.projects.first(where: { $0.path == path }) {
                    store.forceStopAction(for: project)?()
                }
            }
        })
        // Dashboard windows: object "open" or "close" (closes them all).
        observers.append(center.addObserver(forName: .init("sh.hun.debug.dashboard"), object: nil, queue: .main) { note in
            let word = (note.object as? String) ?? ""
            Task { @MainActor in
                if word == "close" {
                    for window in NSApp.windows where window.canBecomeMain && !(window is NSPanel) { window.close() }
                } else {
                    hunApp.openDashboard()
                }
            }
        })
        // object: "hide" or "show": the hide-Dock-icon setting.
        observers.append(center.addObserver(forName: .init("sh.hun.debug.dock"), object: nil, queue: .main) { note in
            let hide = (note.object as? String) == "hide"
            Task { @MainActor in
                UserDefaults.standard.set(hide, forKey: HunAppBehavior.hideDockKey)
                HunAppBehavior.applyDockSetting()
            }
        })
        // object: "key=value", a string preference set from inside the app.
        observers.append(center.addObserver(forName: .init("sh.hun.debug.setDefault"), object: nil, queue: .main) { note in
            guard let text = note.object as? String, let split = text.firstIndex(of: "=") else { return }
            UserDefaults.standard.set(String(text[text.index(after: split)...]), forKey: String(text[..<split]))
        })
        // object: "new" or "beta".
        observers.append(center.addObserver(forName: .init("sh.hun.debug.rehearse"), object: nil, queue: .main) { note in
            let beta = (note.object as? String) == "beta"
            Task { @MainActor in HunOnboarding.rehearse(asBeta: beta, license: license) }
        })
        observers.append(center.addObserver(forName: .init("sh.hun.debug.activate"), object: nil, queue: .main) { note in
            guard let key = note.object as? String else { return }
            Task { @MainActor in await license.activate(key) }
        })
        // object: "<folder path>\n<service name>"
        observers.append(center.addObserver(forName: .init("sh.hun.debug.runService"), object: nil, queue: .main) { note in
            guard let text = note.object as? String, let split = text.firstIndex(of: "\n") else { return }
            let path = String(text[..<split]), name = String(text[text.index(after: split)...])
            Task { @MainActor in
                await store.refresh(force: true)
                guard let project = store.model.projects.first(where: { $0.path == path }),
                      let service = project.services.first(where: { $0.name == name })
                else { return }
                store.run(service, in: project)
            }
        })
        // Pretends this Mac's license was just deactivated (nothing real changes).
        observers.append(center.addObserver(forName: .init("sh.hun.debug.loseLicense"), object: nil, queue: .main) { _ in
            Task { @MainActor in license.startRehearsal() }
        })
        observers.append(center.addObserver(forName: .init("sh.hun.debug.finishOnboarding"), object: nil, queue: .main) { _ in
            UserDefaults.standard.set(true, forKey: HunOnboarding.completedKey)
            Task { @MainActor in
                HunOnboardingBackdrop.hide()
                HunOnboarding.rehearsingAsNewUser = false
                license.endRehearsal()
            }
        })
        observers.append(center.addObserver(forName: .init("sh.hun.debug.snapshot"), object: nil, queue: .main) { note in
            guard let path = note.object as? String else { return }
            Task { @MainActor in snapshot(to: URL(fileURLWithPath: path)) }
        })
    }

    @MainActor
    private static func snapshot(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif