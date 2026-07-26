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

        #if DEBUG
        if let version = Self.previewUpdateVersion(
            arguments: ProcessInfo.processInfo.arguments,
            currentVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        ) {
            availableUpdate = HunAvailableUpdate(version: version)
        }
        #endif
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

    nonisolated static func previewUpdateVersion(
        arguments: [String],
        currentVersion: String?
    ) -> String? {
        guard let flagIndex = arguments.firstIndex(of: "-HunPreviewUpdateBanner") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        if arguments.indices.contains(valueIndex) {
            let value = arguments[valueIndex]
            if !value.isEmpty, !value.hasPrefix("-") {
                return value
            }
        }

        guard let currentVersion else {
            return "0.3.1"
        }

        let components = currentVersion.split(separator: ".").compactMap { Int($0) }
        guard components.count == 3 else {
            return "0.3.1"
        }

        return "\(components[0]).\(components[1]).\(components[2] + 1)"
    }
}
