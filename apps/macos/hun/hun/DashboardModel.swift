import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class HunStore {
    var model = HunDashboardModel.empty
    var globalMode: HunMode = .focus {
        didSet {
            guard oldValue != globalMode, !isApplyingSnapshot else { return }
            let mode = globalMode
            let preferredProject = mode == .focus ? pendingModePreferredProjectID : nil
            modeChangeGeneration += 1
            let generation = modeChangeGeneration
            let previousTask = modeChangeTask
            modeChangeTask = Task { [weak self] in
                await previousTask?.value
                guard let self, generation == self.modeChangeGeneration else { return }
                await self.setMode(mode, preferredProject: preferredProject)
            }
        }
    }
    var selectedProjectID: HunProject.ID? {
        didSet {
            guard oldValue != selectedProjectID else { return }
            persistNavigationState()
            guard !isApplyingSnapshot else { return }
            ensureSelectedService()
            scheduleLogReload()
        }
    }
    var selectedServiceID: HunService.ID? {
        didSet {
            guard oldValue != selectedServiceID else { return }
            persistNavigationState()
            guard !isApplyingSnapshot else { return }
            scheduleLogReload()
        }
    }
    var selectedLogScope: LogScope = .service {
        didSet {
            guard oldValue != selectedLogScope else { return }
            persistNavigationState()
            guard !isApplyingSnapshot else { return }
            scheduleLogReload()
        }
    }
    var openTabIDs: [HunProject.ID] = [] {
        didSet {
            guard oldValue != openTabIDs else { return }
            persistNavigationState()
        }
    }
    var isConnected = false
    var isRefreshing = false
    var isAddingProject = false
    var pendingProjectReview: HunProjectInitReview?
    var lastError: String?
    var pendingActions: Set<HunActionKey> = []
    var daemonInfo: HunDaemonInfo?
    var daemonSettingsError: String?
    var isLoadingDaemonInfo = false
    var isRestartingDaemon = false

    private let client: HunDaemonClientProtocol
    private let supervisor: HunDaemonSupervisorProtocol
    private let projectInitializer: HunProjectInitializing
    private let navigationDefaults: UserDefaults?
    private var pollTask: Task<Void, Never>?
    private var logSubscription: HunLogSubscribing?
    private var logsByProject: [HunProject.ID: [HunLogLine]] = [:]
    private var isApplyingSnapshot = false
    private var pendingModePreferredProjectID: HunProject.ID?
    private var modeChangeTask: Task<Void, Never>?
    private var modeChangeGeneration = 0

    init(
        client: HunDaemonClientProtocol = HunDaemonClient(),
        supervisor: HunDaemonSupervisorProtocol = HunDaemonSupervisor(),
        projectInitializer: HunProjectInitializing = HunProjectInitializer(),
        navigationDefaults: UserDefaults? = nil,
        startAutomatically: Bool = true
    ) {
        self.client = client
        self.supervisor = supervisor
        self.projectInitializer = projectInitializer
        if let navigationDefaults {
            selectedProjectID = navigationDefaults.string(forKey: NavigationPreferenceKey.selectedProject)
            selectedServiceID = navigationDefaults.string(forKey: NavigationPreferenceKey.selectedService)
            openTabIDs = navigationDefaults.stringArray(forKey: NavigationPreferenceKey.openTabs) ?? []
            selectedLogScope = navigationDefaults.string(forKey: NavigationPreferenceKey.logScope) == "combined"
                ? .combined
                : .service
        }
        self.navigationDefaults = navigationDefaults
        if startAutomatically {
            Task { await start() }
        }
    }

    var focusedProject: HunProject? {
        model.projects.first { $0.isActive }
    }

    var runningProjects: [HunProject] {
        model.projects.filter { $0.status == .running }
    }

    func changeMode(_ mode: HunMode, preferredProject: HunProject.ID?) {
        guard mode != globalMode else { return }
        pendingModePreferredProjectID = runningProjectID(preferredProject)
        globalMode = mode
        pendingModePreferredProjectID = nil
    }

    private func runningProjectID(_ requestedProject: HunProject.ID?) -> HunProject.ID? {
        guard let requestedProject,
              model.projects.contains(where: { $0.id == requestedProject && $0.status == .running })
        else {
            return nil
        }
        return requestedProject
    }

    func projectAction(for project: HunProject) -> HunActionKind? {
        let order: [HunActionKind] = [.startProject, .restartProject, .stopProject]
        return order.first { pendingActions.contains(.project(project.id, $0)) }
    }

    func serviceAction(for service: HunService, in project: HunProject) -> HunActionKind? {
        let order: [HunActionKind] = [.startService, .restartService, .stopService, .removeService]
        return order.first { pendingActions.contains(.service(project.id, service.id, $0)) }
    }

    func project(id: String) -> HunProject? {
        model.projects.first { $0.id == id }
    }

    func start() async {
        installAgentSkillIfPossible()
        await refresh(force: true)
        startPolling()
    }

    func refreshNow() {
        Task { await refresh(force: true) }
    }

    func clearLastError() {
        lastError = nil
    }

    func refreshDaemonInfo() async {
        guard !isLoadingDaemonInfo else { return }
        isLoadingDaemonInfo = true
        defer { isLoadingDaemonInfo = false }
        do {
            daemonInfo = try await client.daemonInfo()
            daemonSettingsError = nil
        } catch {
            daemonInfo = nil
            daemonSettingsError = error.localizedDescription
        }
    }

    func restartDaemon() async {
        guard !isRestartingDaemon else { return }
        isRestartingDaemon = true
        defer { isRestartingDaemon = false }
        do {
            try await supervisor.restartDaemon()
            daemonInfo = try await client.daemonInfo()
            daemonSettingsError = nil
            isConnected = true
            await refresh(force: true)
        } catch {
            daemonInfo = nil
            daemonSettingsError = error.localizedDescription
            isConnected = false
        }
    }

    func addProject(at url: URL) async {
        guard !isAddingProject else { return }
        HunTrace.addProject("flow start path=\(url.path)")
        isAddingProject = true
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
            isAddingProject = false
        }

        do {
            pendingProjectReview = try await projectInitializer.initializeProject(at: url)
            HunTrace.addProject("flow review_ready path=\(url.path) name=\(pendingProjectReview?.name ?? "")")
            lastError = nil
        } catch {
            HunTrace.addProject("flow failed path=\(url.path) error=\(HunTrace.compact(error.localizedDescription))")
            lastError = error.localizedDescription
        }
    }

    func acceptPendingProject() async {
        guard let review = pendingProjectReview, !isAddingProject else { return }
        HunTrace.addProject("accept start path=\(review.path) name=\(review.name)")
        isAddingProject = true
        defer { isAddingProject = false }

        do {
            try await supervisor.ensureDaemon()
            try await client.registerProject(path: review.path)
            HunTrace.addProject("accept registered path=\(review.path) name=\(review.name)")
            await refresh(force: true)
        } catch {
            HunTrace.addProject("accept failed path=\(review.path) error=\(HunTrace.compact(error.localizedDescription))")
            lastError = error.localizedDescription
            return
        }

        if isConnected {
            pendingProjectReview = nil
            selectProject(at: URL(fileURLWithPath: review.path))
            HunTrace.addProject("accept complete path=\(review.path) selected=\(selectedProjectID ?? "")")
        } else {
            HunTrace.addProject("accept refresh_failed path=\(review.path) error=\(HunTrace.compact(lastError ?? "transient daemon error"))")
        }
    }

    func discardPendingProject() {
        guard let review = pendingProjectReview else { return }
        HunTrace.addProject("discard path=\(review.path) created_config=\(review.createdConfig)")
        if review.createdConfig {
            do {
                try FileManager.default.removeItem(atPath: review.configPath)
            } catch {
                HunTrace.addProject("discard failed path=\(review.path) error=\(HunTrace.compact(error.localizedDescription))")
                lastError = "Could not remove generated .hun.yml: \(error.localizedDescription)"
                return
            }
        }
        pendingProjectReview = nil
    }

    func openConfig(for project: HunProject) {
        let configURL = URL(fileURLWithPath: project.path).appendingPathComponent(".hun.yml")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            lastError = "\(project.name) does not have a .hun.yml file."
            return
        }

        if !NSWorkspace.shared.open(configURL) {
            lastError = "Could not open \(configURL.path)."
        }
    }

    func copyAgentPrompt(for project: HunProject) {
        installAgentSkillIfPossible()
        let prompt = HunAgentPromptBuilder.prompt(for: project)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
    }

    func chooseLogo(for project: HunProject) {
        let panel = NSOpenPanel()
        panel.title = "Choose Logo for \(project.name)"
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["png", "jpg", "jpeg", "webp", "gif", "icns", "ico", "svg"]
            .compactMap { UTType(filenameExtension: $0) }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        perform { [self] in
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try await self.client.setProjectIcon(project.id, path: url.path)
        }
    }

    func clearLogo(for project: HunProject) {
        perform { [self] in
            try await self.client.clearProjectIcon(project.id)
        }
    }

    func copyAgentPrompt(for review: HunProjectInitReview) {
        installAgentSkillIfPossible()
        let prompt = HunAgentPromptBuilder.prompt(for: review)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
    }

    func openConfig(for review: HunProjectInitReview) {
        let configURL = URL(fileURLWithPath: review.configPath)
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            lastError = "\(review.name) does not have a .hun.yml file."
            return
        }

        if !NSWorkspace.shared.open(configURL) {
            lastError = "Could not open \(configURL.path)."
        }
    }

    private func installAgentSkillIfPossible() {
        do {
            _ = try HunAgentSkillInstaller.installBundledSkillGlobally()
        } catch HunAgentSkillInstallError.missingBundledSkill {
            return
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func selectProject(at url: URL) {
        let path = normalizedPath(url.path)
        guard let project = model.projects.first(where: { normalizedPath($0.path) == path }) else { return }
        selectProject(project.id)
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let priorLogKey = currentLogKey
        do {
            try await supervisor.ensureDaemon()
            let snapshot = try await client.snapshot(force: force)
            apply(snapshot)
            isConnected = true
            lastError = nil
            if force || priorLogKey != currentLogKey {
                await reloadLogs(resubscribe: true)
            }
        } catch {
            isConnected = false
            if !isTransientDaemonError(error) {
                lastError = error.localizedDescription
            }
        }
        isRefreshing = false
    }

    func selectProject(_ id: HunProject.ID) {
        if !openTabIDs.contains(id) {
            openTabIDs.append(id)
        }
        selectedProjectID = id
    }

    func closeTab(_ id: HunProject.ID) {
        guard openTabIDs.count > 1 else { return }
        let idx = openTabIDs.firstIndex(of: id)
        openTabIDs.removeAll { $0 == id }
        if selectedProjectID == id, let i = idx {
            selectedProjectID = openTabIDs[min(i, openTabIDs.count - 1)]
        }
    }

    func focus(_ project: HunProject) {
        selectProject(project.id)
        perform(key: .project(project.id, .startProject)) { [self] in
            try await self.client.startProject(project.id, mode: .exclusive)
        }
    }

    func run(_ project: HunProject) {
        perform(key: .project(project.id, .startProject)) { [self] in
            try await self.client.startProject(project.id, mode: .parallel)
        }
    }

    func stop(_ project: HunProject) {
        perform(key: .project(project.id, .stopProject)) { [self] in
            try await self.client.stopProject(project.id)
        }
    }

    func restart(_ project: HunProject) {
        perform(key: .project(project.id, .restartProject)) { [self] in
            try await self.client.restartProject(project.id)
        }
    }

    func restart(_ service: HunService, in project: HunProject) {
        perform(key: .service(project.id, service.id, .restartService)) { [self] in
            try await self.client.restartService(project.id, service: service.id)
        }
    }

    func run(_ service: HunService, in project: HunProject) {
        perform(key: .service(project.id, service.id, .startService)) { [self] in
            try await self.client.startService(project.id, service: service.id, mode: self.globalMode.daemonMode)
        }
    }

    func stop(_ service: HunService, in project: HunProject) {
        perform(key: .service(project.id, service.id, .stopService)) { [self] in
            try await self.client.stopService(project.id, service: service.id)
        }
    }

    func remove(_ service: HunService, from project: HunProject) {
        perform(key: .service(project.id, service.id, .removeService)) { [self] in
            try await self.client.removeService(project.id, service: service.id)
        }
    }

    private func setMode(_ mode: HunMode, preferredProject: String?) async {
        do {
            try await client.setMode(mode, preferredProject: preferredProject)
            await refresh(force: false)
        } catch {
            if !isTransientDaemonError(error) {
                lastError = error.localizedDescription
            }
        }
    }

    private func perform(key: HunActionKey? = nil, _ operation: @escaping () async throws -> Void) {
        Task {
            if let key {
                pendingActions.insert(key)
            }
            defer {
                if let key {
                    pendingActions.remove(key)
                }
            }
            do {
                try await operation()
                lastError = nil
                await refresh(force: true)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func isTransientDaemonError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("connection closed") ||
            message.contains("no such file or directory") ||
            message.contains("connection refused") ||
            message.contains("broken pipe") ||
            message.contains("socket is not connected") ||
            message.contains("lifecycle operation in progress")
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                guard await self?.pendingProjectReview == nil else { continue }
                await self?.refresh(force: false)
            }
        }
    }

    private func apply(_ snapshot: HunDaemonSnapshot) {
        isApplyingSnapshot = true
        defer { isApplyingSnapshot = false }

        globalMode = HunMode(snapshot.mode)

        let projects = snapshot.projects.map { project in
            HunProject(snapshot: project, activeID: snapshot.activeProject, logs: logsByProject[project.id] ?? [])
        }
        model = HunDashboardModel(
            projects: projects,
            selectedProjectID: selectedProjectID,
            selectedServiceID: selectedServiceID,
            warnings: snapshot.warnings,
            scanDirs: snapshot.scanDirs
        )

        let validIDs = Set(projects.map(\.id))
        openTabIDs.removeAll { !validIDs.contains($0) }

        if selectedProjectID == nil || !validIDs.contains(selectedProjectID ?? "") {
            selectedProjectID = snapshot.activeProject.flatMap { id in validIDs.contains(id) ? id : nil }
                ?? projects.first(where: { $0.status == .running })?.id
                ?? projects.first?.id
        }

        if let selectedProjectID, !openTabIDs.contains(selectedProjectID) {
            openTabIDs.insert(selectedProjectID, at: 0)
        }
        if openTabIDs.isEmpty, let first = projects.first?.id {
            openTabIDs = [first]
        }

        ensureSelectedService()
        model.selectedProjectID = selectedProjectID
        model.selectedServiceID = selectedServiceID
    }

    private func ensureSelectedService() {
        guard let selectedProjectID,
              let project = model.projects.first(where: { $0.id == selectedProjectID })
        else {
            selectedServiceID = nil
            return
        }
        if let selectedServiceID, project.services.contains(where: { $0.id == selectedServiceID }) {
            return
        }
        selectedServiceID = project.services.first?.id
    }

    private func persistNavigationState() {
        guard let navigationDefaults else { return }
        navigationDefaults.set(selectedProjectID, forKey: NavigationPreferenceKey.selectedProject)
        navigationDefaults.set(selectedServiceID, forKey: NavigationPreferenceKey.selectedService)
        navigationDefaults.set(openTabIDs, forKey: NavigationPreferenceKey.openTabs)
        navigationDefaults.set(
            selectedLogScope == .combined ? "combined" : "service",
            forKey: NavigationPreferenceKey.logScope
        )
    }

    private var currentLogKey: String {
        guard let selectedProjectID else { return "" }
        switch selectedLogScope {
        case .service:
            return "\(selectedProjectID):\(selectedServiceID ?? "")"
        case .combined:
            return "\(selectedProjectID):*"
        }
    }

    private func scheduleLogReload() {
        Task { await reloadLogs(resubscribe: true) }
    }

    private func reloadLogs(resubscribe: Bool) async {
        guard let selectedProjectID else { return }
        let service = selectedLogScope == .service ? selectedServiceID : nil
        do {
            let lines = try await client.logs(project: selectedProjectID, service: service, lines: 500)
                .map(HunLogLine.init)
            logsByProject[selectedProjectID] = Array(lines.suffix(5_000))
            updateProjectLogs(projectID: selectedProjectID)
            if resubscribe {
                subscribe(project: selectedProjectID, service: service)
            }
        } catch {
            if !isTransientDaemonError(error) {
                lastError = error.localizedDescription
            }
        }
    }

    private func subscribe(project: String, service: String?) {
        logSubscription?.cancel()
        do {
            logSubscription = try client.subscribe(project: project, service: service) { [weak self] line in
                Task { @MainActor in
                    self?.append(line)
                }
            } onError: { [weak self] error in
                Task { @MainActor in
                    guard let self, !self.isTransientDaemonError(error) else { return }
                    self.lastError = error.localizedDescription
                }
            }
        } catch {
            if !isTransientDaemonError(error) {
                lastError = error.localizedDescription
            }
        }
    }

    private func append(_ line: HunDaemonLogLine) {
        var lines = logsByProject[line.project] ?? []
        lines.append(HunLogLine(line))
        if lines.count > 5_000 {
            lines = Array(lines.suffix(5_000))
        }
        logsByProject[line.project] = lines
        updateProjectLogs(projectID: line.project)
    }

    private func updateProjectLogs(projectID: String) {
        guard let index = model.projects.firstIndex(where: { $0.id == projectID }) else { return }
        model.projects[index].logs = logsByProject[projectID] ?? []
    }
}

private enum NavigationPreferenceKey {
    static let selectedProject = "hun.dashboard.selectedProject"
    static let selectedService = "hun.dashboard.selectedService"
    static let openTabs = "hun.dashboard.openTabs"
    static let logScope = "hun.dashboard.logScope"
}

nonisolated enum HunActionKind: String, Hashable {
    case startProject
    case stopProject
    case restartProject
    case startService
    case stopService
    case restartService
    case removeService

    var progressTitle: String {
        switch self {
        case .startProject, .startService:
            return "Starting..."
        case .stopProject, .stopService:
            return "Stopping..."
        case .restartProject, .restartService:
            return "Restarting..."
        case .removeService:
            return "Removing..."
        }
    }

    var statusText: String {
        switch self {
        case .startProject, .startService:
            return "Starting..."
        case .stopProject, .stopService:
            return "Stopping..."
        case .restartProject, .restartService:
            return "Restarting..."
        case .removeService:
            return "Removing..."
        }
    }
}

nonisolated struct HunActionKey: Hashable {
    let projectID: String
    let serviceID: String?
    let kind: HunActionKind

    static func project(_ projectID: String, _ kind: HunActionKind) -> HunActionKey {
        HunActionKey(projectID: projectID, serviceID: nil, kind: kind)
    }

    static func service(_ projectID: String, _ serviceID: String, _ kind: HunActionKind) -> HunActionKey {
        HunActionKey(projectID: projectID, serviceID: serviceID, kind: kind)
    }
}

nonisolated struct HunDashboardModel {
    var projects: [HunProject]
    var selectedProjectID: HunProject.ID?
    var selectedServiceID: HunService.ID?
    var warnings: [String]
    var scanDirs: [String]

    static let empty = HunDashboardModel(projects: [], selectedProjectID: nil, selectedServiceID: nil, warnings: [], scanDirs: [])
}

nonisolated struct HunProject: Identifiable, Hashable {
    let id: String
    var name: String
    var path: String
    var iconPath: String?
    var iconIsCustom: Bool
    var status: ProjectStatus
    var isActive: Bool
    var branch: String?
    var modeLabel: String
    var startedText: String
    var services: [HunService]
    var logs: [HunLogLine]
    var handoff: HandoffNote?
    var configError: String?

    init(snapshot: HunDaemonProject, activeID: String?, logs: [HunLogLine]) {
        id = snapshot.id
        name = snapshot.name
        path = snapshot.path
        iconPath = snapshot.iconPath
        iconIsCustom = snapshot.iconCustom
        status = ProjectStatus(snapshot.status)
        isActive = snapshot.isActive || snapshot.id == activeID
        let normalizedBranch = snapshot.branch?.trimmingCharacters(in: .whitespacesAndNewlines)
        branch = normalizedBranch?.isEmpty == false ? normalizedBranch : nil
        modeLabel = isActive ? "Active" : status.title
        startedText = Self.runtimeText(startedAt: snapshot.startedAt, status: status)
        services = snapshot.services.map(HunService.init).sorted { $0.name < $1.name }
        self.logs = logs
        handoff = HandoffNote(branch: branch, note: snapshot.lastNote ?? "")
        if handoff?.note.isEmpty == true {
            handoff = nil
        }
        configError = snapshot.configError
    }

    private static func runtimeText(startedAt: String?, status: ProjectStatus) -> String {
        guard status == .running || status == .crashed else { return "not running" }
        guard let startedAt, let date = HunDateParser.date(from: startedAt) else { return "running" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        return "\(hours) hr"
    }
}

nonisolated struct HunService: Identifiable, Hashable {
    let id: String
    var name: String
    var command: String
    var status: ProjectStatus
    var pid: Int
    var port: Int
    var ready: Bool

    init(snapshot: HunDaemonService) {
        id = snapshot.id
        name = snapshot.name
        command = snapshot.cmd ?? ""
        status = ProjectStatus(snapshot.status)
        pid = snapshot.pid
        port = snapshot.port
        ready = snapshot.ready
    }

    var pidText: String {
        pid > 0 ? "\(pid)" : "none"
    }

    var portText: String {
        port > 0 ? ":\(port)" : "none"
    }

    var browserURL: URL? {
        guard status == .running, pid > 0, port > 0 else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "localhost"
        components.port = port
        return components.url
    }
}

nonisolated struct HunLogLine: Identifiable, Hashable {
    let id = UUID()
    var time: String
    var serviceID: String
    var service: String
    var level: LogLevel
    var message: String

    init(_ line: HunDaemonLogLine) {
        time = HunDateParser.time(from: line.timestamp)
        serviceID = line.service
        service = line.service
        level = HunLogClassifier.level(for: line.text, isErr: line.isErr)
        message = line.text
    }
}

nonisolated enum HunLogClassifier {
    static func level(for text: String, isErr: Bool) -> LogLevel {
        let lower = text.lowercased()
        guard !lower.isEmpty else { return .info }
        _ = isErr // stderr alone is not enough to classify a line as an error.

        switch explicitLevel(in: lower) {
        case "error", "fatal", "critical", "panic":
            return matches(lower, benignShutdownPattern) ? .warning : .error
        case "warn", "warning":
            return .warning
        case "info", "debug", "trace", "verbose":
            return .info
        default:
            break
        }

        if matches(lower, benignShutdownPattern) {
            return .warning
        }
        if matches(lower, warningPattern) {
            return .warning
        }
        if matches(lower, errorPattern) {
            if matches(lower, benignErrorPattern) {
                return .info
            }
            return .error
        }
        if matches(lower, strongFailurePattern) {
            return .error
        }

        return .info
    }

    private static func explicitLevel(in lower: String) -> String? {
        for pattern in explicitLevelPatterns {
            guard let match = firstCapture(in: lower, pattern: pattern) else { continue }
            let normalized = match.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized == "warning" {
                return "warn"
            }
            return normalized
        }
        return nil
    }

    private static func firstCapture(in lower: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.firstMatch(in: lower, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: lower)
        else {
            return nil
        }
        return String(lower[captureRange])
    }

    private static func matches(_ lower: String, _ pattern: String) -> Bool {
        lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let explicitLevelPatterns = [
        #""level"\s*:\s*"([a-z]+)""#,
        #"^\s*(?:\[[^\]]+\]\s*)?([a-z]+)\s*:"#,
        #"\b(?:level|lvl|severity)\s*[=:]\s*"?([a-z]+)"?"#,
        #"\b(info|warn(?:ing)?|error|fatal|critical|debug|trace|verbose|panic)\/[a-z_][a-z0-9_:-]*\b"#
    ]
    private static let warningPattern = #"\b(?:warn|warning|[a-z0-9_]*warning)\b"#
    private static let errorPattern = #"\b(error|fatal|panic|exception|traceback|critical|segfault|sigsegv)\b"#
    private static let strongFailurePattern = #"\b(failed|failure|cannot|can't|unable|refused|timeout|timed out|permission denied|no such file)\b"#
    private static let benignErrorPattern = #"\b(no errors?|without errors?|0 errors?|error(s)?\s*[:=]\s*0)\b"#
    private static let benignShutdownPattern = #"\b(polite quit request|warm shutdown|graceful shutdown|draining worker|shutting down worker|terminated by signal sigterm|received sigterm)\b"#
}

nonisolated struct HandoffNote: Hashable {
    var branch: String?
    var note: String
}

nonisolated enum ProjectStatus: String, Hashable {
    case running
    case stopped
    case crashed
    case starting

    init(_ raw: String) {
        self = ProjectStatus(rawValue: raw) ?? .stopped
    }

    var title: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .running:
            AppTheme.success
        case .stopped:
            AppTheme.textTertiary
        case .crashed:
            AppTheme.danger
        case .starting:
            AppTheme.warning
        }
    }
}

nonisolated enum LogLevel: Hashable {
    case info
    case warning
    case error

    var color: Color {
        switch self {
        case .info:
            AppTheme.textSecondary
        case .warning:
            AppTheme.warning
        case .error:
            AppTheme.danger
        }
    }
}

nonisolated enum LogScope: Hashable {
    case service
    case combined
}

nonisolated enum HunMode: String, CaseIterable, Hashable {
    case focus
    case multitask

    init(_ raw: String) {
        switch raw {
        case "multitask", "parallel":
            self = .multitask
        default:
            self = .focus
        }
    }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .multitask: return "Multitask"
        }
    }

    var icon: String {
        switch self {
        case .focus: return "bolt.fill"
        case .multitask: return "rectangle.split.2x1.fill"
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .focus: return "Switch"
        case .multitask: return "Run"
        }
    }

    var primaryActionIcon: String {
        switch self {
        case .focus: return "bolt.fill"
        case .multitask: return "play.fill"
        }
    }

    var daemonMode: HunDaemonStartMode {
        switch self {
        case .focus: return .exclusive
        case .multitask: return .parallel
        }
    }

    var helpText: String {
        switch self {
        case .focus: return "One project runs at a time. Switching stops the others."
        case .multitask: return "Run projects in parallel."
        }
    }
}

extension Color {
    /// Exact sRGB color from a 24-bit hex value, e.g. `0x030303`.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

enum AppTheme {
    static let appBackground = Color(hex: 0x030303)
    static let sidebar = Color(hex: 0x060606)
    static let elevated = Color(red: 0.105, green: 0.105, blue: 0.110)

    static let divider = Color.white.opacity(0.06)
    static let dividerStrong = Color.white.opacity(0.10)

    static let hover = Color.white.opacity(0.035)
    static let selection = Color.white.opacity(0.06)
    static let tabActive = Color.white.opacity(0.055)
    static let chipFill = Color.white.opacity(0.05)
    static let buttonFill = Color.white.opacity(0.04)
    static let searchField = Color.white.opacity(0.035)

    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.36)

    /// Neutral used for log body text — readable but softer than pure white.
    static let logText = Color.white.opacity(0.66)
    /// Dimmer still, for log timestamps.
    static let logTimestamp = Color.white.opacity(0.26)

    static let accent = Color(red: 0.369, green: 0.416, blue: 0.824)
    static let success = Color(red: 0.34, green: 0.78, blue: 0.45)
    static let warning = Color(red: 0.95, green: 0.66, blue: 0.34)
    static let danger = Color(red: 0.93, green: 0.45, blue: 0.45)

    static let brand = textPrimary
}

nonisolated enum HunDateParser {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func date(from raw: String) -> Date? {
        isoWithFractional.date(from: raw) ?? iso.date(from: raw)
    }

    static func time(from raw: String) -> String {
        guard let date = date(from: raw) else { return raw }
        return timeFormatter.string(from: date)
    }
}
