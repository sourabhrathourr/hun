import AppKit
import Observation
import SwiftUI

/// Hun's menu bar item. It's an AppKit status item rather than SwiftUI's
/// MenuBarExtra so it can carry an autosave name: macOS then remembers where
/// the user ⌘-dragged it, across launches and updates.
@MainActor
final class HunStatusItemController: NSObject {
    private static var installed: HunStatusItemController?

    /// Creates the menu bar item once, after the app has started.
    static func install(store: HunStore, license: HunLicenseManager) {
        guard installed == nil else { return }
        installed = HunStatusItemController(store: store, license: license)
    }

    private let store: HunStore
    private let statusItem: NSStatusItem
    private let panel: HunMenuPanel
    private let hosting: NSHostingView<AnyView>
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    /// When the panel was last dismissed by a click elsewhere or a focus
    /// change, so the click on the icon that caused it doesn't reopen it.
    private var lastDismissal = Date.distantPast
    /// True while the panel fades out.
    private var isClosing = false

    private init(store: HunStore, license: HunLicenseManager) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // The position macOS saves is keyed by this name.
        statusItem.autosaveName = "Hun"

        panel = HunMenuPanel()
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        super.init()

        // Report the view's natural size without forcing the window's.
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.rootView = AnyView(
            HunLicenseMenuBarView()
                .environment(store)
                .environment(license)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { proxy in
                        Color.clear.onChange(of: proxy.size, initial: true) { _, size in
                            self.resizePanel(to: size)
                        }
                    }
                )
        )
        panel.setContent(hosting)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        updateIcon()
    }

    // MARK: Icon

    /// The switch is on while any project runs; re-armed after each change.
    private func updateIcon() {
        let isOn = withObservationTracking {
            store.model.projects.contains { $0.status == .running || $0.status == .starting }
        } onChange: {
            // The controller lives as long as the app.
            Task { @MainActor in HunStatusItemController.installed?.updateIcon() }
        }
        statusItem.button?.image = HunMenuBarGlyph.image(on: isOn)
        statusItem.button?.setAccessibilityLabel(isOn ? "Hun, projects running" : "Hun")
    }

    // MARK: Panel

    @objc private func toggle() {
        // Act on the press only; a release of the same click must not flip
        // the panel back.
        if let type = NSApp.currentEvent?.type, type == .leftMouseUp || type == .rightMouseUp {
            return
        }
        if isOpen {
            close()
        } else if Date().timeIntervalSince(lastDismissal) > 0.3 {
            // The click that dismissed the panel (as an outside click or a
            // focus change) is this same click on the icon: it stays closed.
            open()
        }
    }

    private var isOpen: Bool { panel.isVisible && !isClosing }

    private func open() {
        guard let button = statusItem.button else { return }
        isClosing = false
        // Replaces a fade-out still in flight.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.setFrame(frame(for: hosting.fittingSize, under: button), display: false)
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        startDismissMonitoring()
        Task { await store.refresh(force: true) }
    }

    /// Hides the panel with a short fade, like a menu. `dismissed` marks a
    /// close that came from a click elsewhere or a focus change.
    private func close(dismissed: Bool = false) {
        guard isOpen else { return }
        if dismissed { lastDismissal = Date() }
        isClosing = true
        statusItem.button?.highlight(false)
        stopDismissMonitoring()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Reopened during the fade: leave it up.
                guard let self, self.isClosing else { return }
                self.isClosing = false
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    /// Follows the content's height, keeping the top edge under the menu bar.
    private func resizePanel(to size: CGSize) {
        guard isOpen, let button = statusItem.button, size.height > 0 else { return }
        panel.setFrame(frame(for: size, under: button), display: true)
    }

    /// Left edge lined up with the icon's, like a system menu, a few points
    /// below the menu bar, and kept on screen with a small margin.
    private func frame(for size: CGSize, under button: NSStatusBarButton) -> NSRect {
        let width = ceil(size.width), height = ceil(size.height)
        guard let window = button.window else {
            return NSRect(x: 0, y: 0, width: width, height: height)
        }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? anchor
        let margin: CGFloat = 8
        var x = anchor.minX.rounded()
        x = min(max(x, screen.minX + margin), screen.maxX - width - margin)
        let y = (anchor.minY - 5 - height).rounded()
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func startDismissMonitoring() {
        stopDismissMonitoring()
        // A click in another app or on the desktop.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close(dismissed: true) }
        }) {
            monitors.append(monitor)
        }
        // Esc while the panel is focused.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53, self?.panel.isKeyWindow == true else { return event }
            self?.close()
            return nil
        }) {
            monitors.append(monitor)
        }
        // A click in one of Hun's own windows, or Open Hun.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(dismissed: true) }
        })
    }

    private func stopDismissMonitoring() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}

/// A borderless, rounded panel like a menu bar extra's window: no arrow, and
/// it can take keyboard focus for the project search without activating Hun.
final class HunMenuPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }

    func setContent(_ view: NSView) {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentView = container
        updateBorder()
    }

    override func becomeKey() {
        super.becomeKey()
        updateBorder()
    }

    /// A hairline edge in the current appearance, like the system's panels.
    private func updateBorder() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            contentView?.layer?.borderColor = NSColor(AppTheme.dividerStrong).cgColor
        }
    }
}
