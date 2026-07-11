import Foundation
import Testing
@testable import hun

@MainActor
struct hunTests {
    @Test func snapshotDecodingMapsProjectState() async throws {
        let client = MockDaemonClient()
        client.nextSnapshot = .fixture(activeProject: "app")
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)

        await store.refresh(force: true)

        #expect(store.isConnected)
        #expect(store.globalMode == .focus)
        #expect(store.selectedProjectID == "app")
        #expect(store.model.projects.first?.services.first?.name == "web")
        #expect(store.model.projects.first?.status == .running)
        #expect(store.model.projects.first?.iconPath == "/tmp/projects/app/logo.png")
        #expect(store.model.projects.first?.iconIsCustom == true)
    }

    @Test func snapshotDecodingDefaultsMissingWarnings() throws {
        let payload = """
        {
          "protocol": 2,
          "mode": "focus",
          "scan_dirs": ["/tmp/projects"],
          "last_scan_at": "2026-05-11T00:30:22.153584+05:30",
          "projects": [
            {
              "id": "app",
              "name": "app",
              "path": "/tmp/projects/app",
              "status": "stopped",
              "is_active": false,
              "services": []
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(HunDaemonSnapshot.self, from: payload)

        #expect(snapshot.warnings.isEmpty)
        #expect(snapshot.projects.map(\.id) == ["app"])
    }

    @Test func daemonSettingsLoadsHealthAndRestartsDaemon() async throws {
        let client = MockDaemonClient()
        client.nextDaemonInfo = HunDaemonInfo(
            status: "pong",
            protocolVersion: 11,
            version: "v0.2.1",
            commit: "abc1234",
            pid: 4242,
            startedAt: "2026-07-11T06:30:00Z"
        )
        let supervisor = MockSupervisor()
        let store = HunStore(client: client, supervisor: supervisor, startAutomatically: false)

        await store.refreshDaemonInfo()

        #expect(store.daemonInfo == client.nextDaemonInfo)
        #expect(store.daemonSettingsError == nil)

        await store.restartDaemon()

        #expect(supervisor.restartCount == 1)
        #expect(client.daemonInfoRequests == 2)
        #expect(store.daemonInfo == client.nextDaemonInfo)
        #expect(store.isRestartingDaemon == false)
    }

    @Test func daemonInfoDecodesLegacyPingWithoutBuildMetadata() throws {
        let payload = """
        {
          "status": "pong",
          "protocol": 10
        }
        """.data(using: .utf8)!

        let info = try JSONDecoder().decode(HunDaemonInfo.self, from: payload)

        #expect(info.status == "pong")
        #expect(info.protocolVersion == 10)
        #expect(info.version == "unknown")
        #expect(info.commit == "none")
        #expect(info.pid == 0)
        #expect(info.startedAt.isEmpty)
    }

    @Test func debugAppUsesIsolatedHunHome() throws {
        #if DEBUG
        #expect(HunPaths.environmentName == "Development")
        #expect(HunPaths.homeURL.lastPathComponent == ".hun-dev")
        #expect(HunPaths.socketPath.contains("/.hun-dev/"))
        #endif
    }

    @Test func daemonRestartPrefersSocketReportedPIDWhenPIDFileIsMissing() throws {
        let missingPIDFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .path

        #expect(resolvedDaemonProcessID(reportedPID: 4242, pidPath: missingPIDFile) == 4242)
        #expect(resolvedDaemonProcessID(reportedPID: 0, pidPath: missingPIDFile) == nil)
    }

    @Test func logClassificationDoesNotTreatStderrAsError() throws {
        #expect(logLevel("Container otto-redis-1 Running", isErr: true) == .info)
        #expect(logLevel("INFO/MainProcess] beat: Starting...", isErr: true) == .info)
        #expect(logLevel("AuthlibDeprecationWarning: authlib.jose module is deprecated", isErr: true) == .warning)
        #expect(logLevel("ERROR: Script was terminated by signal SIGTERM (Polite quit request)", isErr: true) == .warning)
        #expect(logLevel("FATAL: unable to bind port: permission denied", isErr: true) == .error)
    }

    @Test func agentPromptIncludesProjectAndHunSkillInstructions() throws {
        let project = HunProject(snapshot: .fixtureProject(path: "/tmp/projects/shop"), activeID: nil, logs: [])
        let prompt = HunAgentPromptBuilder.prompt(
            for: project,
            bundledSkillURL: URL(fileURLWithPath: "/Applications/hun.app/Contents/Resources/hun-skill/SKILL.md"),
            globalSkillURLs: [
                URL(fileURLWithPath: "/Users/me/.agents/skills/hun/SKILL.md"),
                URL(fileURLWithPath: "/Users/me/.claude/skills/hun/SKILL.md")
            ]
        )

        #expect(prompt.contains("Use the Hun skill"))
        #expect(prompt.contains("/tmp/projects/shop"))
        #expect(prompt.contains("/tmp/projects/shop/.hun.yml"))
        #expect(prompt.contains("local vs Docker vs hybrid"))
        #expect(prompt.contains("Run `hun validate .`"))
        #expect(prompt.contains("/Applications/hun.app/Contents/Resources/hun-skill/SKILL.md"))
        #expect(prompt.contains("/Users/me/.agents/skills/hun/SKILL.md"))
        #expect(prompt.contains("/Users/me/.claude/skills/hun/SKILL.md"))
    }

    @Test func agentPromptSupportsPendingProjectReview() throws {
        let review = HunProjectInitReview(
            name: "shop",
            path: "/tmp/projects/shop",
            configPath: "/tmp/projects/shop/.hun.yml",
            configContents: "name: shop\nservices:\n  web:\n    cmd: npm run dev\n",
            commandOutput: "",
            createdConfig: true
        )

        let prompt = HunAgentPromptBuilder.prompt(
            for: review,
            bundledSkillURL: URL(fileURLWithPath: "/Applications/hun.app/Contents/Resources/hun-skill/SKILL.md"),
            globalSkillURLs: []
        )

        #expect(prompt.contains("- name: shop"))
        #expect(prompt.contains("- path: /tmp/projects/shop"))
        #expect(prompt.contains("Inspect any existing .hun.yml before changing it."))
    }

    @Test func projectInitReviewExtractsNameAndServices() throws {
        let contents = """
        name: voice-ai
        services:
          backend:
            cmd: uvicorn app:app
          worker:
            cmd: celery -A app worker
        """
        let review = HunProjectInitReview(
            name: HunProjectInitReview.projectName(in: contents) ?? "",
            path: "/tmp/voice-ai",
            configPath: "/tmp/voice-ai/.hun.yml",
            configContents: contents,
            commandOutput: "",
            createdConfig: true
        )

        #expect(review.name == "voice-ai")
        #expect(review.serviceNames == ["backend", "worker"])
    }

    @Test func shellEnvironmentParsesNulSeparatedOutput() throws {
        let data = Data("PATH=/x/bin\0PNPM_HOME=/pnpm\0bad-key=nope\0SHELL=/bin/zsh\0".utf8)

        let environment = HunShellEnvironment.parseNulSeparatedEnvironment(data)

        #expect(environment["PATH"] == "/x/bin")
        #expect(environment["PNPM_HOME"] == "/pnpm")
        #expect(environment["SHELL"] == "/bin/zsh")
        #expect(environment["bad-key"] == nil)
    }

    @Test func agentSkillInstallerCopiesToGlobalSkillDirectories() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let source = home.appendingPathComponent("source")
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("agents"),
            withIntermediateDirectories: true
        )
        try """
        ---
        name: hun
        description: Create .hun.yml files.
        ---

        Use this skill for .hun.yml.
        """.write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "interface:\n  display_name: \"Hun Config\"\n".write(
            to: source.appendingPathComponent("agents/openai.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let installed = try HunAgentSkillInstaller.installSkill(from: source, homeDirectory: home)

        #expect(installed.map(\.path).sorted() == [
            home.appendingPathComponent(".agents/skills/hun/SKILL.md").path,
            home.appendingPathComponent(".claude/skills/hun/SKILL.md").path,
            home.appendingPathComponent(".codex/skills/hun/SKILL.md").path,
            home.appendingPathComponent(".cursor/skills/hun/SKILL.md").path
        ].sorted())
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".agents/skills/hun/agents/openai.yaml").path))
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/skills/hun/SKILL.md").path))
    }

    @Test func snapshotKeepsAllConfiguredServices() async throws {
        let client = MockDaemonClient()
        client.nextSnapshot = HunDaemonSnapshot(
            protocolVersion: 2,
            mode: "focus",
            activeProject: "voice-ai",
            scanDirs: ["/tmp/projects"],
            lastScanAt: nil,
            projects: [
                HunDaemonProject(
                    id: "voice-ai",
                    name: "voice-ai",
                    path: "/tmp/projects/voice-ai",
                    status: "stopped",
                    isActive: false,
                    branch: "main",
                    lastNote: nil,
                    startedAt: nil,
                    services: [
                        HunDaemonService(id: "web", name: "web", cmd: "bun run dev", pid: 0, port: 5173, status: "stopped", running: false, ready: false),
                        HunDaemonService(id: "api", name: "api", cmd: "bun run api", pid: 0, port: 8000, status: "stopped", running: false, ready: false),
                        HunDaemonService(id: "agent", name: "agent", cmd: "bun run agent", pid: 0, port: 0, status: "stopped", running: false, ready: false)
                    ],
                    configError: nil
                )
            ],
            warnings: []
        )
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)

        await store.refresh(force: true)

        #expect(store.model.projects.first?.services.map(\.name) == ["agent", "api", "web"])
    }

    @Test func addProjectRunsInitializerAndRefreshesSelection() async throws {
        let client = MockDaemonClient()
        let initializer = MockProjectInitializer()
        let projectURL = URL(fileURLWithPath: "/tmp/projects/newapp")
        initializer.nextReview = HunProjectInitReview(
            name: "newapp",
            path: projectURL.path,
            configPath: projectURL.appendingPathComponent(".hun.yml").path,
            configContents: "name: newapp\nservices:\n  web:\n    cmd: npm run dev\n",
            commandOutput: "Created .hun.yml",
            createdConfig: true
        )
        let registeredSnapshot = HunDaemonSnapshot(
            protocolVersion: 2,
            mode: "focus",
            activeProject: nil,
            scanDirs: ["/tmp/projects"],
            lastScanAt: nil,
            projects: [
                HunDaemonProject(
                    id: "newapp",
                    name: "newapp",
                    path: projectURL.path,
                    status: "stopped",
                    isActive: false,
                    branch: "main",
                    lastNote: nil,
                    startedAt: nil,
                    services: [],
                    configError: nil
                )
            ],
            warnings: []
        )
        client.nextSnapshot = registeredSnapshot
        let store = HunStore(
            client: client,
            supervisor: MockSupervisor(),
            projectInitializer: initializer,
            startAutomatically: false
        )

        await store.addProject(at: projectURL)

        #expect(initializer.urls == [projectURL])
        #expect(client.snapshotForces.isEmpty)
        #expect(store.pendingProjectReview?.path == projectURL.path)
        #expect(store.selectedProjectID == nil)

        await store.acceptPendingProject()

        #expect(client.actions.contains("register:/tmp/projects/newapp"))
        #expect(client.snapshotForces == [true])
        #expect(store.selectedProjectID == "newapp")
        #expect(store.pendingProjectReview == nil)
    }

    @Test func actionsSendDaemonRequestsAndRefresh() async throws {
        let client = MockDaemonClient()
        client.nextSnapshot = .fixture(activeProject: "app")
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)

        guard let project = store.model.projects.first else {
            Issue.record("missing project")
            return
        }

        store.run(project)

        try await waitUntil { client.actions.contains("start:app:parallel") }
        try await waitUntil { client.snapshotForces.contains(true) }

        guard let service = project.services.first else {
            Issue.record("missing service")
            return
        }

        store.focus(project)
        try await waitUntil { client.actions.contains("start:app:exclusive") }
        store.run(service, in: project)
        try await waitUntil { client.actions.contains("start:app:web:exclusive") }
        store.stop(project)
        try await waitUntil { client.actions.contains("stop:app") }
        store.restart(project)
        try await waitUntil { client.actions.contains("restart:app") }
        store.restart(service, in: project)
        try await waitUntil { client.actions.contains("restart:app:web") }
        store.stop(service, in: project)
        try await waitUntil { client.actions.contains("stop:app:web") }
        store.remove(service, from: project)
        try await waitUntil { client.actions.contains("remove:app:web") }
        store.globalMode = .multitask
        try await waitUntil { client.actions.contains("mode:multitask") }

        #expect(client.actions.contains("start:app:exclusive"))
        #expect(client.actions.contains("start:app:web:exclusive"))
        #expect(client.actions.contains("stop:app"))
        #expect(client.actions.contains("restart:app"))
        #expect(client.actions.contains("restart:app:web"))
        #expect(client.actions.contains("stop:app:web"))
        #expect(client.actions.contains("remove:app:web"))
        #expect(client.actions.contains("mode:multitask"))
    }

    @Test func projectActionsExposePendingState() async throws {
        let client = MockDaemonClient()
        client.startProjectDelay = .milliseconds(200)
        client.nextSnapshot = .fixture(activeProject: "app")
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)

        guard let project = store.model.projects.first else {
            Issue.record("missing project")
            return
        }

        store.run(project)

        try await waitUntil { store.projectAction(for: project) == .startProject }
        try await waitUntil { client.actions.contains("start:app:parallel") }
        try await waitUntil { store.projectAction(for: project) == nil }
    }

    @Test func logSubscriptionSwitchesBetweenServiceAndCombinedScopes() async throws {
        let client = MockDaemonClient()
        client.nextSnapshot = .fixture(activeProject: "app")
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)

        await store.refresh(force: true)

        #expect(client.subscriptions.last?.project == "app")
        #expect(client.subscriptions.last?.service == "web")
        #expect(client.logRequests.last?.service == "web")

        store.selectedLogScope = .combined
        try await Task.sleep(for: .milliseconds(50))

        #expect(client.subscriptions.last?.project == "app")
        #expect(client.subscriptions.last?.service == nil)
        #expect(client.logRequests.last?.service == nil)

        store.selectedLogScope = .service
        try await Task.sleep(for: .milliseconds(50))

        #expect(client.subscriptions.last?.service == "web")
    }

    @Test func removedProjectCleansSelectionAndTabs() async throws {
        let client = MockDaemonClient()
        client.nextSnapshot = .fixture(activeProject: "app")
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)
        store.selectProject("app")

        client.nextSnapshot = HunDaemonSnapshot(
            protocolVersion: 2,
            mode: "focus",
            activeProject: nil,
            scanDirs: [],
            lastScanAt: nil,
            projects: [],
            warnings: []
        )
        await store.refresh(force: true)

        #expect(store.selectedProjectID == nil)
        #expect(store.openTabIDs.isEmpty)
    }

    @Test func daemonErrorsSurfaceWithoutClearingState() async throws {
        let client = MockDaemonClient()
        client.nextSnapshot = .fixture(activeProject: "app")
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)

        client.error = TestError.boom
        await store.refresh(force: true)

        #expect(store.lastError == "boom")
        #expect(store.model.projects.count == 1)
    }

    @Test func transientDaemonTransportErrorsDoNotShowBanner() async throws {
        let client = MockDaemonClient()
        client.nextSnapshot = .fixture(activeProject: "app")
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)

        client.error = TestError.connectionClosed
        await store.refresh(force: true)

        #expect(store.lastError == nil)
        #expect(store.model.projects.count == 1)
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async throws {
        for _ in 0..<20 {
            if predicate() {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(predicate())
    }

    private func logLevel(_ text: String, isErr: Bool) -> LogLevel {
        HunLogLine(
            HunDaemonLogLine(
                timestamp: "2026-05-10T17:30:00Z",
                service: "web",
                project: "app",
                text: text,
                isErr: isErr
            )
        ).level
    }
}

private final class MockSupervisor: HunDaemonSupervisorProtocol {
    var restartCount = 0

    func ensureDaemon() async throws {}

    func restartDaemon() async throws {
        restartCount += 1
    }
}

private final class MockProjectInitializer: HunProjectInitializing {
    var urls: [URL] = []
    var error: Error?
    var nextReview = HunProjectInitReview(
        name: "newapp",
        path: "/tmp/projects/newapp",
        configPath: "/tmp/projects/newapp/.hun.yml",
        configContents: "name: newapp\nservices: {}\n",
        commandOutput: "",
        createdConfig: true
    )

    func initializeProject(at url: URL) async throws -> HunProjectInitReview {
        urls.append(url)
        if let error {
            throw error
        }
        return nextReview
    }
}

private final class MockDaemonClient: HunDaemonClientProtocol {
    var nextSnapshot = HunDaemonSnapshot.fixture(activeProject: "app")
    var nextDaemonInfo = HunDaemonInfo(
        status: "pong",
        protocolVersion: 11,
        version: "v0.2.1",
        commit: "abc1234",
        pid: 4242,
        startedAt: "2026-07-11T06:30:00Z"
    )
    var error: Error?
    var startProjectDelay: Duration?
    var actions: [String] = []
    var snapshotForces: [Bool] = []
    var logRequests: [(project: String, service: String?, lines: Int)] = []
    var subscriptions: [(project: String, service: String?)] = []
	var daemonInfoRequests = 0

	func daemonInfo() async throws -> HunDaemonInfo {
		if let error { throw error }
		daemonInfoRequests += 1
		return nextDaemonInfo
	}

    func snapshot(force: Bool) async throws -> HunDaemonSnapshot {
        if let error { throw error }
        snapshotForces.append(force)
        return nextSnapshot
    }

    func registerProject(path: String) async throws {
        actions.append("register:\(path)")
    }

    func startProject(_ project: String, mode: HunDaemonStartMode) async throws {
        if let startProjectDelay {
            try? await Task.sleep(for: startProjectDelay)
        }
        actions.append("start:\(project):\(mode.rawValue)")
    }

    func startService(_ project: String, service: String, mode: HunDaemonStartMode) async throws {
        actions.append("start:\(project):\(service):\(mode.rawValue)")
    }

    func setProjectIcon(_ project: String, path: String) async throws {
        actions.append("icon:\(project):\(path)")
    }

    func clearProjectIcon(_ project: String) async throws {
        actions.append("icon-clear:\(project)")
    }

    func stopProject(_ project: String) async throws {
        actions.append("stop:\(project)")
    }

    func stopService(_ project: String, service: String) async throws {
        actions.append("stop:\(project):\(service)")
    }

    func restartProject(_ project: String) async throws {
        actions.append("restart:\(project)")
    }

    func restartService(_ project: String, service: String) async throws {
        actions.append("restart:\(project):\(service)")
    }

    func removeService(_ project: String, service: String) async throws {
        actions.append("remove:\(project):\(service)")
    }

    func setMode(_ mode: HunMode) async throws {
        actions.append("mode:\(mode.rawValue)")
    }

    func logs(project: String, service: String?, lines: Int) async throws -> [HunDaemonLogLine] {
        logRequests.append((project, service, lines))
        return [
            HunDaemonLogLine(
                timestamp: "2026-05-10T17:30:00Z",
                service: service ?? "web",
                project: project,
                text: "ready",
                isErr: false
            )
        ]
    }

    func subscribe(
        project: String,
        service: String?,
        onLine: @escaping @Sendable (HunDaemonLogLine) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws -> HunLogSubscribing {
        subscriptions.append((project, service))
        return MockSubscription()
    }
}

private final class MockSubscription: HunLogSubscribing {
    func cancel() {}
}

private enum TestError: Error, LocalizedError {
    case boom
    case connectionClosed

    var errorDescription: String? {
        switch self {
        case .boom:
            return "boom"
        case .connectionClosed:
            return "connection closed"
        }
    }
}

private extension HunDaemonSnapshot {
    static func fixture(activeProject: String?) -> HunDaemonSnapshot {
        HunDaemonSnapshot(
            protocolVersion: 2,
            mode: "focus",
            activeProject: activeProject,
            scanDirs: ["/tmp/projects"],
            lastScanAt: nil,
            projects: [
                HunDaemonProject(
                    id: "app",
                    name: "app",
                    path: "/tmp/projects/app",
                    iconPath: "/tmp/projects/app/logo.png",
                    iconCustom: true,
                    status: "running",
                    isActive: true,
                    branch: "main",
                    lastNote: "ship it",
                    startedAt: "2026-05-10T17:00:00Z",
                    services: [
                        HunDaemonService(
                            id: "web",
                            name: "web",
                            cmd: "npm run dev",
                            pid: 123,
                            port: 3000,
                            status: "running",
                            running: true,
                            ready: true
                        )
                    ],
                    configError: nil
                )
            ],
            warnings: []
        )
    }
}

private extension HunDaemonProject {
    static func fixtureProject(path: String) -> HunDaemonProject {
        HunDaemonProject(
            id: "shop",
            name: "shop",
            path: path,
            status: "stopped",
            isActive: false,
            branch: "main",
            lastNote: nil,
            startedAt: nil,
            services: [
                HunDaemonService(
                    id: "web",
                    name: "web",
                    cmd: "npm run dev",
                    pid: 0,
                    port: 3000,
                    status: "stopped",
                    running: false,
                    ready: false
                )
            ],
            configError: nil
        )
    }
}
