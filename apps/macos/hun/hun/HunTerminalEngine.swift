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

    private func configureTerminal() {
        terminalView.processDelegate = self
        terminalView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalView.nativeBackgroundColor = NSColor(AppTheme.appBackground)
        terminalView.nativeForegroundColor = NSColor(AppTheme.logText)
        terminalView.layer?.backgroundColor = NSColor(AppTheme.appBackground).cgColor
        terminalView.caretColor = NSColor(AppTheme.accent)
        terminalView.selectedTextBackgroundColor = NSColor(AppTheme.accent).withAlphaComponent(0.36)
        terminalView.optionAsMetaKey = true
        terminalView.allowMouseReporting = true
        terminalView.terminal.setCursorStyle(.steadyBar)
        terminalView.setAccessibilityLabel("Project terminal")
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
        scroller.knobStyle = .light
        if let terminalView {
            visibilityController.install(
                scroller: scroller,
                hostView: terminalView,
                focusView: terminalView
            )
        }
    }
}
