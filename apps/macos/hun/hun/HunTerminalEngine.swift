import AppKit
import Foundation
import SwiftUI
@preconcurrency import SwiftTerm

struct HunTerminalLaunchConfiguration: Equatable {
    let executable: String
    let execName: String
    let currentDirectory: String
    let environment: [String]

    static func projectShell(
        rootPath: String,
        environment sourceEnvironment: [String: String]
    ) -> HunTerminalLaunchConfiguration {
        let requestedShell = sourceEnvironment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let executable: String
        if let requestedShell,
           !requestedShell.isEmpty,
           FileManager.default.isExecutableFile(atPath: requestedShell)
        {
            executable = requestedShell
        } else {
            executable = "/bin/zsh"
        }

        var environment = sourceEnvironment
        environment["SHELL"] = executable
        environment["PWD"] = rootPath
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Hun"
        environment["HUN_PROJECT_ROOT"] = rootPath
        environment.removeValue(forKey: "TERM_SESSION_ID")

        return HunTerminalLaunchConfiguration(
            executable: executable,
            execName: "-" + URL(fileURLWithPath: executable).lastPathComponent,
            currentDirectory: rootPath,
            environment: environment
                .map { "\($0.key)=\($0.value)" }
                .sorted()
        )
    }
}

@MainActor
protocol HunTerminalEngineDelegate: AnyObject {
    func terminalEngine(_ engine: any HunTerminalEngine, didUpdateCurrentDirectory directory: String?)
    func terminalEngine(_ engine: any HunTerminalEngine, didTerminateWithExitCode exitCode: Int32?)
}

@MainActor
protocol HunTerminalEngine: AnyObject {
    var view: NSView { get }
    var isRunning: Bool { get }
    var delegate: (any HunTerminalEngineDelegate)? { get set }

    func start(configuration: HunTerminalLaunchConfiguration)
    func clear()
    func reset()
    func terminate()
    func focus()
    func updateAppearance()
}

extension HunTerminalEngine {
    func updateAppearance() {}
}

@MainActor
final class SwiftTermTerminalEngine: NSObject, HunTerminalEngine, @preconcurrency LocalProcessTerminalViewDelegate {
    weak var delegate: (any HunTerminalEngineDelegate)?

    private let terminalView: LocalProcessTerminalView
    private var scrollVisibilityController: HunTerminalScrollVisibilityController?

    override init() {
        terminalView = LocalProcessTerminalView(frame: .zero)
        super.init()
        configureTerminal()
        scrollVisibilityController = HunTerminalScrollVisibilityController(terminalView: terminalView)
    }

    var view: NSView {
        terminalView
    }

    var isRunning: Bool {
        terminalView.process.running
    }

    func start(configuration: HunTerminalLaunchConfiguration) {
        terminalView.startProcess(
            executable: configuration.executable,
            environment: configuration.environment,
            execName: configuration.execName,
            currentDirectory: configuration.currentDirectory
        )
    }

    func clear() {
        terminalView.send([0x0C])
        focus()
    }

    func reset() {
        terminalView.terminal.resetToInitialState()
    }

    func terminate() {
        guard terminalView.process.running else { return }
        terminalView.terminate()
    }

    func focus() {
        guard let window = terminalView.window else { return }
        window.makeFirstResponder(terminalView)
        scrollVisibilityController?.refresh()
    }

    func updateAppearance() {
        applyAppearance()
        scrollVisibilityController?.refresh()
    }

    private func configureTerminal() {
        terminalView.processDelegate = self
        terminalView.font = Self.terminalFont(size: 12)
        applyAppearance()
        terminalView.optionAsMetaKey = true
        terminalView.allowMouseReporting = true
        terminalView.terminal.setCursorStyle(.steadyBar)
        terminalView.setAccessibilityLabel("Project terminal")
    }

    private func applyAppearance() {
        let isDark = terminalView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        terminalView.installColors(isDark ? HunTerminalPalette.dark : HunTerminalPalette.light)
        terminalView.effectiveAppearance.performAsCurrentDrawingAppearance {
            let background = NSColor(AppTheme.appBackground)
            terminalView.nativeBackgroundColor = background
            terminalView.nativeForegroundColor = NSColor(AppTheme.logText)
            terminalView.layer?.backgroundColor = (background.usingColorSpace(.deviceRGB) ?? background).cgColor
            terminalView.caretColor = NSColor(AppTheme.accent)
            terminalView.selectedTextBackgroundColor = NSColor(AppTheme.accent)
                .withAlphaComponent(0.36)
        }
        terminalView.needsDisplay = true
    }

    /// The system monospaced font, falling back to an installed Nerd Font for
    /// icon glyphs (eza, starship, oh-my-zsh themes) that it doesn't have, so
    /// those render as icons instead of missing-glyph boxes.
    private static func terminalFont(size: CGFloat) -> NSFont {
        let base = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let families = NSFontManager.shared.availableFontFamilies
        let preferred = ["Symbols Nerd Font Mono", "Symbols Nerd Font"]
        let nerdFamily = preferred.first(where: families.contains)
            ?? families.first { $0.contains("Nerd Font") || $0.hasSuffix(" NF") || $0.hasSuffix(" NFM") }
        guard let nerdFamily,
              let fallback = NSFontManager.shared.font(withFamily: nerdFamily, traits: [], weight: 5, size: size)
        else {
            return base
        }
        let descriptor = base.fontDescriptor.addingAttributes([.cascadeList: [fallback.fontDescriptor]])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        delegate?.terminalEngine(self, didUpdateCurrentDirectory: directory)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        delegate?.terminalEngine(self, didTerminateWithExitCode: exitCode)
    }
}

private final class HunTerminalScrollVisibilityController: NSResponder {
    private weak var terminalView: LocalProcessTerminalView?
    private weak var scroller: NSScroller?
    private let visibilityController = HunScrollVisibilityController()

    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
        scroller = terminalView.subviews.first { $0 is NSScroller } as? NSScroller
        super.init()

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        terminalView.addTrackingArea(trackingArea)
        styleScroller()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        styleScroller()
        visibilityController.setPointerInside(true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        visibilityController.setPointerInside(false)
        super.mouseExited(with: event)
    }

    func refresh() {
        styleScroller()
        visibilityController.refresh()
    }

    private func styleScroller() {
        if scroller == nil {
            scroller = terminalView?.subviews.first { $0 is NSScroller } as? NSScroller
        }
        guard let scroller else { return }
        scroller.scrollerStyle = .overlay
        scroller.controlSize = .mini
        scroller.knobStyle = terminalView?.effectiveAppearance.bestMatch(
            from: [.aqua, .darkAqua]
        ) == .darkAqua ? .light : .dark
        if let terminalView {
            visibilityController.install(
                scroller: scroller,
                hostView: terminalView,
                focusView: terminalView
            )
        }
    }
}

/// A softened ANSI palette that matches the app instead of stock xterm's
/// saturated colors. Each hue stays distinct; light mode uses deeper tones.
enum HunTerminalPalette {
    static let dark: [SwiftTerm.Color] = [
        0x3A3A3C, 0xE5736F, 0x8DC486, 0xD9C27C, 0x7EA8E1, 0xB79CDF, 0x7CC0C2, 0xC9C9C7,
        0x6E6E73, 0xF08C88, 0xA5D59D, 0xE6D394, 0x97BCEE, 0xCAB3EC, 0x96D2D3, 0xEDEDEB,
    ].map(color)

    static let light: [SwiftTerm.Color] = [
        0x3A3A3C, 0xBF4540, 0x3F8A3B, 0x94760F, 0x2F6AB0, 0x8854B0, 0x2B878B, 0x6E6E73,
        0x8E8E93, 0xCF5650, 0x4F9A4A, 0xA8861E, 0x3C7BC3, 0x9965C1, 0x3A979B, 0x1C1C1E,
    ].map(color)

    private static func color(_ hex: Int) -> SwiftTerm.Color {
        // SwiftTerm takes 16-bit channels; 0x101 maps 0xFF to 0xFFFF.
        SwiftTerm.Color(
            red: UInt16((hex >> 16) & 0xFF) * 0x101,
            green: UInt16((hex >> 8) & 0xFF) * 0x101,
            blue: UInt16(hex & 0xFF) * 0x101
        )
    }
}
