import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class HunStore {
    var model = HunDashboardModel.empty
    private(set) var globalMode: HunMode = .focus
    private(set) var pendingMode: HunMode?
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
    var isRecoveringServices = false
    var isAddingProject = false
    var pendingProjectReview: HunProjectInitReview?
    /// Setup conversations with the coding agent, by project folder. Loaded
    /// from disk the first time a project is shown.
    private(set) var agentChats: [String: HunAgentChat] = [:]
    private var loadedAgentChats: Set<String> = []
    /// Logs or Setup in each project's right-hand pane, by project folder.
    var paneTabs: [String: HunPaneTab] = [:]
    /// Messages typed while the agent was busy, sent in order when it's free.
    private(set) var agentQueues: [String: [HunQueuedMessage]] = [:]
    /// The coding agent on this Mac Hun asks (Claude Code, then Codex), once found.
    private(set) var availableAgent: HunAgent?
    private var agentEnvironment: [String: String]?
    private var agentTasks: [String: Task<Void, Never>] = [:]
    var lastError: String?
    /// Set when the last action failed because something else holds a port.
    var portConflict: HunPortConflict?
    var pendingActions: Set<HunActionKey> = []
    /// Pending actions that have run long enough to offer force stop.
    var stoppableActions: Set<HunActionKey> = []
    /// Which run of each pending action is current, so a finished or
    /// force-stopped one doesn't clear a newer one with the same key.
    private var pendingTokens: [HunActionKey: UUID] = [:]
    private var forceStoppedTokens: Set<UUID> = []
    /// How long an action runs before its spinner offers force stop. Most
    /// finish in 1-5 seconds and a cold Docker start in 5-8; well past that
    /// it's likely stuck.
    static let forceStopDelay: Duration = .seconds(15)
    var daemonInfo: HunDaemonInfo?
    var daemonSettingsError: String?
    var isLoadingDaemonInfo = false
    var isRestartingDaemon = false

    private let client: HunDaemonClientProtocol
    private let supervisor: HunDaemonSupervisorProtocol
    private let projectInitializer: HunProjectInitializing
    private let navigationDefaults: UserDefaults?
    private var pollTask: Task<Void, Never>?
    private var visibilityObservers: [NSObjectProtocol] = []
    private var logSubscription: HunLogSubscribing?
    /// Lines for the log view, kept outside the project model.
    let logFeed = HunLogFeed()
    private var isApplyingSnapshot = false
    private var modeChangeTask: Task<Void, Never>?
    private var modeChangeGeneration = 0
    private var hasStarted = false

    /// Off in tests, so adding a project never starts a real agent.
    private let findsCodingAgents: Bool

    init(
        client: HunDaemonClientProtocol = HunDaemonClient(),
        supervisor: HunDaemonSupervisorProtocol = HunDaemonSupervisor(),
        projectInitializer: HunProjectInitializing = HunProjectInitializer(),
        navigationDefaults: UserDefaults? = nil,
        startAutomatically: Bool = true,
        findsCodingAgents: Bool = true
    ) {
        self.findsCodingAgents = findsCodingAgents
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

    var displayedMode: HunMode {
        pendingMode ?? globalMode
    }

    var isChangingMode: Bool {
        pendingMode != nil
    }

    func changeMode(_ mode: HunMode, preferredProject: HunProject.ID?) {
        guard mode != displayedMode else { return }
        let preferredProject = mode == .focus ? runningProjectID(preferredProject) : nil
        pendingMode = mode
        modeChangeGeneration += 1
        let generation = modeChangeGeneration
        let previousTask = modeChangeTask
        modeChangeTask = Task { [weak self] in
            await previousTask?.value
            guard let self, generation == self.modeChangeGeneration else { return }
            await self.setMode(mode, preferredProject: preferredProject, generation: generation)
        }
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
        let order: [HunActionKind] = [.startProject, .switchProfile, .restartProject, .stopProject]
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
        guard !hasStarted else { return }
        hasStarted = true
        // Paint from the daemon's cached registry (a few ms), then rescan
        // project folders. Installing the agent skill copies files, so it
        // waits until the dashboard is on screen.
        await refresh(force: false)
        await refresh(force: true)
        installAgentSkillIfPossible()
        startPolling()
        _ = await resolveAgent()
    }

    func refreshNow() {
        Task { await refresh(force: true) }
    }

    func clearLastError() {
        lastError = nil
        portConflict = nil
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

    /// Adds the repository a running dev server belongs to.
    func addProject(from process: HunUnmanagedProcess) {
        var url = URL(fileURLWithPath: process.cwd, isDirectory: true)
        var candidate = url
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".git").path) {
                url = candidate
                break
            }
            candidate.deleteLastPathComponent()
        }
        Task { await addProject(at: url) }
    }

    /// Adds a folder as a project. A new project is registered straight
    /// away; if a coding agent is installed, it then writes the project's
    /// .hun.yml in the background while the window shows it working. Hun's
    /// own rule-based draft is the fallback. A .hun.yml already in the
    /// folder is used as it is.
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
            let agent = await resolveAgent()
            let draft = try await projectInitializer.initializeProject(at: url)
            HunTrace.addProject("flow drafted path=\(draft.path) created=\(draft.createdConfig) agent=\(agent?.kind.rawValue ?? "none")")
            if draft.createdConfig, let agent {
                // Show the agent at work before the rule-based draft can.
                loadedAgentChats.insert(draft.path)
                agentChats[draft.path] = HunAgentChat(agent: agent.kind, sessionID: nil, messages: [.agentWorking(isSetup: true)])
            }
            try await supervisor.ensureDaemon()
            try await client.registerProject(path: draft.path)
            await refresh(force: true)
            selectProject(at: URL(fileURLWithPath: draft.path))
            lastError = nil
            if draft.createdConfig, let agent {
                runAgent(agent, path: draft.path, prompt: HunAgentBrief.setup, resuming: nil)
            }
        } catch {
            HunTrace.addProject("flow failed path=\(url.path) error=\(HunTrace.compact(error.localizedDescription))")
            agentChats[url.path] = nil
            lastError = error.localizedDescription
        }
    }

    // MARK: Coding agents

    /// The setup conversation for a project folder.
    func agentChat(for path: String) -> HunAgentChat? {
        agentChats[path]
    }

    /// Reads conversations from disk for projects seen for the first time.
    private func loadAgentChats(for paths: [String]) {
        for path in paths where !loadedAgentChats.contains(path) {
            loadAgentChat(for: path)
        }
    }

    private func loadAgentChat(for path: String) {
        if !loadedAgentChats.contains(path) {
            loadedAgentChats.insert(path)
            if var chat = HunAgentChatArchive.load(for: path) {
                // A reply that was running when Hun quit didn't finish.
                if let last = chat.messages.indices.last, chat.messages[last].status == .working {
                    chat.messages[last].status = .failed
                    chat.messages[last].text = "This was interrupted when Hun quit."
                }
                agentChats[path] = chat
            }
        }
    }

    /// Sends a message now, or queues it if the agent is still working.
    func sendAgentMessage(_ text: String, for project: HunProject) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if agentChats[project.path]?.isWorking == true {
            agentQueues[project.path, default: []].append(HunQueuedMessage(text: text))
        } else {
            askAgent(text, for: project)
        }
    }

    /// Steers: stops the turn in progress and sends this instead, in the
    /// same session, so the agent still has what was asked before.
    func steerAgent(_ text: String, for project: HunProject) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if agentChats[project.path]?.isWorking == true {
            cancelAgent(for: project.path, note: "Stopped for your next message.")
            askAgent(text, for: project, steering: true)
        } else {
            askAgent(text, for: project)
        }
    }

    func removeQueuedAgentMessage(_ id: UUID, for path: String) {
        agentQueues[path]?.removeAll { $0.id == id }
    }

    /// Sends a queued message right away, steering the turn in progress.
    func sendQueuedAgentMessageNow(_ id: UUID, for project: HunProject) {
        guard let message = agentQueues[project.path]?.first(where: { $0.id == id }) else { return }
        removeQueuedAgentMessage(id, for: project.path)
        steerAgent(message.text, for: project)
    }

    /// After a turn ends, the next queued message, if any.
    private func sendNextQueuedAgentMessage(for path: String) {
        guard var queue = agentQueues[path], !queue.isEmpty,
              let project = model.projects.first(where: { $0.path == path })
        else { return }
        let next = queue.removeFirst()
        agentQueues[path] = queue.isEmpty ? nil : queue
        askAgent(next.text, for: project)
    }

    /// Asks the project's agent to change its .hun.yml ("put the API in Docker").
    func askAgent(_ request: String, for project: HunProject, steering: Bool = false) {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        loadAgentChat(for: project.path)
        guard !request.isEmpty, agentChats[project.path]?.isWorking != true else { return }
        Task {
            guard let agent = await resolveAgent() else {
                lastError = "Install Claude Code or Codex to change the setup by asking."
                return
            }
            let configURL = URL(fileURLWithPath: project.configPath)
            let current = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            var chat = agentChats[project.path]
                ?? HunAgentChat(agent: agent.kind, sessionID: nil, messages: [])
            // A different agent can't pick up another one's session.
            if chat.agent != agent.kind {
                chat.agent = agent.kind
                chat.sessionID = nil
            }
            chat.messages.append(.user(request))
            chat.messages.append(.agentWorking(isSetup: false))
            agentChats[project.path] = chat
            let state = await liveState(for: project)
            runAgent(
                agent, path: project.path,
                prompt: HunAgentBrief.change(
                    steering ? "Change of plan, this replaces what I asked just before: \(request)" : request,
                    current: current, state: state
                ),
                resuming: chat.sessionID,
                previousConfig: current
            )
        }
    }

    /// Stops the agent. A first setup keeps Hun's rule-based draft.
    func cancelAgent(for path: String, note: String? = nil) {
        agentTasks[path]?.cancel()
        agentTasks[path] = nil
        updateLastAgentMessage(path: path) { message in
            guard message.status == .working else { return }
            message.status = .failed
            message.isThinking = nil
            message.text = note ?? (message.isSetup
                ? "Stopped. Hun's own setup is in place; ask for any changes here."
                : "Stopped.")
        }
    }

    /// Puts back the .hun.yml from before a reply's change.
    func undoAgentChange(_ messageID: UUID, for project: HunProject) {
        guard var chat = agentChats[project.path], !chat.isWorking,
              let index = chat.messages.firstIndex(where: { $0.id == messageID }),
              let change = chat.messages[index].change, !change.undone
        else { return }
        Task {
            if let problem = await saveAgentConfig(change.previousConfig, path: project.path) {
                lastError = problem
                return
            }
            await refresh(force: true)
            chat.messages[index].change?.undone = true
            agentChats[project.path] = chat
            HunAgentChatArchive.save(chat, for: project.path)
        }
    }

    /// Starts the setup conversation over. The project's .hun.yml stays as it is.
    func clearAgentChat(for path: String) {
        guard agentChats[path]?.isWorking != true else { return }
        agentChats[path] = nil
        agentQueues[path] = nil
        HunAgentChatArchive.remove(for: path)
    }

    /// Looks for an agent again, for after someone installs one.
    func recheckAgent() async {
        availableAgent = nil
        agentEnvironment = nil
        await resolveAgent()
    }

    /// Each service's status and port, and the latest log lines, so the agent
    /// can answer "why did the API crash?".
    private func liveState(for project: HunProject) async -> String? {
        let services = project.services.filter { !$0.isExternal }
        guard !services.isEmpty else { return nil }
        var lines = services.map { service -> String in
            let port = service.port > 0 ? " on port \(service.port)" : ""
            return "- \(service.name): \(service.status.rawValue)\(port)"
        }
        if let logs = try? await client.logs(project: project.id, service: nil, lines: 120), !logs.isEmpty {
            lines.append("")
            lines.append("Latest log lines (oldest first):")
            lines += logs.suffix(120).map { "[\($0.service)]\($0.isErr ? " (stderr)" : "") \($0.text)" }
        }
        return lines.joined(separator: "\n")
    }

    #if DEBUG
    /// Debug builds: act as if no agent is installed, to see that state.
    var debugHidesAgent = false
    #endif

    /// The agent to ask, found once (and looked for again until one is installed).
    @discardableResult
    func resolveAgent() async -> HunAgent? {
        guard findsCodingAgents else { return nil }
        #if DEBUG
        if debugHidesAgent { availableAgent = nil; return nil }
        #endif
        if let availableAgent { return availableAgent }
        let environment = await environmentForAgents()
        let agent = await Task.detached(priority: .utility) {
            HunAgentLocator.preferred(environment: environment)
        }.value
        availableAgent = agent
        return agent
    }

    /// Every coding agent installed on this Mac (Claude Code first).
    func installedAgents() async -> [HunAgent] {
        guard findsCodingAgents else { return [] }
        #if DEBUG
        if debugHidesAgent { return [] }
        #endif
        let environment = await environmentForAgents()
        return await Task.detached(priority: .utility) {
            HunAgentLocator.installed(environment: environment)
        }.value
    }

    private func environmentForAgents() async -> [String: String] {
        if let agentEnvironment { return agentEnvironment }
        let environment = await HunShellEnvironment.loginEnvironment()
        agentEnvironment = environment
        return environment
    }

    private func runAgent(
        _ agent: HunAgent,
        path: String,
        prompt: String,
        resuming session: String?,
        previousConfig: String? = nil
    ) {
        agentTasks[path]?.cancel()
        let before = setupOutline(path: path)
        HunTrace.addProject("agent start path=\(path) agent=\(agent.kind.rawValue) resume=\(session != nil)")
        agentTasks[path] = Task { [weak self] in
            guard let self else { return }
            let environment = await self.environmentForAgents()
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            let apply: @MainActor @Sendable (HunAgentEvent) -> Void = { [weak self] event in
                self?.applyAgentEvent(event, path: path)
            }
            let onEvent: @Sendable (HunAgentEvent) -> Void = { event in
                Task { @MainActor in apply(event) }
            }
            do {
                var result = try await HunAgentRunner.run(
                    agent, in: directory, prompt: prompt, resuming: session,
                    environment: environment, onEvent: onEvent
                )
                if let problem = await self.saveAgentConfig(result.yaml, path: path) {
                    // One more go, with the daemon's reason.
                    HunTrace.addProject("agent retry path=\(path) problem=\(HunTrace.compact(problem))")
                    self.applyAgentEvent(.step("Fixing the setup", files: []), path: path)
                    let summary = result.summary
                    result = try await HunAgentRunner.run(
                        agent, in: directory, prompt: HunAgentBrief.fix(problem),
                        resuming: result.sessionID ?? session, environment: environment, onEvent: onEvent
                    )
                    if result.summary.isEmpty { result = HunAgentResult(yaml: result.yaml, summary: summary, sessionID: result.sessionID) }
                    if let again = await self.saveAgentConfig(result.yaml, path: path) {
                        throw HunAgentError.failed(again)
                    }
                }
                await self.refresh(force: true)
                var change: HunAgentChange?
                if let previousConfig, let before {
                    let lines = HunSetupOutline.changes(from: before, to: self.setupOutline(path: path) ?? before)
                    change = HunAgentChange(lines: lines, previousConfig: previousConfig, undone: false)
                }
                self.finishAgent(path: path, summary: result.summary, sessionID: result.sessionID, change: change)
            } catch is CancellationError {
                HunTrace.addProject("agent cancelled path=\(path)")
            } catch {
                HunTrace.addProject("agent failed path=\(path) error=\(HunTrace.compact(error.localizedDescription))")
                let reason = HunAgentError.friendly(error, agent: agent.kind)
                self.updateLastAgentMessage(path: path) { message in
                    message.status = .failed
                    message.isThinking = nil
                    message.text = message.isSetup
                        ? "I couldn't finish, so Hun's own setup is in place. \(reason)"
                        : reason
                }
            }
            if !Task.isCancelled {
                self.agentTasks[path] = nil
                self.sendNextQueuedAgentMessage(for: path)
            }
        }
    }

    /// The project's services and profiles as the daemon last reported them.
    private func setupOutline(path: String) -> HunSetupOutline? {
        guard let project = model.projects.first(where: { $0.path == path }) else { return nil }
        var services: [String: HunSetupOutline.Service] = [:]
        for service in project.services where !service.isExternal {
            services[service.name] = .init(command: service.command, port: service.port)
        }
        var profiles: [String: [String]] = [:]
        for profile in project.profiles {
            profiles[profile.name] = profile.services
        }
        return HunSetupOutline(services: services, profiles: profiles)
    }

    /// Saves through the daemon, which checks it first. Returns why not, if it can't.
    private func saveAgentConfig(_ yaml: String, path: String) async -> String? {
        do {
            try await client.saveConfig(path: path, content: yaml)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func applyAgentEvent(_ event: HunAgentEvent, path: String) {
        updateLastAgentMessage(path: path, save: false) { message in
            guard message.status == .working else { return }
            switch event {
            case let .step(step, files):
                message.isThinking = nil
                if message.steps.last != step { message.steps.append(step) }
                var read = message.files ?? []
                for file in files where !read.contains(file) { read.append(file) }
                message.files = read.isEmpty ? nil : read
            case .thinking:
                message.isThinking = true
            case let .reply(text):
                message.isThinking = nil
                message.text = text
            }
        }
    }

    private func finishAgent(path: String, summary: String, sessionID: String?, change: HunAgentChange?) {
        // When a new project's first setup finishes, show what was set up.
        if agentChats[path]?.isFirstSetupRunning == true {
            paneTabs[path] = .setup
        }
        updateLastAgentMessage(path: path) { message in
            message.status = .done
            message.isThinking = nil
            if !summary.isEmpty { message.text = summary }
            message.change = change
        }
        if let sessionID, var chat = agentChats[path] {
            chat.sessionID = sessionID
            agentChats[path] = chat
            HunAgentChatArchive.save(chat, for: path)
        }
        HunTrace.addProject("agent done path=\(path)")
    }

    private func updateLastAgentMessage(path: String, save: Bool = true, _ update: (inout HunAgentMessage) -> Void) {
        guard var chat = agentChats[path], let index = chat.messages.lastIndex(where: { $0.role == .agent }) else { return }
        update(&chat.messages[index])
        agentChats[path] = chat
        if save { HunAgentChatArchive.save(chat, for: path) }
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

    /// The .hun.yml open in Hun's editor, if any.
    var configEditor: HunConfigEditorTarget?
    /// The same, opened from the add-project review, which is already a sheet.
    var reviewConfigEditor: HunConfigEditorTarget?

    func openConfig(for project: HunProject) {
        let target = HunConfigEditorTarget(name: project.name, directory: project.path, file: project.configPath)
        guard FileManager.default.fileExists(atPath: target.fileURL.path) else {
            lastError = "\(project.name) does not have a .hun.yml file."
            return
        }
        configEditor = target
    }

    /// Why `content` is not a config Hun can run, or nil when it is.
    func configProblem(in content: String) async -> String? {
        do {
            try await client.validateConfig(content)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Saves edited .hun.yml source; returns why it couldn't, or nil.
    func saveConfig(_ content: String, for target: HunConfigEditorTarget) async -> String? {
        do {
            try await client.saveConfig(path: target.directory, content: content)
        } catch {
            return error.localizedDescription
        }
        if let review = pendingProjectReview, review.path == target.directory {
            pendingProjectReview = review.replacingConfig(with: content)
        }
        await refresh(force: true)
        return nil
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
        // A banner or screenshot can't work at icon size, so ask for a
        // square-ish image rather than showing an unreadable sliver.
        if let image = NSImage(contentsOf: url), !ProjectIconTraits.isIconShaped(image.size) {
            lastError = "\(url.lastPathComponent) is \(Int(image.size.width))×\(Int(image.size.height)). Choose a square image for the logo."
            return
        }
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
        let target = HunConfigEditorTarget(name: review.name, directory: review.path)
        guard FileManager.default.fileExists(atPath: target.fileURL.path) else {
            lastError = "\(review.name) does not have a .hun.yml file."
            return
        }
        reviewConfigEditor = target
    }

    /// Copies files, so it runs off the main thread.
    private func installAgentSkillIfPossible() {
        Task {
            let failure: String? = await Task.detached(priority: .utility) {
                do {
                    _ = try HunAgentSkillInstaller.installBundledSkillGlobally()
                    return nil
                } catch HunAgentSkillInstallError.missingBundledSkill {
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let failure { lastError = failure }
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
        defer { isRefreshing = false }
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
            if isTransientDaemonError(error) {
                isRecoveringServices = true
            } else {
                isRecoveringServices = false
                lastError = error.localizedDescription
            }
        }
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

    /// Chooses a profile, or every service for nil. A running project switches
    /// to it, changing only the services that differ; a stopped one stays
    /// stopped and runs it next time.
    func chooseProfile(_ profile: String?, for project: HunProject) {
        let name = profile ?? HunProfile.allServices
        guard project.status == .running || project.status == .starting else {
            perform(key: .project(project.id, .switchProfile)) { [self] in
                try await self.client.selectProfile(project.id, profile: name)
            }
            return
        }
        if globalMode == .focus {
            selectProject(project.id)
        }
        perform(key: .project(project.id, .switchProfile)) { [self] in
            try await self.client.runProfile(project.id, profile: name, mode: self.globalMode.daemonMode)
        }
    }

    /// Saves the project's running services as a profile in its .hun.yml.
    func saveRunningServicesAsProfile(named name: String, for project: HunProject) {
        let services = project.services
            .filter { $0.status == .running || $0.status == .starting }
            .map(\.id)
        guard !services.isEmpty else { return }
        perform(key: .project(project.id, .switchProfile)) { [self] in
            try await self.client.saveProfile(project.id, name: name, services: services)
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

    /// Stops whatever holds a stopped service's port, then runs the service.
    func stopHolderAndRun(_ service: HunService, in project: HunProject) {
        guard let holder = service.conflict else { return }
        perform(key: .service(project.id, service.id, .startService)) { [self] in
            try await self.client.freePort(holder.port)
            try await self.client.startService(project.id, service: service.id, mode: self.globalMode.daemonMode)
        }
    }

    /// Stops the holder named by the last port conflict, then retries the action that hit it.
    func resolvePortConflict() {
        guard let conflict = portConflict else { return }
        portConflict = nil
        lastError = nil
        perform(key: conflict.key) { [self] in
            try await self.client.freePort(conflict.holder.port)
            try await conflict.retry()
        }
    }

    /// Unregisters a project; its folder and files are left alone.
    func remove(_ project: HunProject) {
        perform(key: .project(project.id, .stopProject)) { [self] in
            try await self.client.removeProject(project.id)
        }
    }

    /// Clears the logs in view (the selected service's, or the whole
    /// project's in the All view); new output keeps streaming in.
    func clearLogs(for project: HunProject) {
        let service = selectedLogScope == .service ? selectedServiceID : nil
        logFeed.clear(service: service)
        Task {
            do {
                try await client.clearLogs(project: project.id, service: service)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func stop(_ process: HunUnmanagedProcess) {
        perform { [self] in
            try await self.client.freePort(process.port)
        }
    }

    func remove(_ service: HunService, from project: HunProject) {
        perform(key: .service(project.id, service.id, .removeService)) { [self] in
            try await self.client.removeService(project.id, service: service.id)
        }
    }

    private func setMode(_ mode: HunMode, preferredProject: String?, generation: Int) async {
        var finalError: Error?
        for attempt in 0..<3 {
            do {
                try await client.setMode(mode, preferredProject: preferredProject)
                globalMode = mode
                if generation == modeChangeGeneration {
                    pendingMode = nil
                    lastError = nil
                }
                await refresh(force: false)
                return
            } catch {
                finalError = error
                guard isTransientDaemonError(error), attempt < 2 else { break }
                if !isLifecycleBusyError(error) {
                    try? await supervisor.ensureDaemon()
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        guard generation == modeChangeGeneration else { return }
        pendingMode = nil
        if let finalError {
            lastError = "Couldn’t switch mode: \(finalError.localizedDescription)"
        }
    }

    private func perform(key: HunActionKey? = nil, _ operation: @escaping () async throws -> Void) {
        Task {
            let token = UUID()
            if let key {
                pendingActions.insert(key)
                pendingTokens[key] = token
                stoppableActions.remove(key)
                Task { [weak self] in
                    try? await Task.sleep(for: Self.forceStopDelay)
                    guard let self, self.pendingTokens[key] == token else { return }
                    withAnimation(.easeOut(duration: 0.25)) { _ = self.stoppableActions.insert(key) }
                }
            }
            defer {
                if let key, pendingTokens[key] == token {
                    pendingActions.remove(key)
                    pendingTokens[key] = nil
                    stoppableActions.remove(key)
                }
            }
            do {
                try await operation()
                guard !forceStoppedTokens.contains(token) else { return }
                lastError = nil
                portConflict = nil
                await refresh(force: true)
            } catch HunDaemonError.portConflict(let message, let holder) {
                guard !forceStoppedTokens.contains(token) else { return }
                lastError = message
                portConflict = HunPortConflict(holder: holder, key: key, retry: operation)
                await refresh(force: true)
            } catch {
                // A force-stopped action ends in an error nobody needs to see.
                guard !forceStoppedTokens.contains(token) else { return }
                lastError = error.localizedDescription
                portConflict = nil
            }
        }
    }

    /// Force-stops a pending action that's taking too long: its spinner goes
    /// at once, and the daemon kills the project's (or service's) processes
    /// without waiting behind it.
    func forceStop(_ key: HunActionKey) {
        guard let token = pendingTokens[key] else { return }
        forceStoppedTokens.insert(token)
        pendingTokens[key] = nil
        pendingActions.remove(key)
        stoppableActions.remove(key)
        Task {
            do {
                try await client.forceStop(key.projectID, service: key.serviceID)
                lastError = nil
            } catch {
                lastError = "Couldn’t force-stop: \(error.localizedDescription)"
            }
            await refresh(force: true)
        }
    }

    /// Force stop for a project's pending action, once it's been long enough.
    func forceStopAction(for project: HunProject) -> (() -> Void)? {
        guard let kind = projectAction(for: project) else { return nil }
        let key = HunActionKey.project(project.id, kind)
        guard stoppableActions.contains(key) else { return nil }
        return { [weak self] in self?.forceStop(key) }
    }

    /// Force stop for a service's pending action, once it's been long enough.
    func forceStopAction(for service: HunService, in project: HunProject) -> (() -> Void)? {
        guard let kind = serviceAction(for: service, in: project) else { return nil }
        let key = HunActionKey.service(project.id, service.id, kind)
        guard stoppableActions.contains(key) else { return nil }
        return { [weak self] in self?.forceStop(key) }
    }

    private func isTransientDaemonError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("connection closed") ||
            message.contains("no such file or directory") ||
            message.contains("connection refused") ||
            message.contains("broken pipe") ||
            message.contains("socket is not connected") ||
            message.contains("resource temporarily unavailable") ||
            message.contains("lifecycle operation in progress")
    }

    private func isLifecycleBusyError(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("lifecycle operation in progress")
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(2))
                guard !Task.isCancelled else { break }
                guard self?.pendingProjectReview == nil else { continue }
                await self?.refresh(force: false)
            }
        }
        // Coming back into view refreshes straight away rather than waiting
        // out the slower background interval.
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSWindow.didChangeOcclusionStateNotification] {
            visibilityObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isInView, self.pendingProjectReview == nil else { return }
                    await self.refresh(force: false)
                }
            })
        }
    }

    /// Each snapshot has the daemon re-scan what's running (lsof, ps,
    /// docker), so poll less often while Hun is out of sight.
    private var pollInterval: Duration {
        isInView ? .seconds(2) : .seconds(10)
    }

    private var isInView: Bool {
        guard let app = NSApp else { return true }
        return app.isActive || app.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) }
    }

    private func apply(_ snapshot: HunDaemonSnapshot) {
        isApplyingSnapshot = true
        defer { isApplyingSnapshot = false }

        globalMode = HunMode(snapshot.mode)
        isRecoveringServices = snapshot.lifecycleBusy

        var projects = snapshot.projects.map { project in
            HunProject(snapshot: project, activeID: snapshot.activeProject)
        }
        #if DEBUG
        projects += HunWorktreeSimulation.projects()
        #endif
        loadAgentChats(for: projects.map(\.path))
        // A project renamed in .hun.yml comes back under a new ID; keep its
        // tab and selection by matching the folder.
        let previousPaths = Dictionary(model.projects.map { ($0.id, $0.path) }, uniquingKeysWith: { first, _ in first })
        let idsByPath = Dictionary(projects.map { ($0.path, $0.id) }, uniquingKeysWith: { first, _ in first })
        let currentIDs = Set(projects.map(\.id))
        func followRename(_ id: HunProject.ID) -> HunProject.ID {
            guard !currentIDs.contains(id), let path = previousPaths[id], let renamed = idsByPath[path] else { return id }
            return renamed
        }
        openTabIDs = openTabIDs.map(followRename)
        if let selected = selectedProjectID {
            selectedProjectID = followRename(selected)
        }
        model = HunDashboardModel(
            projects: projects,
            selectedProjectID: selectedProjectID,
            selectedServiceID: selectedServiceID,
            warnings: snapshot.warnings,
            scanDirs: snapshot.scanDirs,
            unmanaged: snapshot.unmanaged
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
            logFeed.replace(with: lines)
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
        let feed = logFeed
        let subscription = feed.beginSubscription()
        // Lines are converted on the reader thread and reach the feed in
        // batches, so a chatty service can't flood the main thread.
        let batcher = HunLogBatcher { batch in
            feed.append(batch, subscription: subscription)
        }
        do {
            logSubscription = try client.subscribe(project: project, service: service) { line in
                batcher.add(line)
            } onError: { [weak self] error in
                guard let self else { return }
                Task { @MainActor in
                    guard !self.isTransientDaemonError(error) else { return }
                    self.lastError = error.localizedDescription
                }
            }
        } catch {
            if !isTransientDaemonError(error) {
                lastError = error.localizedDescription
            }
        }
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
    case switchProfile

    var progressTitle: String {
        switch self {
        case .startProject, .startService, .switchProfile:
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
        case .startProject, .startService, .switchProfile:
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
    /// Dev servers listening on ports that no registered service accounts for.
    var unmanaged: [HunUnmanagedProcess] = []

    static let empty = HunDashboardModel(projects: [], selectedProjectID: nil, selectedServiceID: nil, warnings: [], scanDirs: [])
}

/// A failed action and the process holding the port it needed.
struct HunPortConflict {
    let holder: HunPortHolder
    let key: HunActionKey?
    let retry: () async throws -> Void
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
    var handoff: HandoffNote?
    var configError: String?
    var profiles: [HunDaemonProfile]
    /// The profile Run uses; nil runs every service.
    var profile: String?
    /// The main checkout's folder, when this is a git worktree: it's shown
    /// under that project.
    var worktreeOf: String?
    /// When the worktree was made: the newest are listed first.
    var worktreeCreated: Date?
    /// The .hun.yml it runs on: its own, or its main checkout's.
    var configPath: String

    var isWorktree: Bool { worktreeOf != nil }

    /// Newest worktree first; ones without a date last, then by name.
    static func newestWorktreeFirst(_ a: HunProject, _ b: HunProject) -> Bool {
        switch (a.worktreeCreated, b.worktreeCreated) {
        case let (x?, y?) where x != y: return x > y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.worktreeName.localizedStandardCompare(b.worktreeName) == .orderedAscending
        }
    }
    /// A worktree's own name: its folder (ott-1650), not its registry key.
    var worktreeName: String { URL(fileURLWithPath: path).lastPathComponent }

    /// What the current profile runs, or nil when it runs every service.
    var profileServices: Set<String>? {
        guard let profile, let match = profiles.first(where: { $0.name == profile }) else { return nil }
        return Set(match.resolved)
    }

    init(snapshot: HunDaemonProject, activeID: String?) {
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
        handoff = HandoffNote(branch: branch, note: snapshot.lastNote ?? "")
        if handoff?.note.isEmpty == true {
            handoff = nil
        }
        configError = snapshot.configError
        profiles = snapshot.profiles
        profile = snapshot.profile
        worktreeOf = snapshot.worktreeOf
        worktreeCreated = snapshot.worktreeCreatedAt.flatMap(HunDateParser.date(from:))
        configPath = snapshot.configPath ?? URL(fileURLWithPath: snapshot.path).appendingPathComponent(".hun.yml").path
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

enum HunProfile {
    /// The daemon's name for running every service.
    static let allServices = "all"

    /// Why a name can't be used for a new profile, or nil when it can.
    static func problem(with name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter a name." }
        if trimmed == allServices { return "\"all\" already means every service." }
        if trimmed.contains(where: { $0 == ":" || $0 == "#" || $0.isNewline }) {
            return "Use letters, numbers, - or _."
        }
        return nil
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
    /// Running, but started outside Hun (a terminal, an agent, Docker Desktop).
    var isExternal: Bool
    var isDocker: Bool
    var container: String?
    /// What holds the configured port while this service is stopped.
    var conflict: HunPortHolder?

    init(snapshot: HunDaemonService) {
        id = snapshot.id
        name = snapshot.name
        command = snapshot.cmd ?? ""
        status = ProjectStatus(snapshot.status)
        pid = snapshot.pid
        port = snapshot.port
        ready = snapshot.ready
        isExternal = snapshot.origin == "external"
        isDocker = snapshot.runtime == "docker"
        container = snapshot.container
        conflict = snapshot.conflict
    }

    var externalSourceText: String {
        if isDocker, let container, !container.isEmpty {
            return "Started outside Hun · Docker container \(container)"
        }
        return pid > 0 ? "Started outside Hun · pid \(pid)" : "Started outside Hun"
    }

    var pidText: String {
        pid > 0 ? "\(pid)" : "none"
    }

    var portText: String {
        port > 0 ? ":\(port)" : "none"
    }

    var browserURL: URL? {
        guard status == .running, pid > 0 || isExternal, port > 0 else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "localhost"
        components.port = port
        return components.url
    }
}

nonisolated struct HunLogLine: Identifiable, Hashable, Sendable {
    /// Sequence number, assigned when the line reaches `HunLogFeed`.
    var id = 0
    var time: String
    var service: String
    var level: LogLevel
    var message: String

    var serviceID: String { service }

    init(_ line: HunDaemonLogLine) {
        time = HunDateParser.time(from: line.timestamp)
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
    nonisolated init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
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
