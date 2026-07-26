import AppKit
import Observation
import Sparkle

struct HunAvailableUpdate: Equatable, Sendable {
    let version: String

    var changelogURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "hun.sh"
        components.path = "/changelog"
        components.fragment = "v\(version)"
        return components.url
    }
}

@MainActor
@Observable
final class HunUpdater: NSObject, SPUStandardUserDriverDelegate {
    private(set) var availableUpdate: HunAvailableUpdate?

    @ObservationIgnored
    private var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func openChangelog(for update: HunAvailableUpdate) {
        guard let changelogURL = update.changelogURL else { return }
        NSWorkspace.shared.open(changelogURL)
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        availableUpdate = HunAvailableUpdate(version: update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableUpdate = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableUpdate = nil
    }
}
