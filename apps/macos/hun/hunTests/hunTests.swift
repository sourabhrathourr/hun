import AppKit
import Darwin
import Foundation
import Testing
@testable import hun

@MainActor
struct hunTests {
    @Test func gitDiffDocumentHidesPatchMetadataAndTracksLineNumbers() {
        let patch = """
        diff --git a/Sample.swift b/Sample.swift
        index 1111111..2222222 100644
        --- a/Sample.swift
        +++ b/Sample.swift
        @@ -10,3 +10,4 @@ func render() {
         let stable = true
        -let oldValue = 1
        +let newValue = 2
        +let extraValue = 3
         return stable
        """

        let document = HunGitDiffDocument(patch: patch)

        #expect(document.lines.map(\.kind) == [.context, .deletion, .addition, .addition, .context])
        #expect(document.lines.map(\.content) == [
            "let stable = true",
            "let oldValue = 1",
            "let newValue = 2",
            "let extraValue = 3",
            "return stable"
        ])
        #expect(document.lines.map(\.oldLineNumber) == [10, 11, nil, nil, 12])
        #expect(document.lines.map(\.newLineNumber) == [10, nil, 11, 12, 13])
    }

    @Test func gitDiffDocumentPairsChangesForSplitReview() throws {
        let patch = """
        @@ -1,3 +1,4 @@
         unchanged
        -old
        +new
        +extra
         tail
        """

        let document = HunGitDiffDocument(patch: patch)
        let rows = document.splitRows
        let lines = document.lines

        #expect(rows.count == 4)
        #expect(rows[0].left(in: lines)?.content == "unchanged")
        #expect(rows[0].right(in: lines)?.content == "unchanged")
        #expect(rows[1].left(in: lines)?.content == "old")
        #expect(rows[1].right(in: lines)?.content == "new")
        #expect(rows[2].left(in: lines) == nil)
        #expect(rows[2].right(in: lines)?.content == "extra")
        #expect(rows[3].left(in: lines)?.oldLineNumber == 3)
        #expect(rows[3].right(in: lines)?.newLineNumber == 4)
    }

    @Test func gitDiffDocumentHandlesOneHundredThousandChangedLines() {
        let patch = "@@ -0,0 +1,100000 @@\n" + String(repeating: "+expanded line\n", count: 100_000)

        let document = HunGitDiffDocument(patch: patch)

        #expect(document.lines.count == 100_000)
        #expect(document.splitRows.count == 100_000)
        #expect(document.lines.last?.newLineNumber == 100_000)
    }

    @Test func unixSocketLineReaderPreservesCoalescedRecordsAfterLargeResponse() async throws {
        var sockets = [Int32](repeating: 0, count: 2)
        try #require(Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
        let writeSocket = sockets[0]
        let readSocket = sockets[1]
        defer {
            Darwin.close(writeSocket)
            Darwin.close(readSocket)
        }

        let payload = Data(repeating: 0x41, count: 1_000_000)
        let writer = Task.detached {
            try UnixSocket.writeAll(
                socket: writeSocket,
                payload: payload + Data([0x0A]) + Data("next record\n".utf8)
            )
        }

        let reader = UnixSocketLineReader(socket: readSocket)
        let response = try reader.readLine()
        let nextRecord = try reader.readLine()
        try await writer.value

        #expect(response.count == payload.count)
        #expect(response == payload)
        #expect(nextRecord == Data("next record".utf8))
    }

    @Test func gitWorkspaceModelLoadsRepositoryAndCoordinatesFileActions() async throws {
        let client = MockGitClient()
        client.status = .fixture()
        client.branches = [
            HunGitBranch(name: "main", current: true, remote: false, upstream: "origin/main", updatedAt: 10),
            HunGitBranch(name: "feature/ui", current: false, remote: false, upstream: nil, updatedAt: 9)
        ]
        client.diff = HunGitDiff(
            path: "ContentView.swift",
            staged: false,
            content: "@@ -1 +1 @@\n-old\n+new\n",
            binary: false,
            truncated: false
        )
        let model = HunGitWorkspaceModel(client: client)

        await model.load(projectID: "app")
        await model.loadBranches()
        let change = try #require(model.status?.files.first)
        await model.loadDiff(for: change, staged: false)

        #expect(model.status?.branch == "main")
        #expect(model.status?.changeCount == 1)
        #expect(model.branches.map(\.name) == ["main", "feature/ui"])
        #expect(model.selectedDiffDocument?.lines.last?.content == "new")

        await model.stage(change)

        #expect(client.actions == ["stage:app:ContentView.swift"])
        #expect(model.status?.files.first?.staged == true)
        #expect(model.errorMessage == nil)
    }

    @Test func presentingGitWorkspaceSelectsTheFirstWorkingTreeChange() async {
        let client = MockGitClient()
        client.diff = HunGitDiff(
            path: "ContentView.swift",
            staged: false,
            content: "@@ -1 +1 @@\n-old\n+new\n",
            binary: false,
            truncated: false
        )
        let model = HunGitWorkspaceModel(client: client)
        await model.load(projectID: "app")

        await model.presentWorkspace()

        #expect(model.isWorkspacePresented)
        #expect(model.selectedPath == "ContentView.swift")
        #expect(model.selectedDiffDocument?.lines.count == 2)
    }

    @Test func switchingProjectsDuringDiffLoadDoesNotLeaveGitBusy() async throws {
        let client = MockGitClient()
        client.diffDelay = .milliseconds(80)
        client.diff = HunGitDiff(
            path: "ContentView.swift",
            staged: false,
            content: "@@ -1 +1 @@\n-old\n+new\n",
            binary: false,
            truncated: false
        )
        let model = HunGitWorkspaceModel(client: client)
        await model.load(projectID: "first")
        let change = try #require(model.status?.files.first)

        let loadingDiff = Task {
            await model.loadDiff(for: change, staged: false)
        }
        try await Task.sleep(for: .milliseconds(20))
        await model.load(projectID: "second")
        await loadingDiff.value

        #expect(model.operation == nil)
        #expect(model.status?.isRepository == true)
        #expect(model.selectedDiffDocument == nil)
    }

    @Test func silentGitRefreshCannotOverwriteMutationOrDismissActionError() async throws {
        let client = MockGitClient()
        client.statusDelay = .milliseconds(80)
        let model = HunGitWorkspaceModel(client: client)
        await model.load(projectID: "app")
        let change = try #require(model.status?.files.first)

        let refresh = Task { await model.refresh(silently: true) }
        try await Task.sleep(for: .milliseconds(20))
        await model.stage(change)
        model.errorMessage = "Switch requires a clean working tree."
        await refresh.value

        #expect(model.status?.files.first?.staged == true)
        #expect(model.errorMessage == "Switch requires a clean working tree.")
    }

    @Test func failedGitFetchKeepsItsErrorVisible() async {
        let client = MockGitClient()
        let model = HunGitWorkspaceModel(client: client)
        await model.load(projectID: "app")
        client.fetchError = TestError.boom

        await model.fetch()

        #expect(model.errorMessage == "boom")
        #expect(client.branchRequests == 0)
    }

    @Test func failedGitStageDoesNotReloadDiffOrHideItsError() async throws {
        let client = MockGitClient()
        client.status.files[0] = HunGitFileChange(
            path: "ContentView.swift",
            originalPath: nil,
            indexStatus: "M",
            worktreeStatus: "M",
            untracked: false,
            conflicted: false
        )
        let model = HunGitWorkspaceModel(client: client)
        await model.load(projectID: "app")
        let change = try #require(model.status?.files.first)
        client.stageError = TestError.boom

        await model.stage(change)

        #expect(model.errorMessage == "boom")
        #expect(client.diffRequests == 0)
    }

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

    @Test func dashboardNavigationRestoresLastVisibleProject() async throws {
        let suiteName = "hunTests.navigation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let snapshot = HunDaemonSnapshot.fixture(activeProject: "app")
            .appending(.fixtureProject(path: "/tmp/projects/shop"))

        let firstClient = MockDaemonClient()
        firstClient.nextSnapshot = snapshot
        let firstStore = HunStore(
            client: firstClient,
            supervisor: MockSupervisor(),
            navigationDefaults: defaults,
            startAutomatically: false
        )
        await firstStore.refresh(force: true)
        firstStore.selectProject("shop")
        firstStore.selectedLogScope = .combined

        #expect(defaults.string(forKey: "hun.dashboard.logScope") == "combined")

        let restoredClient = MockDaemonClient()
        restoredClient.nextSnapshot = snapshot
        let restoredStore = HunStore(
            client: restoredClient,
            supervisor: MockSupervisor(),
            navigationDefaults: defaults,
            startAutomatically: false
        )
        #expect(restoredStore.selectedLogScope == .combined)
        await restoredStore.refresh(force: true)

        #expect(restoredStore.selectedProjectID == "shop")
        #expect(restoredStore.openTabIDs.contains("shop"))
        #expect(restoredStore.selectedServiceID == "web")
        #expect(restoredStore.selectedLogScope == .combined)
    }

    @Test func focusSwitchSelectsProjectForDashboardImmediately() async throws {
        let client = MockDaemonClient()
        client.nextSnapshot = HunDaemonSnapshot.fixture(activeProject: "app")
            .appending(.fixtureProject(path: "/tmp/projects/shop"))
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)
        let project = try #require(store.project(id: "shop"))

        store.focus(project)

        #expect(store.selectedProjectID == "shop")
        #expect(store.openTabIDs.contains("shop"))
        try await waitUntil { client.actions.contains("start:shop:exclusive") }
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

    @Test func projectWithoutGitBranchDoesNotInventUnknownBranch() throws {
        let snapshot = HunDaemonProject(
            id: "plain-folder",
            name: "plain-folder",
            path: "/tmp/plain-folder",
            status: "stopped",
            isActive: false,
            branch: nil,
            lastNote: nil,
            startedAt: nil,
            services: [],
            configError: nil
        )

        let project = HunProject(snapshot: snapshot, activeID: nil, logs: [])

        #expect(project.branch == nil)
    }

    @Test func runningServiceBuildsLocalBrowserURLWithoutChangingPortMetadata() throws {
        let running = HunService(snapshot: HunDaemonService(
            id: "web",
            name: "web",
            cmd: "bun run dev",
            pid: 4242,
            port: 5173,
            status: "running",
            running: true,
            ready: true
        ))
        let stopped = HunService(snapshot: HunDaemonService(
            id: "api",
            name: "api",
            cmd: "go run .",
            pid: 0,
            port: 4000,
            status: "stopped",
            running: false,
            ready: false
        ))

        #expect(running.portText == ":5173")
        #expect(running.browserURL?.absoluteString == "http://localhost:5173")
        #expect(stopped.browserURL == nil)
    }

    @Test func daemonSettingsLoadsHealthAndRestartsDaemon() async throws {
        let client = MockDaemonClient()
        client.nextDaemonInfo = HunDaemonInfo(
            status: "pong",
            protocolVersion: 13,
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

    @Test func daemonRestartFallsBackToPIDFromHeldLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let lockPath = directory.appendingPathComponent("daemon.lock").path
        try "4242".write(toFile: lockPath, atomically: true, encoding: .utf8)
        let fd = Darwin.open(lockPath, O_RDWR)
        #expect(fd >= 0)
        defer {
            _ = hunSystemFlock(fd, LOCK_UN)
            _ = Darwin.close(fd)
        }
        #expect(hunSystemFlock(fd, LOCK_EX | LOCK_NB) == 0)

        let missingPIDPath = directory.appendingPathComponent("daemon.pid").path
        #expect(resolvedDaemonProcessID(reportedPID: 0, pidPath: missingPIDPath, lockPath: lockPath) == 4242)
    }

    @Test func daemonRestartDoesNotTrustPIDFromUnlockedLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let lockPath = directory.appendingPathComponent("daemon.lock").path
        try "4242".write(toFile: lockPath, atomically: true, encoding: .utf8)
        let missingPIDPath = directory.appendingPathComponent("daemon.pid").path

        #expect(resolvedDaemonProcessID(reportedPID: 0, pidPath: missingPIDPath, lockPath: lockPath) == nil)
    }

    @Test func daemonTerminationWaitsForForcedExit() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); print('ready', flush=True); time.sleep(30)"
        ]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        defer {
            if process.isRunning {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
        _ = output.fileHandleForReading.availableData

        try terminateDaemonProcess(process.processIdentifier, gracefulTimeout: 0.1, forcedTimeout: 1)
        process.waitUntilExit()

        #expect(!daemonProcessExists(process.processIdentifier))
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
        let snapshotsBeforeModeChange = client.snapshotForces.count
        store.changeMode(.multitask, preferredProject: nil)
        try await waitUntil {
            client.actions.contains("mode:multitask:none") &&
                client.snapshotForces.count > snapshotsBeforeModeChange
        }
        store.changeMode(.focus, preferredProject: "app")
        try await waitUntil { client.actions.contains("mode:focus:app") }

        #expect(client.actions.contains("start:app:exclusive"))
        #expect(client.actions.contains("start:app:web:exclusive"))
        #expect(client.actions.contains("stop:app"))
        #expect(client.actions.contains("restart:app"))
        #expect(client.actions.contains("restart:app:web"))
        #expect(client.actions.contains("stop:app:web"))
        #expect(client.actions.contains("remove:app:web"))
        #expect(client.actions.contains("mode:multitask:none"))
        #expect(client.actions.contains("mode:focus:app"))
    }

    @Test func rapidModeChangesApplyLatestIntentLast() async throws {
        let client = MockDaemonClient()
        client.modeChangeDelay = .milliseconds(100)
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)

        store.changeMode(.multitask, preferredProject: nil)
        store.changeMode(.focus, preferredProject: "app")

        try await waitUntil { client.actions.last == "mode:focus:app" }

        #expect(store.globalMode == .focus)
        #expect(client.actions.last == "mode:focus:app")
    }

    @Test func modeChangeWithoutDashboardPreferenceDoesNotUseHiddenSelection() async throws {
        let client = MockDaemonClient()
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)

        store.changeMode(.multitask, preferredProject: nil)
        try await waitUntil { client.actions.contains("mode:multitask:none") }
        store.changeMode(.focus, preferredProject: nil)
        try await waitUntil { client.actions.contains("mode:focus:none") }

        #expect(client.actions.contains("mode:focus:none"))
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

    @Test func terminalLaunchConfigurationUsesProjectAndLoginShellEnvironment() throws {
        let configuration = HunTerminalLaunchConfiguration.projectShell(
            rootPath: "/tmp/projects/app",
            environment: [
                "SHELL": "/bin/zsh",
                "PATH": "/opt/homebrew/bin:/usr/bin",
                "TERM_SESSION_ID": "stale",
                "TOKEN": "part=with=equals"
            ]
        )

        #expect(configuration.executable == "/bin/zsh")
        #expect(configuration.execName == "-zsh")
        #expect(configuration.currentDirectory == "/tmp/projects/app")
        #expect(configuration.environment.contains("PWD=/tmp/projects/app"))
        #expect(configuration.environment.contains("HUN_PROJECT_ROOT=/tmp/projects/app"))
        #expect(configuration.environment.contains("TERM=xterm-256color"))
        #expect(configuration.environment.contains("COLORTERM=truecolor"))
        #expect(configuration.environment.contains("TOKEN=part=with=equals"))
        #expect(!configuration.environment.contains(where: { $0.hasPrefix("TERM_SESSION_ID=") }))
        #expect(configuration.environment == configuration.environment.sorted())
    }

    @Test func terminalLaunchConfigurationFallsBackFromInvalidShell() {
        let configuration = HunTerminalLaunchConfiguration.projectShell(
            rootPath: "/tmp/projects/app",
            environment: ["SHELL": "/missing/not-a-shell"]
        )

        #expect(configuration.executable == "/bin/zsh")
        #expect(configuration.execName == "-zsh")
        #expect(configuration.environment.contains("SHELL=/bin/zsh"))
    }

    @Test func terminalPanelHeightPreservesWorkspaceAndMinimumTerminalSize() {
        #expect(HunTerminalPanelMetrics.clamp(80, availableHeight: 700) == 164)
        #expect(HunTerminalPanelMetrics.clamp(900, availableHeight: 700) == 530)
        #expect(HunTerminalPanelMetrics.clamp(280, availableHeight: 700) == 280)
    }

    @Test func sleekScrollbarsOverlayContentWithoutChangingItsWidth() throws {
        let scrollView = HunStyledScrollView(
            frame: NSRect(x: 0, y: 0, width: 240, height: 180)
        )
        scrollView.hasVerticalScroller = true
        scrollView.enableHorizontalScroller()
        scrollView.documentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 640)
        )
        scrollView.layoutSubtreeIfNeeded()

        let scroller = try #require(scrollView.verticalScroller as? HunOverlayScroller)
        let horizontalScroller = try #require(
            scrollView.horizontalScroller as? HunOverlayScroller
        )
        let restingWidth = scrollView.contentView.bounds.width
        let restingHeight = scrollView.contentView.bounds.height

        scroller.setRevealed(true, animated: false)
        horizontalScroller.setRevealed(true, animated: false)
        scrollView.tile()
        let revealedWidth = scrollView.contentView.bounds.width
        let revealedHeight = scrollView.contentView.bounds.height

        #expect(scroller.alphaValue == 1)
        #expect(horizontalScroller.alphaValue == 1)
        #expect(revealedWidth == restingWidth)
        #expect(revealedHeight == restingHeight)
        #expect(scrollView.scrollerStyle == .overlay)
        #expect(HunScrollStyleMetrics.thumbWidth == 2)
        #expect(HunScrollStyleMetrics.thumbOpacity < 0.3)
        #expect(
            HunOverlayScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)
                == HunScrollStyleMetrics.laneWidth
        )

        scroller.setRevealed(false, animated: false)
        horizontalScroller.setRevealed(false, animated: false)
        #expect(scroller.alphaValue == 0)
        #expect(horizontalScroller.alphaValue == 0)
    }

    @Test func terminalDirectoryNormalizesShellFileURLs() {
        #expect(
            HunTerminalSession.normalizedDirectory(
                "file://mac.local/Users/me/Side%20Projects/hun"
            ) == "/Users/me/Side Projects/hun"
        )
        #expect(HunTerminalSession.normalizedDirectory("/tmp/hun") == "/tmp/hun")
    }

    @Test func terminalControllerPreservesOneSessionPerProject() async throws {
        let suiteName = "hunTests.terminal.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var engines: [MockTerminalEngine] = []
        let controller = HunTerminalController(
            engineFactory: {
                let engine = MockTerminalEngine()
                engines.append(engine)
                return engine
            },
            environmentProvider: {
                ["SHELL": "/bin/zsh", "PATH": "/usr/bin:/bin"]
            },
            defaults: defaults
        )

        let first = controller.show(
            project: HunTerminalProjectContext(
                id: "app",
                name: "App",
                rootPath: "/tmp/projects/app"
            )
        )
        try await waitUntil { engines.first?.startCount == 1 }
        controller.hide()
        let restored = controller.show(
            project: HunTerminalProjectContext(
                id: "app",
                name: "App",
                rootPath: "/tmp/projects/app"
            )
        )

        #expect(first === restored)
        #expect(engines.count == 1)
        #expect(engines[0].startCount == 1)
        #expect(engines[0].lastConfiguration?.currentDirectory == "/tmp/projects/app")

        controller.clearActiveTerminal()
        #expect(engines[0].clearCount == 1)

        controller.hide()
        controller.clearActiveTerminal()
        #expect(engines[0].clearCount == 1)

        _ = controller.show(
            project: HunTerminalProjectContext(
                id: "app",
                name: "App",
                rootPath: "/tmp/projects/app"
            )
        )
        controller.projectDidChange(
            HunTerminalProjectContext(
                id: "shop",
                name: "Shop",
                rootPath: "/tmp/projects/shop"
            )
        )
        try await waitUntil { engines.count == 2 && engines[1].startCount == 1 }
        controller.pruneSessions(validProjectIDs: ["shop"])

        #expect(engines[0].terminateCount == 1)
        #expect(engines[1].terminateCount == 0)
    }

    @Test func terminalControllerBoundsRetainedShellProcesses() {
        var engines: [MockTerminalEngine] = []
        let controller = HunTerminalController(
            engineFactory: {
                let engine = MockTerminalEngine()
                engines.append(engine)
                return engine
            },
            environmentProvider: { [:] },
            defaults: nil
        )

        for index in 0...HunTerminalController.maximumRetainedSessionCount {
            _ = controller.session(
                for: HunTerminalProjectContext(
                    id: "project-\(index)",
                    name: "Project \(index)",
                    rootPath: "/tmp/project-\(index)"
                )
            )
        }

        #expect(engines.count == HunTerminalController.maximumRetainedSessionCount + 1)
        #expect(engines[0].terminateCount == 1)
        #expect(engines.dropFirst().allSatisfy { $0.terminateCount == 0 })
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

@MainActor
private final class MockTerminalEngine: HunTerminalEngine {
    weak var delegate: (any HunTerminalEngineDelegate)?
    let view = NSView(frame: .zero)
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var clearCount = 0
    private(set) var resetCount = 0
    private(set) var terminateCount = 0
    private(set) var focusCount = 0
    private(set) var lastConfiguration: HunTerminalLaunchConfiguration?

    func start(configuration: HunTerminalLaunchConfiguration) {
        startCount += 1
        lastConfiguration = configuration
        isRunning = true
    }

    func reset() {
        resetCount += 1
    }

    func clear() {
        clearCount += 1
    }

    func terminate() {
        terminateCount += 1
        isRunning = false
    }

    func focus() {
        focusCount += 1
    }
}

private final class MockSupervisor: HunDaemonSupervisorProtocol {
    var restartCount = 0

    func ensureDaemon() async throws {}

    func restartDaemon() async throws {
        restartCount += 1
    }
}

private final class MockGitClient: HunGitClientProtocol {
    var status = HunGitStatus.fixture()
    var branches: [HunGitBranch] = []
    var diff = HunGitDiff(path: "", staged: false, content: "", binary: false, truncated: false)
    var statusDelay: Duration?
    var diffDelay: Duration?
    var fetchError: Error?
    var stageError: Error?
    var branchRequests = 0
    var diffRequests = 0
    var actions: [String] = []

    func gitStatus(project: String) async throws -> HunGitStatus {
        let result = status
        if let statusDelay {
            try? await Task.sleep(for: statusDelay)
        }
        return result
    }

    func gitBranches(project: String) async throws -> [HunGitBranch] {
        branchRequests += 1
        return branches
    }

    func gitDiff(project: String, path: String, staged: Bool) async throws -> HunGitDiff {
        diffRequests += 1
        let result = diff
        if let diffDelay {
            try? await Task.sleep(for: diffDelay)
        }
        return result
    }

    func gitStage(project: String, path: String) async throws -> HunGitStatus {
        actions.append("stage:\(project):\(path)")
        if let stageError {
            throw stageError
        }
        status.files[0] = HunGitFileChange(
            path: status.files[0].path,
            originalPath: status.files[0].originalPath,
            indexStatus: "M",
            worktreeStatus: ".",
            untracked: false,
            conflicted: false
        )
        return status
    }

    func gitUnstage(project: String, path: String) async throws -> HunGitStatus {
        actions.append("unstage:\(project):\(path)")
        return status
    }

    func gitCommit(project: String, message: String) async throws -> HunGitStatus {
        actions.append("commit:\(project):\(message)")
        return status
    }

    func gitCreateBranch(project: String, branch: String) async throws -> HunGitStatus {
        actions.append("create:\(project):\(branch)")
        return status
    }

    func gitSwitchBranch(project: String, branch: String, stash: Bool) async throws -> HunGitStatus {
        actions.append("switch:\(project):\(branch):\(stash)")
        return status
    }

    func gitFetch(project: String) async throws -> HunGitStatus {
        actions.append("fetch:\(project)")
        if let fetchError {
            throw fetchError
        }
        return status
    }

    func gitPull(project: String) async throws -> HunGitStatus {
        actions.append("pull:\(project)")
        return status
    }

    func gitPush(project: String) async throws -> HunGitStatus {
        actions.append("push:\(project)")
        return status
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

private extension HunGitStatus {
    static func fixture() -> HunGitStatus {
        HunGitStatus(
            isRepository: true,
            branch: "main",
            head: "abc123",
            upstream: "origin/main",
            ahead: 0,
            behind: 0,
            detached: false,
            clean: false,
            operation: nil,
            files: [
                HunGitFileChange(
                    path: "ContentView.swift",
                    originalPath: nil,
                    indexStatus: ".",
                    worktreeStatus: "M",
                    untracked: false,
                    conflicted: false
                )
            ]
        )
    }
}

private final class MockDaemonClient: HunDaemonClientProtocol {
    var nextSnapshot = HunDaemonSnapshot.fixture(activeProject: "app")
    var nextDaemonInfo = HunDaemonInfo(
        status: "pong",
        protocolVersion: 13,
        version: "v0.2.1",
        commit: "abc1234",
        pid: 4242,
        startedAt: "2026-07-11T06:30:00Z"
    )
    var error: Error?
    var startProjectDelay: Duration?
    var modeChangeDelay: Duration?
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

    func setMode(_ mode: HunMode, preferredProject: String?) async throws {
        if let modeChangeDelay {
            try? await Task.sleep(for: modeChangeDelay)
        }
        nextSnapshot = nextSnapshot.replacingMode(mode.rawValue)
        actions.append("mode:\(mode.rawValue):\(preferredProject ?? "none")")
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

    func replacingMode(_ mode: String) -> HunDaemonSnapshot {
        HunDaemonSnapshot(
            protocolVersion: protocolVersion,
            mode: mode,
            activeProject: activeProject,
            scanDirs: scanDirs,
            lastScanAt: lastScanAt,
            projects: projects,
            warnings: warnings
        )
    }

    func appending(_ project: HunDaemonProject) -> HunDaemonSnapshot {
        HunDaemonSnapshot(
            protocolVersion: protocolVersion,
            mode: mode,
            activeProject: activeProject,
            scanDirs: scanDirs,
            lastScanAt: lastScanAt,
            projects: projects + [project],
            warnings: warnings
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
