import AppKit
import Darwin
import Foundation
import SwiftUI
import Testing
@testable import hun

private enum ThemeTestError: Error {
    case unavailableAppearance
    case unresolvableColor
}

@MainActor
struct hunTests {
    @Test func appThemeUsesCreamCanvasInLightMode() throws {
        let color = try themeComponents(AppTheme.appBackground, appearance: .aqua)
        let sidebar = try themeComponents(AppTheme.sidebar, appearance: .aqua)

        #expect(abs(color.red - 247.0 / 255.0) < 0.0001)
        #expect(abs(color.green - 247.0 / 255.0) < 0.0001)
        #expect(abs(color.blue - 242.0 / 255.0) < 0.0001)
        #expect(abs(color.alpha - 1) < 0.0001)
        #expect(abs(sidebar.red - 242.0 / 255.0) < 0.0001)
        #expect(abs(sidebar.green - 242.0 / 255.0) < 0.0001)
        #expect(abs(sidebar.blue - 236.0 / 255.0) < 0.0001)
    }

    @Test func appThemePreservesOriginalDarkCanvasAndRaisedSurface() throws {
        let canvas = try themeComponents(AppTheme.appBackground, appearance: .darkAqua)
        let raised = try themeComponents(AppTheme.elevated, appearance: .darkAqua)

        #expect(abs(canvas.red - 3.0 / 255.0) < 0.0001)
        #expect(abs(canvas.green - 3.0 / 255.0) < 0.0001)
        #expect(abs(canvas.blue - 3.0 / 255.0) < 0.0001)
        #expect(abs(raised.red - 0.105) < 0.0001)
        #expect(abs(raised.green - 0.105) < 0.0001)
        #expect(abs(raised.blue - 0.110) < 0.0001)
    }

    @Test func modeSelectorsUseWhiteActiveTabsInLightModeWithoutChangingDarkMode() throws {
        let lightActive = try themeComponents(AppTheme.modeSelectorActive, appearance: .aqua)
        let lightBackground = try themeComponents(AppTheme.modeSelectorBackground, appearance: .aqua)
        let darkActive = try themeComponents(AppTheme.modeSelectorActive, appearance: .darkAqua)
        let darkBackground = try themeComponents(AppTheme.modeSelectorBackground, appearance: .darkAqua)

        #expect(abs(lightActive.red - 1) < 0.0001)
        #expect(abs(lightActive.green - 1) < 0.0001)
        #expect(abs(lightActive.blue - 1) < 0.0001)
        #expect(abs(lightActive.alpha - 1) < 0.0001)
        #expect(abs(lightBackground.red - 242.0 / 255.0) < 0.0001)
        #expect(abs(lightBackground.green - 242.0 / 255.0) < 0.0001)
        #expect(abs(lightBackground.blue - 236.0 / 255.0) < 0.0001)
        #expect(abs(darkActive.alpha - 0.055) < 0.0001)
        #expect(abs(darkBackground.alpha - 0.035) < 0.0001)
    }

    @Test func storedBetaLicenseValidityComesFromDodo() async {
        let service = MockLicenseService()
        let previousValidation = Date(timeIntervalSince1970: 1_000)
        let currentDate = Date(timeIntervalSince1970: 2_000)
        let store = InMemoryLicenseStore(
            license: HunStoredLicense(
                licenseKey: "test-license",
                instanceID: "lki_test",
                productID: "beta",
                productName: "Hun Public Beta",
                lastValidatedAt: previousValidation
            )
        )
        let configuration = HunLicenseConfiguration(
            apiBaseURL: URL(string: "https://test.dodopayments.com")!,
            allowedProductIDs: ["beta"],
            checkoutURL: URL(string: "https://hun.sh")!,
            offlineGracePeriod: 72 * 60 * 60
        )
        let manager = HunLicenseManager(
            configuration: configuration,
            service: service,
            store: store,
            now: { currentDate }
        )

        await manager.restore()

        #expect(service.validatedInstances == ["lki_test"])
        #expect(
            manager.state == .active(
                HunLicenseSession(
                    productID: "beta",
                    productName: "Hun Public Beta",
                    lastValidatedAt: currentDate,
                    isOffline: false
                )
            )
        )
    }

    private func themeComponents(
        _ color: Color,
        appearance name: NSAppearance.Name
    ) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        guard let appearance = NSAppearance(named: name) else {
            throw ThemeTestError.unavailableAppearance
        }
        var components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)?
        appearance.performAsCurrentDrawingAppearance {
            guard let resolved = NSColor(color).usingColorSpace(.sRGB) else { return }
            components = (
                resolved.redComponent,
                resolved.greenComponent,
                resolved.blueComponent,
                resolved.alphaComponent
            )
        }
        guard let components else {
            throw ThemeTestError.unresolvableColor
        }
        return components
    }

    @Test func anEndedBetaLicenseAsksForAPaidOneAndRemembersIt() async {
        let defaults = UserDefaults(suiteName: "hun-tests-\(UUID().uuidString)")!
        let service = MockLicenseService()
        service.isValid = false
        let store = InMemoryLicenseStore(license: HunStoredLicense(
            licenseKey: "beta-key",
            instanceID: "lki_beta",
            productID: "beta",
            productName: "Hun Public Beta",
            lastValidatedAt: Date(timeIntervalSince1970: 1_000)
        ))
        let configuration = HunLicenseConfiguration(
            apiBaseURL: URL(string: "https://test.dodopayments.com")!,
            allowedProductIDs: ["paid", "beta"],
            checkoutURL: URL(string: "https://hun.sh")!,
            offlineGracePeriod: 72 * 60 * 60,
            betaProductIDs: ["beta"]
        )
        let manager = HunLicenseManager(
            configuration: configuration,
            service: service,
            store: store,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        await manager.restore()
        #expect(manager.state == .needsActivation)
        #expect(manager.betaEnded)
        #expect(manager.errorMessage == nil)
        #expect((try? store.load()) == nil)

        // Still says so after a relaunch, until a new key is activated.
        let relaunched = HunLicenseManager(
            configuration: configuration,
            service: service,
            store: store,
            defaults: defaults
        )
        #expect(relaunched.betaEnded)
        await relaunched.activate("paid-key")
        #expect(relaunched.isLicensed)
        #expect(!relaunched.betaEnded)
        #expect(!defaults.bool(forKey: "HunBetaEnded"))
    }

    @Test func anInvalidPaidLicenseExplainsItselfWithoutMentioningTheBeta() async {
        let service = MockLicenseService()
        service.isValid = false
        let manager = HunLicenseManager(
            configuration: HunLicenseConfiguration(
                apiBaseURL: URL(string: "https://test.dodopayments.com")!,
                allowedProductIDs: ["paid"],
                checkoutURL: URL(string: "https://hun.sh")!,
                offlineGracePeriod: 72 * 60 * 60,
                betaProductIDs: ["beta"]
            ),
            service: service,
            store: InMemoryLicenseStore(license: HunStoredLicense(
                licenseKey: "paid-key",
                instanceID: "lki_paid",
                productID: "paid",
                productName: "Hun",
                lastValidatedAt: Date(timeIntervalSince1970: 1_000)
            )),
            defaults: UserDefaults(suiteName: "hun-tests-\(UUID().uuidString)")!,
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        await manager.restore()
        #expect(manager.state == .needsActivation)
        #expect(!manager.betaEnded)
        #expect(manager.errorMessage == "This license is no longer valid.")
    }

    @Test func recheckingOnlyRunsForAnActiveLicense() async {
        let service = MockLicenseService()
        let manager = HunLicenseManager(
            configuration: HunLicenseConfiguration(
                apiBaseURL: URL(string: "https://test.dodopayments.com")!,
                allowedProductIDs: ["beta"],
                checkoutURL: URL(string: "https://hun.sh")!,
                offlineGracePeriod: 72 * 60 * 60
            ),
            service: service,
            store: InMemoryLicenseStore(),
            defaults: UserDefaults(suiteName: "hun-tests-\(UUID().uuidString)")!
        )
        await manager.restore()
        await manager.recheck()
        #expect(service.validatedInstances.isEmpty)
        #expect(manager.state == .needsActivation)
    }

    @Test func bundledCLIIsLinkedOntoThePATHWithoutTouchingTheUsersOwn() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cli-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func app(_ name: String) throws -> URL {
            let cli = root.appendingPathComponent("\(name)/hun.app/Contents/Resources/hun")
            try fm.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: cli)
            return cli
        }
        let cli = try app("New")
        let missing = root.appendingPathComponent("missing-bin")
        let shared = root.appendingPathComponent("shared-bin")
        let local = root.appendingPathComponent("home/.local/bin")
        try fm.createDirectory(at: shared, withIntermediateDirectories: true)

        // The first folder that exists and is writable gets the link.
        let linked = HunCLILinker.link(cli: cli, into: [missing, shared, local])
        #expect(linked == shared.appendingPathComponent("hun"))
        #expect(try fm.destinationOfSymbolicLink(atPath: shared.appendingPathComponent("hun").path) == cli.path)

        // Hun's own link follows the app when it moves.
        let moved = try app("Moved")
        #expect(HunCLILinker.link(cli: moved, into: [missing, shared, local]) == shared.appendingPathComponent("hun"))
        #expect(try fm.destinationOfSymbolicLink(atPath: shared.appendingPathComponent("hun").path) == moved.path)

        // With nowhere else to go, ~/.local/bin is created.
        try fm.removeItem(at: shared.appendingPathComponent("hun"))
        try fm.removeItem(at: shared)
        #expect(HunCLILinker.link(cli: cli, into: [missing, shared, local]) == local.appendingPathComponent("hun"))

        // A hun the user installed themselves is left alone.
        try fm.createDirectory(at: shared, withIntermediateDirectories: true)
        try Data("#!/bin/sh".utf8).write(to: shared.appendingPathComponent("hun"))
        try fm.removeItem(at: local.appendingPathComponent("hun"))
        #expect(HunCLILinker.link(cli: cli, into: [shared, local]) == nil)
        #expect(!fm.fileExists(atPath: local.appendingPathComponent("hun").path))
    }

    @Test func recentlyValidatedLicenseOpensBeforeTheServerAnswers() {
        let validatedAt = Date(timeIntervalSince1970: 1_000)
        let stored = HunStoredLicense(
            licenseKey: "test-license",
            instanceID: "lki_test",
            productID: "beta",
            productName: "Hun Public Beta",
            lastValidatedAt: validatedAt
        )
        let configuration = HunLicenseConfiguration(
            apiBaseURL: URL(string: "https://test.dodopayments.com")!,
            allowedProductIDs: ["beta"],
            checkoutURL: URL(string: "https://hun.sh")!,
            offlineGracePeriod: 72 * 60 * 60
        )
        let recent = HunLicenseManager(
            configuration: configuration,
            service: MockLicenseService(),
            store: InMemoryLicenseStore(license: stored),
            now: { validatedAt.addingTimeInterval(60) }
        )
        #expect(recent.isLicensed)

        let stale = HunLicenseManager(
            configuration: configuration,
            service: MockLicenseService(),
            store: InMemoryLicenseStore(license: stored),
            now: { validatedAt.addingTimeInterval(73 * 60 * 60) }
        )
        #expect(!stale.isLicensed)
    }

    @Test func fileLicenseStoreMigratesALicenseFromThePreviousStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("license.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let previous = InMemoryLicenseStore(license: HunStoredLicense(
            licenseKey: "test-license",
            instanceID: "lki_test",
            productID: "beta",
            productName: "Hun Public Beta",
            lastValidatedAt: Date(timeIntervalSince1970: 1_000)
        ))
        let store = HunFileLicenseStore(url: url, migratingFrom: previous)

        #expect(try store.load()?.instanceID == "lki_test")
        #expect(try previous.load() == nil)
        #expect(try HunFileLicenseStore(url: url).load()?.instanceID == "lki_test")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func offlineLicenseGraceEndsAfterSeventyTwoHours() {
        let configuration = HunLicenseConfiguration(
            apiBaseURL: URL(string: "https://test.dodopayments.com")!,
            allowedProductIDs: ["beta"],
            checkoutURL: URL(string: "https://hun.sh")!,
            offlineGracePeriod: 72 * 60 * 60
        )
        let validation = Date(timeIntervalSince1970: 10_000)

        #expect(
            HunLicensePolicy.mayUseOffline(
                lastValidatedAt: validation,
                now: validation.addingTimeInterval(72 * 60 * 60),
                configuration: configuration
            )
        )
        #expect(
            !HunLicensePolicy.mayUseOffline(
                lastValidatedAt: validation,
                now: validation.addingTimeInterval(72 * 60 * 60 + 1),
                configuration: configuration
            )
        )
    }

    @Test func dodoActivationResponseDecodesSnakeCaseProductID() throws {
        let payload = Data(
            """
            {
              "id": "lki_test",
              "product": {
                "product_id": "pdt_hun_beta",
                "name": "Hun Public Beta"
              }
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(ActivateResponse.self, from: payload)

        #expect(response.id == "lki_test")
        #expect(response.product.productID == "pdt_hun_beta")
        #expect(response.product.name == "Hun Public Beta")
    }

    @Test func licenseActivationErrorsUseProductLanguage() {
        #expect(
            HunLicenseError.rejected(
                statusCode: 404,
                providerMessage: "The requested resource could not be found."
            ).errorDescription
                == "That license key isn’t valid. Check the key and try again."
        )
        #expect(
            HunLicenseError.rejected(
                statusCode: 403,
                providerMessage: "License key activation limit reached"
            ).errorDescription
                == HunLicenseError.activationLimitMessage
        )
        #expect(
            HunLicenseError.rejected(
                statusCode: 400,
                providerMessage: "License key has expired"
            ).errorDescription
                == "This license key has expired."
        )
        #expect(
            HunLicenseError.rejected(
                statusCode: 503,
                providerMessage: "Internal service error"
            ).errorDescription
                == "The license service is temporarily unavailable. Try again in a moment."
        )
    }

    @Test func licenseNetworkErrorsUseActionableProductLanguage() {
        #expect(
            HunLicenseUserMessage.activation(
                for: URLError(.notConnectedToInternet)
            ) == "Couldn’t connect to the license service. Check your internet connection and try again."
        )
    }

    @Test func failedLicenseStorageReleasesTheDodoActivation() async {
        let service = MockLicenseService()
        let configuration = HunLicenseConfiguration(
            apiBaseURL: URL(string: "https://test.dodopayments.com")!,
            allowedProductIDs: ["beta"],
            checkoutURL: URL(string: "https://hun.sh")!,
            offlineGracePeriod: 72 * 60 * 60
        )
        let manager = HunLicenseManager(
            configuration: configuration,
            service: service,
            store: FailingLicenseStore()
        )

        await manager.activate("test-license")

        #expect(service.deactivatedInstances == ["lki_test"])
        #expect(manager.state == .needsActivation)
        #expect(manager.errorMessage == "Hun couldn’t activate this license key. Try again.")
    }

    @Test func updateBannerPreviewUsesExplicitVersion() {
        let version = HunUpdater.previewUpdateVersion(
            arguments: ["hun", "-HunPreviewUpdateBanner", "0.4.0"],
            currentVersion: "0.3.0"
        )

        #expect(version == "0.4.0")
    }

    @Test func updateBannerPreviewDefaultsToNextPatchVersion() {
        let version = HunUpdater.previewUpdateVersion(
            arguments: ["hun", "-HunPreviewUpdateBanner"],
            currentVersion: "0.3.0"
        )

        #expect(version == "0.3.1")
        #expect(
            HunUpdater.previewUpdateVersion(
                arguments: ["hun"],
                currentVersion: "0.3.0"
            ) == nil
        )
    }

    @Test func runtimeBuildParsesVersionAndCommit() {
        #expect(
            HunRuntimeBuild.parse("hun.sh v0.3.1 (commit: abc1234)\n")
                == HunRuntimeBuild(version: "v0.3.1", commit: "abc1234")
        )
        #expect(HunRuntimeBuild.parse("hun.sh v0.3.1") == nil)
    }

    @Test func runtimeBuildRequiresProtocolVersionAndCommitToMatch() {
        let build = HunRuntimeBuild(version: "v0.3.1", commit: "abc1234")
        let daemon = HunDaemonInfo(
            status: "pong",
            protocolVersion: 15,
            version: "v0.3.1",
            commit: "abc1234",
            pid: 123,
            startedAt: "2026-07-26T09:00:00Z"
        )

        #expect(build.matches(daemon, requiredProtocol: 15))
        #expect(!build.matches(daemon, requiredProtocol: 16))
        #expect(
            !HunRuntimeBuild(version: "v0.3.1", commit: "newer")
                .matches(daemon, requiredProtocol: 15)
        )
    }

    @Test func gitStatusExplainsItsRelationshipToTheRemote() {
        #expect(HunGitStatus.fixture(ahead: 0, behind: 0).syncState == .upToDate(upstream: "origin/main"))
        #expect(HunGitStatus.fixture(ahead: 2, behind: 0).syncState == .ahead(count: 2, upstream: "origin/main"))
        #expect(HunGitStatus.fixture(ahead: 0, behind: 3).syncState == .behind(count: 3, upstream: "origin/main"))
        #expect(
            HunGitStatus.fixture(ahead: 2, behind: 3).syncState ==
                .diverged(ahead: 2, behind: 3, upstream: "origin/main")
        )
        #expect(HunGitStatus.fixture(upstream: "").syncState == .unpublished(branch: "main"))
        #expect(HunGitStatus.fixture(detached: true).syncState == .detached)
    }

    @Test func remoteCheckAgeDoesNotStayJustNow() {
        let now = Date(timeIntervalSince1970: 100_000)

        #expect(HunGitRemoteCheckAge(checkedAt: nil, relativeTo: now) == .never)
        #expect(
            HunGitRemoteCheckAge(checkedAt: now.addingTimeInterval(-30), relativeTo: now) ==
                .justNow
        )
        #expect(
            HunGitRemoteCheckAge(checkedAt: now.addingTimeInterval(-300), relativeTo: now) ==
                .minutes(5)
        )
        #expect(
            HunGitRemoteCheckAge(checkedAt: now.addingTimeInterval(-7_200), relativeTo: now) ==
                .hours(2)
        )
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

    @Test func branchSwitcherOnlyQueriesGitWhileOpen() async {
        let client = MockGitClient()
        let model = HunBranchModel(client: client)

        model.select(projectID: "app")
        #expect(client.statusRequests == 0)
        #expect(client.branchRequests == 0)

        await model.loadForPicker()
        #expect(client.statusRequests == 1)
        #expect(client.branchRequests == 1)
    }

    @Test func dirtyWorkingTreeRequestsADecisionBeforeSwitchingBranches() async {
        let client = MockGitClient()
        client.status = HunGitStatus.fixture(clean: false)
        let model = HunBranchModel(client: client)
        model.select(projectID: "app")
        await model.refresh()

        let switched = await model.switchBranch("feature")

        #expect(!switched)
        #expect(model.pendingBranchSwitch == "feature")
        #expect(model.errorMessage == nil)
        #expect(client.actions.isEmpty)
    }

    @Test func switchFailureRefreshesStaleStatusBeforeShowingAnError() async {
        let client = MockGitClient()
        client.status = HunGitStatus.fixture(clean: true)
        let model = HunBranchModel(client: client)
        model.select(projectID: "app")
        await model.refresh()
        client.status = HunGitStatus.fixture(clean: false)
        client.switchError = TestError.boom

        let switched = await model.switchBranch("feature")

        #expect(!switched)
        #expect(model.pendingBranchSwitch == "feature")
        #expect(model.errorMessage == nil)
        #expect(client.actions == ["switch:app:feature:false"])
    }

    @Test func conflictedWorkingTreeBlocksSwitchWithoutOfferingAStash() async {
        let client = MockGitClient()
        client.status = HunGitStatus.fixture(clean: false, conflicted: true)
        let model = HunBranchModel(client: client)
        model.select(projectID: "app")
        await model.refresh()

        let switched = await model.switchBranch("feature")

        #expect(!switched)
        #expect(model.pendingBranchSwitch == nil)
        #expect(model.errorMessage == "Resolve the current conflicts before switching branches.")
        #expect(client.actions.isEmpty)
    }

    @Test func cancellingBranchPickerClearsThePendingSwitch() async {
        let client = MockGitClient()
        client.status = HunGitStatus.fixture(clean: false)
        let model = HunBranchModel(client: client)
        model.select(projectID: "app")
        await model.refresh()
        model.isBranchPickerPresented = true
        _ = await model.switchBranch("feature")

        model.cancelBranchPicker()

        #expect(!model.isBranchPickerPresented)
        #expect(model.pendingBranchSwitch == nil)
        #expect(client.actions.isEmpty)
    }

    @Test func failedGitFetchKeepsItsErrorVisible() async {
        let client = MockGitClient()
        let model = HunBranchModel(client: client)
        model.select(projectID: "app")
        await model.refresh()
        client.fetchError = TestError.boom

        await model.fetch()

        #expect(model.errorMessage == "boom")
        #expect(client.branchRequests == 0)
    }

    @Test func successfulFetchMarksTheRemoteAsChecked() async {
        let client = MockGitClient()
        let model = HunBranchModel(client: client)
        model.select(projectID: "app")
        await model.refresh()

        await model.fetch()

        #expect(model.lastRemoteCheckAt != nil)
        #expect(client.actions == ["fetch:app"])
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

    @Test func clearingLogsEmptiesTheViewAndTheDaemonBuffer() async throws {
        let client = MockDaemonClient()
        client.nextSnapshot = .fixture(activeProject: "app")
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)
        store.selectedLogScope = .combined
        // Changing the scope reloads logs in the background; let it finish.
        try await Task.sleep(for: .milliseconds(50))
        let project = try #require(store.model.projects.first)
        #expect(!store.logFeed.lines.isEmpty)

        store.clearLogs(for: project)
        try await Task.sleep(for: .milliseconds(50))

        #expect(store.logFeed.lines.isEmpty)
        #expect(client.actions.contains("clear_logs:app:"))
    }

    @Test func snapshotDecodesProfilesAndToleratesOlderDaemons() throws {
        let json = """
        {"protocol":17,"mode":"multitask","scan_dirs":[],"projects":[
          {"id":"shop","name":"shop","path":"/w/shop","status":"running","is_active":true,"profile":"app","services":[
            {"id":"api","name":"api","pid":10,"port":8000,"status":"running","running":true,"ready":true},
            {"id":"db","name":"db","pid":11,"port":5432,"status":"running","running":true,"ready":true},
            {"id":"web","name":"web","pid":12,"port":3000,"status":"running","running":true,"ready":true},
            {"id":"worker","name":"worker","pid":0,"port":0,"status":"stopped","running":false,"ready":false}
          ],"profiles":[
            {"name":"ui","services":["web"],"resolved":["web"]},
            {"name":"app","services":["web","api"],"resolved":["api","db","web"]}
          ]},
          {"id":"old","name":"old","path":"/w/old","status":"stopped","is_active":false,"services":[]}
        ]}
        """
        let snapshot = try JSONDecoder().decode(HunDaemonSnapshot.self, from: Data(json.utf8))

        let shop = HunProject(snapshot: snapshot.projects[0], activeID: "shop")
        #expect(shop.profile == "app")
        #expect(shop.profiles.map(\.name) == ["ui", "app"])
        #expect(shop.profileServices == ["api", "db", "web"])

        let old = HunProject(snapshot: snapshot.projects[1], activeID: nil)
        #expect(old.profiles.isEmpty)
        #expect(old.profile == nil)
        #expect(old.profileServices == nil)
    }

    @Test func runningAProfileAndSavingOneSendTheRightRequests() async throws {
        let client = MockDaemonClient()
        client.nextSnapshot = .fixture(activeProject: "app")
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)
        let project = try #require(store.model.projects.first)

        store.chooseProfile("ui", for: project)
        store.chooseProfile(nil, for: project)
        try await Task.sleep(for: .milliseconds(50))
        #expect(client.actions.contains { $0.hasPrefix("profile:\(project.id):ui:") })
        #expect(client.actions.contains { $0.hasPrefix("profile:\(project.id):all:") })

        let running = project.services.filter { $0.status == .running || $0.status == .starting }.map(\.id)
        store.saveRunningServicesAsProfile(named: "mine", for: project)
        try await Task.sleep(for: .milliseconds(50))
        if running.isEmpty {
            #expect(!client.actions.contains { $0.hasPrefix("save_profile:") })
        } else {
            #expect(client.actions.contains("save_profile:\(project.id):mine:\(running.joined(separator: ","))"))
        }
    }

    @Test func choosingAProfileForAStoppedProjectDoesNotStartIt() async throws {
        let client = MockDaemonClient()
        client.nextSnapshot = HunDaemonSnapshot(
            protocolVersion: 19, mode: "multitask", activeProject: nil, scanDirs: [], lastScanAt: nil,
            projects: [HunDaemonProject(id: "shop", name: "shop", path: "/w/shop", status: "stopped", isActive: false, branch: nil, lastNote: nil, startedAt: nil, services: [], configError: nil)],
            warnings: []
        )
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)
        let project = try #require(store.model.projects.first)

        store.chooseProfile("ui", for: project)
        try await Task.sleep(for: .milliseconds(50))
        #expect(client.actions.contains("select_profile:shop:ui"))
        #expect(!client.actions.contains { $0.hasPrefix("profile:") || $0.hasPrefix("start:") })
    }

    @Test func editingConfigOpensInHunAndSavesThroughTheDaemon() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cfg-" + UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "name: shop\n".write(to: folder.appendingPathComponent(".hun.yml"), atomically: true, encoding: .utf8)

        let client = MockDaemonClient()
        client.nextSnapshot = HunDaemonSnapshot(
            protocolVersion: 18, mode: "multitask", activeProject: nil, scanDirs: [], lastScanAt: nil,
            projects: [HunDaemonProject(id: "shop", name: "shop", path: folder.path, status: "stopped", isActive: false, branch: nil, lastNote: nil, startedAt: nil, services: [], configError: nil)],
            warnings: []
        )
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)
        let project = try #require(store.model.projects.first)

        store.openConfig(for: project)
        let target = try #require(store.configEditor)
        #expect(target.fileURL.path == folder.appendingPathComponent(".hun.yml").path)

        #expect(await store.configProblem(in: "name: shop") == nil)
        #expect(await store.saveConfig("name: shop\n# edited\n", for: target) == nil)
        #expect(client.savedConfigs.map(\.path) == [folder.path])

        client.configError = "yaml: line 3: mapping values are not allowed in this context"
        #expect(await store.configProblem(in: "bad") == client.configError)
        #expect(await store.saveConfig("bad", for: target) == client.configError)
        #expect(HunConfigEditorSheet.lineNumber(in: client.configError!) == 3)
        #expect(HunConfigEditorSheet.lineNumber(in: "at least one service is required") == nil)
    }

    private func daemonLine(_ text: String, service: String = "web") -> HunDaemonLogLine {
        HunDaemonLogLine(timestamp: "2026-10-20T17:00:00.000Z", service: service, project: "app", text: text, isErr: false)
    }

    @Test func logFeedCapsTrimsAndIgnoresStaleSubscriptions() {
        let feed = HunLogFeed()
        feed.replace(with: (0..<10).map { HunLogLine(daemonLine("old \($0)")) })
        let reloadGeneration = feed.generation
        let stale = feed.beginSubscription()
        let current = feed.beginSubscription()

        feed.append([HunLogLine(daemonLine("from an old stream"))], subscription: stale)
        #expect(feed.lines.count == 10)

        let batch = (0..<HunLogFeed.capacity).map { HunLogLine(daemonLine("new \($0)")) }
        feed.append(batch, subscription: current)
        #expect(feed.lines.count == HunLogFeed.capacity)
        #expect(feed.lines.first?.message == "new 0")
        #expect(feed.lines.last?.message == "new \(HunLogFeed.capacity - 1)")
        #expect(feed.lastSeq == 10 + HunLogFeed.capacity)
        #expect(zip(feed.lines, feed.lines.dropFirst()).allSatisfy { $0.id < $1.id })
        #expect(feed.generation == reloadGeneration, "appending must not force a full redraw")

        feed.clear(service: "web")
        #expect(feed.lines.isEmpty)
        #expect(feed.generation == reloadGeneration + 1)
    }

    @Test func logBatcherDeliversBurstsInFewBatchesAndInOrder() async throws {
        var batches: [[HunLogLine]] = []
        let batcher = HunLogBatcher { batches.append($0) }
        await Task.detached {
            for i in 0..<2_000 { batcher.add(HunDaemonLogLine(timestamp: "", service: "web", project: "app", text: "\(i)", isErr: false)) }
        }.value
        try await Task.sleep(for: .milliseconds(200))

        let delivered = batches.flatMap { $0 }.map(\.message)
        #expect(delivered == (0..<2_000).map(String.init))
        #expect(batches.count < 20, "2,000 lines arrived in \(batches.count) batches")
    }

    @Test func profileNamesAreChecked() {
        #expect(HunProfile.problem(with: "  ") != nil)
        #expect(HunProfile.problem(with: "all") != nil)
        #expect(HunProfile.problem(with: "a:b") != nil)
        #expect(HunProfile.problem(with: "web-only") == nil)
    }

    @Test func renamedProjectKeepsItsTabAndSelection() async {
        func snapshot(id: String) -> HunDaemonSnapshot {
            HunDaemonSnapshot(
                protocolVersion: 16,
                mode: "focus",
                activeProject: nil,
                scanDirs: [],
                lastScanAt: nil,
                projects: [
                    HunDaemonProject(id: "other", name: "other", path: "/w/other", status: "stopped", isActive: false, branch: nil, lastNote: nil, startedAt: nil, services: [], configError: nil),
                    HunDaemonProject(id: id, name: id, path: "/w/shop", status: "stopped", isActive: false, branch: nil, lastNote: nil, startedAt: nil, services: [], configError: nil)
                ],
                warnings: []
            )
        }
        let client = MockDaemonClient()
        client.nextSnapshot = snapshot(id: "shop")
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)
        store.selectProject("shop")

        client.nextSnapshot = snapshot(id: "storefront")
        await store.refresh(force: true)

        #expect(store.selectedProjectID == "storefront")
        #expect(store.openTabIDs.contains("storefront"))
        #expect(!store.openTabIDs.contains("shop"))
    }

    @Test func cachedSnapshotKeepsProjectsVisibleDuringRecovery() async {
        let client = MockDaemonClient()
        client.nextSnapshot = HunDaemonSnapshot.fixture(activeProject: "app").replacingLifecycleBusy(true)
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)

        await store.refresh(force: true)

        #expect(store.isConnected)
        #expect(store.isRecoveringServices)
        #expect(store.model.projects.map(\.id) == ["app"])
        #expect(store.selectedProjectID == "app")
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
        #expect(!snapshot.lifecycleBusy)
        #expect(snapshot.projects.map(\.id) == ["app"])
    }

    @Test func busySnapshotDecodingPreservesRecoveryState() throws {
        let payload = """
        {
          "protocol": 15,
          "mode": "focus",
          "scan_dirs": [],
          "projects": [],
          "lifecycle_busy": true
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(HunDaemonSnapshot.self, from: payload)

        #expect(snapshot.lifecycleBusy)
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

        let project = HunProject(snapshot: snapshot, activeID: nil)

        #expect(project.branch == nil)
    }

    @Test func snapshotDecodesServicesStartedOutsideHunAndPortConflicts() throws {
        let json = """
        {"protocol":16,"mode":"focus","scan_dirs":[],"projects":[{"id":"otto","name":"otto","path":"/w/otto","status":"running","is_active":true,"services":[
          {"id":"backend","name":"backend","pid":0,"port":8000,"status":"running","running":true,"ready":true,"origin":"external","runtime":"docker","container":"otto-backend-1"},
          {"id":"frontend","name":"frontend","pid":0,"port":3000,"status":"stopped","running":false,"ready":false,"conflict":{"port":3000,"pid":812,"command":"node","cwd":"/tmp/demo"}}
        ]}],
        "unmanaged":[{"pid":900,"command":"vite","port":5173,"ports":[5173],"cwd":"/w/scratch"}]}
        """
        let snapshot = try JSONDecoder().decode(HunDaemonSnapshot.self, from: Data(json.utf8))
        let services = HunProject(snapshot: snapshot.projects[0], activeID: "otto").services

        let backend = try #require(services.first { $0.id == "backend" })
        #expect(backend.isExternal)
        #expect(backend.isDocker)
        #expect(backend.browserURL?.absoluteString == "http://localhost:8000")
        #expect(backend.externalSourceText == "Started outside Hun · Docker container otto-backend-1")

        let frontend = try #require(services.first { $0.id == "frontend" })
        #expect(!frontend.isExternal)
        #expect(frontend.conflict?.summary == "node · /tmp/demo")
        #expect(snapshot.unmanaged.map(\.port) == [5173])
    }

    @Test func snapshotFromOlderDaemonDecodesWithoutObservedFields() throws {
        let json = """
        {"protocol":15,"mode":"focus","scan_dirs":[],"projects":[{"id":"a","name":"a","path":"/a","status":"running","is_active":false,"services":[
          {"id":"web","name":"web","pid":4,"port":3000,"status":"running","running":true,"ready":true}
        ]}]}
        """
        let snapshot = try JSONDecoder().decode(HunDaemonSnapshot.self, from: Data(json.utf8))
        let service = try #require(snapshot.projects.first?.services.first)
        #expect(service.origin == nil)
        #expect(service.conflict == nil)
        #expect(snapshot.unmanaged.isEmpty)
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
        let project = HunProject(snapshot: .fixtureProject(path: "/tmp/projects/shop"), activeID: nil)
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
        #expect(prompt.contains("run `hun validate .`"))
        #expect(prompt.contains("suggest profiles"))
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
        #expect(prompt.contains("change only what's wrong if a .hun.yml exists"))
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

    @Test func modeChangeCommitsOnlyAfterDaemonAcknowledgesIt() async throws {
        let client = MockDaemonClient()
        client.modeChangeDelay = .milliseconds(100)
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)

        store.changeMode(.multitask, preferredProject: nil)

        #expect(store.globalMode == .focus)
        #expect(store.displayedMode == .multitask)
        #expect(store.isChangingMode)
        try await waitUntil { store.globalMode == .multitask && !store.isChangingMode }
    }

    @Test func modeChangeRetriesLifecycleRecoveryContention() async throws {
        let client = MockDaemonClient()
        client.modeErrors = [TestError.lifecycleBusy]
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)

        store.changeMode(.multitask, preferredProject: nil)

        try await waitUntil { client.modeChangeAttempts == 2 && store.globalMode == .multitask }
        #expect(!store.isChangingMode)
        #expect(store.lastError == nil)
    }

    @Test func failedModeChangeRollsBackPendingSelection() async throws {
        let client = MockDaemonClient()
        client.modeErrors = [TestError.boom]
        let store = HunStore(client: client, supervisor: MockSupervisor(), startAutomatically: false)
        await store.refresh(force: true)

        store.changeMode(.multitask, preferredProject: nil)

        try await waitUntil { !store.isChangingMode }
        #expect(store.globalMode == .focus)
        #expect(store.displayedMode == .focus)
        #expect(store.lastError == "Couldn’t switch mode: boom")
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

    @Test func workspacePanelWidthPreservesNavigatorAndDetailSpace() {
        #expect(HunWorkspacePanelMetrics.clamp(120, availableWidth: 1_200) == 140)
        #expect(HunWorkspacePanelMetrics.clamp(900, availableWidth: 1_200) == 640)
        // Dragged sizes land on whole points so text stays sharp.
        #expect(HunWorkspacePanelMetrics.clamp(321.01953125, availableWidth: 1_200) == 321)
        #expect(HunTerminalPanelMetrics.clamp(390.29296875, availableHeight: 700) == 390)
        #expect(HunWorkspacePanelMetrics.clamp(500, availableWidth: 700) == 500)
        #expect(HunWorkspacePanelMetrics.clamp(310, availableWidth: 1_200) == 310)
        #expect(HunWorkspacePanelMetrics.clamp(320, availableWidth: 310) == 141)
    }

    @Test func workspaceResizeSurfaceOwnsHorizontalMouseDrags() throws {
        let surface = HunPanelResizeSurfaceView(axis: .horizontal)
        var resizedWidth: CGFloat?
        surface.configure(
            preferredValue: 310,
            allowedRange: 240 ... 640,
            onResize: { resizedWidth = $0 }
        )

        let mouseDown = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 100, y: 20),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
        let mouseDrag = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: NSPoint(x: 150, y: 20),
                modifierFlags: [],
                timestamp: 0.1,
                windowNumber: 0,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 1
            )
        )

        #expect(surface.mouseDownCanMoveWindow == false)
        surface.mouseDown(with: mouseDown)
        surface.mouseDragged(with: mouseDrag)
        #expect(resizedWidth == 360)
    }

    @Test func terminalResizeSurfaceOwnsMouseDragsInsteadOfMovingWindow() throws {
        let surface = HunPanelResizeSurfaceView(axis: .vertical)
        var resizedHeight: CGFloat?
        surface.configure(
            preferredValue: 900,
            allowedRange: HunTerminalPanelMetrics.allowedRange(availableHeight: 700),
            onResize: { resizedHeight = $0 }
        )

        let mouseDown = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 20, y: 100),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
        let mouseDrag = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: NSPoint(x: 20, y: 50),
                modifierFlags: [],
                timestamp: 0.1,
                windowNumber: 0,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 1
            )
        )

        #expect(surface.mouseDownCanMoveWindow == false)
        #expect(surface.currentValue == 530)
        surface.mouseDown(with: mouseDown)
        surface.mouseDragged(with: mouseDrag)
        #expect(resizedHeight == 480)

        #expect(surface.accessibilityPerformDecrement())
        #expect(resizedHeight == 456)
    }

    @Test func activationButtonOwnsTheFirstClickInsteadOfMovingTheWindow() {
        let button = HunFirstMouseButtonView()

        #expect(button.mouseDownCanMoveWindow == false)
        #expect(button.acceptsFirstMouse(for: nil))
    }

    @Test func activationButtonShowsValidationProgressInline() {
        let button = HunFirstMouseButtonView()
        button.attributedTitle = NSAttributedString(string: "Activate Hun")

        button.setLoading(true)

        #expect(button.isLoading)
        #expect(button.attributedTitle.string.isEmpty)

        button.setLoading(false)

        #expect(!button.isLoading)
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

private final class MockLicenseService: HunLicenseServing, @unchecked Sendable {
    var deactivatedInstances: [String] = []
    var validatedInstances: [String] = []
    var isValid = true

    func activate(
        licenseKey: String,
        deviceName: String
    ) async throws -> HunLicenseActivation {
        HunLicenseActivation(
            instanceID: "lki_test",
            productID: "beta",
            productName: "Hun Public Beta"
        )
    }

    func validate(
        licenseKey: String,
        instanceID: String
    ) async throws -> Bool {
        validatedInstances.append(instanceID)
        return isValid
    }

    func deactivate(
        licenseKey: String,
        instanceID: String
    ) async throws {
        deactivatedInstances.append(instanceID)
    }
}

private final class InMemoryLicenseStore: HunLicenseStoring, @unchecked Sendable {
    private var license: HunStoredLicense?

    init(license: HunStoredLicense? = nil) {
        self.license = license
    }

    func load() throws -> HunStoredLicense? {
        license
    }

    func save(_ license: HunStoredLicense) throws {
        self.license = license
    }

    func delete() throws {
        license = nil
    }
}

private struct FailingLicenseStore: HunLicenseStoring {
    func load() throws -> HunStoredLicense? {
        nil
    }

    func save(_ license: HunStoredLicense) throws {
        throw TestError.boom
    }

    func delete() throws {}
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
    var fetchError: Error?
    var switchResult: HunGitStatus?
    var switchError: Error?
    var statusRequests = 0
    var branchRequests = 0
    var actions: [String] = []

    func gitStatus(project: String) async throws -> HunGitStatus {
        statusRequests += 1
        return status
    }

    func gitBranches(project: String) async throws -> [HunGitBranch] {
        branchRequests += 1
        return branches
    }

    func gitCreateBranch(project: String, branch: String) async throws -> HunGitStatus {
        actions.append("create:\(project):\(branch)")
        return status
    }

    func gitSwitchBranch(project: String, branch: String, stash: Bool) async throws -> HunGitStatus {
        actions.append("switch:\(project):\(branch):\(stash)")
        if let switchError {
            throw switchError
        }
        return switchResult ?? status
    }

    func gitFetch(project: String) async throws -> HunGitStatus {
        actions.append("fetch:\(project)")
        if let fetchError {
            throw fetchError
        }
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
    static func fixture(
        branch: String = "main",
        upstream: String = "origin/main",
        ahead: Int = 0,
        behind: Int = 0,
        detached: Bool = false,
        clean: Bool = false,
        operation: String? = nil,
        conflicted: Bool = false
    ) -> HunGitStatus {
        HunGitStatus(
            isRepository: true,
            branch: branch,
            head: "abc123",
            upstream: upstream,
            ahead: ahead,
            behind: behind,
            detached: detached,
            clean: clean,
            operation: operation,
            files: [
                HunGitFileChange(
                    path: "ContentView.swift",
                    originalPath: nil,
                    indexStatus: conflicted ? "U" : ".",
                    worktreeStatus: conflicted ? "U" : "M",
                    untracked: false,
                    conflicted: conflicted
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
    var modeErrors: [Error] = []
    var modeChangeAttempts = 0
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

    func runProfile(_ project: String, profile: String, mode: HunDaemonStartMode) async throws {
        actions.append("profile:\(project):\(profile):\(mode.rawValue)")
    }

    func saveProfile(_ project: String, name: String, services: [String]) async throws {
        actions.append("save_profile:\(project):\(name):\(services.joined(separator: ","))")
    }

    func selectProfile(_ project: String, profile: String) async throws {
        actions.append("select_profile:\(project):\(profile)")
    }

    var configError: String?
    var savedConfigs: [(path: String, content: String)] = []

    func validateConfig(_ content: String) async throws {
        if let configError { throw HunDaemonError.daemon(configError) }
    }

    func saveConfig(path: String, content: String) async throws {
        if let configError { throw HunDaemonError.daemon(configError) }
        savedConfigs.append((path, content))
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

    func freePort(_ port: Int) async throws {
        actions.append("free_port:\(port)")
    }

    func removeProject(_ project: String) async throws {
        actions.append("remove_project:\(project)")
    }

    func clearLogs(project: String, service: String?) async throws {
        actions.append("clear_logs:\(project):\(service ?? "")")
    }

    func setMode(_ mode: HunMode, preferredProject: String?) async throws {
        modeChangeAttempts += 1
        if let modeChangeDelay {
            try? await Task.sleep(for: modeChangeDelay)
        }
        if !modeErrors.isEmpty {
            throw modeErrors.removeFirst()
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
    case lifecycleBusy

    var errorDescription: String? {
        switch self {
        case .boom:
            return "boom"
        case .connectionClosed:
            return "connection closed"
        case .lifecycleBusy:
            return "lifecycle operation in progress"
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
            warnings: warnings,
            lifecycleBusy: lifecycleBusy
        )
    }

    func replacingLifecycleBusy(_ lifecycleBusy: Bool) -> HunDaemonSnapshot {
        HunDaemonSnapshot(
            protocolVersion: protocolVersion,
            mode: mode,
            activeProject: activeProject,
            scanDirs: scanDirs,
            lastScanAt: lastScanAt,
            projects: projects,
            warnings: warnings,
            lifecycleBusy: lifecycleBusy
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
            warnings: warnings,
            lifecycleBusy: lifecycleBusy
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
