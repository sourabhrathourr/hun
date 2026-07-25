import AppKit
import Foundation
import Observation

enum HunTerminalSessionState: Equatable {
    case idle
    case starting
    case running
    case exited(Int32?)
    case failed(String)

    var isRunning: Bool {
        self == .running
    }

    var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .starting:
            return "Starting…"
        case .running:
            return "Running"
        case .exited(let exitCode):
            return exitCode.map { "Shell exited with code \($0)" } ?? "Shell exited"
        case .failed(let message):
            return message
        }
    }
}

struct HunTerminalProjectContext: Equatable {
    let id: String
    let name: String
    let rootPath: String
}

@MainActor
@Observable
final class HunTerminalSession: HunTerminalEngineDelegate {
    typealias EnvironmentProvider = @Sendable () async -> [String: String]

    let projectID: String
    private(set) var projectName: String
    private(set) var rootPath: String
    private(set) var state: HunTerminalSessionState = .idle
    private(set) var currentDirectory: String
    private(set) var shellName: String

    @ObservationIgnored private let engine: any HunTerminalEngine
    @ObservationIgnored private let environmentProvider: EnvironmentProvider
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var intentionallyTerminated = false

    init(
        project: HunTerminalProjectContext,
        engine: any HunTerminalEngine,
        environmentProvider: @escaping EnvironmentProvider
    ) {
        projectID = project.id
        projectName = project.name
        rootPath = project.rootPath
        currentDirectory = project.rootPath
        self.shellName = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        ).lastPathComponent
        self.engine = engine
        self.environmentProvider = environmentProvider
        engine.delegate = self
    }

    var view: NSView {
        engine.view
    }

    func update(project: HunTerminalProjectContext) {
        projectName = project.name
        guard state == .idle else { return }
        rootPath = project.rootPath
        currentDirectory = project.rootPath
    }

    func startIfNeeded() {
        guard startTask == nil, !engine.isRunning else {
            if engine.isRunning {
                state = .running
            }
            return
        }

        intentionallyTerminated = false
        let shouldReset: Bool
        switch state {
        case .exited, .failed:
            shouldReset = true
        default:
            shouldReset = false
        }
        state = .starting
        let rootPath = rootPath
        startTask = Task { [weak self] in
            guard let self else { return }
            let environment = await environmentProvider()
            guard !Task.isCancelled else { return }

            let configuration = HunTerminalLaunchConfiguration.projectShell(
                rootPath: rootPath,
                environment: environment
            )
            shellName = URL(fileURLWithPath: configuration.executable).lastPathComponent
            if shouldReset {
                engine.reset()
            }
            engine.start(configuration: configuration)
            startTask = nil

            if engine.isRunning {
                state = .running
                currentDirectory = rootPath
            } else {
                state = .failed("The shell could not be started.")
            }
        }
    }

    func restartAfterExit() {
        guard !engine.isRunning else { return }
        state = .idle
        engine.reset()
        startIfNeeded()
    }

    func terminate() {
        intentionallyTerminated = true
        startTask?.cancel()
        startTask = nil
        engine.terminate()
        state = .idle
    }

    func focus() {
        engine.focus()
    }

    func clear() {
        guard engine.isRunning else { return }
        engine.clear()
    }

    func terminalEngine(_ engine: any HunTerminalEngine, didUpdateCurrentDirectory directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        currentDirectory = Self.normalizedDirectory(directory)
    }

    func terminalEngine(_ engine: any HunTerminalEngine, didTerminateWithExitCode exitCode: Int32?) {
        startTask = nil
        if intentionallyTerminated {
            state = .idle
        } else {
            state = .exited(exitCode)
        }
    }

    static func normalizedDirectory(_ directory: String) -> String {
        guard directory.hasPrefix("file://"),
              let url = URL(string: directory),
              url.isFileURL
        else {
            return directory
        }
        return url.path
    }
}

enum HunTerminalPanelMetrics {
    static let defaultHeight: CGFloat = 280
    static let minimumHeight: CGFloat = 164
    static let minimumWorkspaceHeight: CGFloat = 170
    static let accessibilityAdjustment: CGFloat = 24

    static func clamp(_ requestedHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let maximum = max(minimumHeight, availableHeight - minimumWorkspaceHeight)
        return min(max(requestedHeight, minimumHeight), maximum)
    }
}

@MainActor
@Observable
final class HunTerminalController {
    typealias EngineFactory = @MainActor () -> any HunTerminalEngine

    private(set) var isPresented = false
    private(set) var activeSession: HunTerminalSession?
    var panelHeight: CGFloat {
        didSet {
            guard panelHeight != oldValue else { return }
            defaults?.set(Double(panelHeight), forKey: PreferenceKey.panelHeight)
        }
    }

    @ObservationIgnored private let engineFactory: EngineFactory
    @ObservationIgnored private let environmentProvider: HunTerminalSession.EnvironmentProvider
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var sessions: [String: HunTerminalSession] = [:]
    @ObservationIgnored private var recentProjectIDs: [String] = []

    init(
        engineFactory: @escaping EngineFactory = { SwiftTermTerminalEngine() },
        environmentProvider: @escaping HunTerminalSession.EnvironmentProvider = {
            await HunShellEnvironment.loginEnvironment()
        },
        defaults: UserDefaults? = .standard
    ) {
        self.engineFactory = engineFactory
        self.environmentProvider = environmentProvider
        self.defaults = defaults

        let savedHeight = defaults?.double(forKey: PreferenceKey.panelHeight) ?? 0
        panelHeight = savedHeight > 0 ? CGFloat(savedHeight) : HunTerminalPanelMetrics.defaultHeight
    }

    func session(for project: HunTerminalProjectContext) -> HunTerminalSession {
        if let session = sessions[project.id] {
            session.update(project: project)
            markRecentlyUsed(project.id)
            return session
        }

        let session = HunTerminalSession(
            project: project,
            engine: engineFactory(),
            environmentProvider: environmentProvider
        )
        sessions[project.id] = session
        markRecentlyUsed(project.id)
        evictOldSessionsIfNeeded()
        return session
    }

    @discardableResult
    func show(project: HunTerminalProjectContext) -> HunTerminalSession {
        let session = session(for: project)
        activeSession = session
        isPresented = true
        session.startIfNeeded()
        return session
    }

    func hide() {
        isPresented = false
    }

    func clearActiveTerminal() {
        guard isPresented else { return }
        activeSession?.clear()
    }

    func toggle(project: HunTerminalProjectContext) {
        if isPresented {
            hide()
        } else {
            _ = show(project: project)
        }
    }

    func projectDidChange(_ project: HunTerminalProjectContext) {
        guard isPresented else { return }
        _ = show(project: project)
    }

    func pruneSessions(validProjectIDs: Set<String>) {
        for projectID in Set(sessions.keys).subtracting(validProjectIDs) {
            sessions.removeValue(forKey: projectID)?.terminate()
        }
        recentProjectIDs.removeAll { !validProjectIDs.contains($0) }
        if let activeSession, !validProjectIDs.contains(activeSession.projectID) {
            self.activeSession = nil
            isPresented = false
        }
    }

    func shutdown() {
        for session in sessions.values {
            session.terminate()
        }
        sessions.removeAll()
        recentProjectIDs.removeAll()
        activeSession = nil
        isPresented = false
    }

    private func markRecentlyUsed(_ projectID: String) {
        recentProjectIDs.removeAll { $0 == projectID }
        recentProjectIDs.append(projectID)
    }

    private func evictOldSessionsIfNeeded() {
        while sessions.count > Self.maximumRetainedSessionCount,
              let projectID = recentProjectIDs.first
        {
            recentProjectIDs.removeFirst()
            sessions.removeValue(forKey: projectID)?.terminate()
        }
    }

    private enum PreferenceKey {
        static let panelHeight = "hun.dashboard.terminalPanelHeight"
    }

    static let maximumRetainedSessionCount = 8
}
