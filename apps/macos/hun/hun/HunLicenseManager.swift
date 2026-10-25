import AppKit
import Foundation
import Observation
import Security

nonisolated struct HunLicenseConfiguration: Sendable {
    let apiBaseURL: URL
    let allowedProductIDs: Set<String>
    let checkoutURL: URL
    let offlineGracePeriod: TimeInterval
    /// Products whose keys belonged to the free public beta. When one stops
    /// being valid, Hun says the beta has ended rather than showing an error.
    var betaProductIDs: Set<String> = []

    static var current: HunLicenseConfiguration {
        let info = Bundle.main.infoDictionary ?? [:]
        let apiBaseURL = URL(
            string: info["HunLicenseAPIBaseURL"] as? String
                ?? "https://live.dodopayments.com"
        )!
        let checkoutURL = URL(
            string: info["HunCheckoutURL"] as? String
                ?? "https://checkout.dodopayments.com/buy/pdt_0NqT6hcDftBBLBUTgJc6P?quantity=1&redirect_url=https://hun.sh%2Flicense%2Fsuccess"
        )!

        return HunLicenseConfiguration(
            apiBaseURL: apiBaseURL,
            allowedProductIDs: productIDs(
                info["HunLicenseProductIDs"] as? String
                    ?? "pdt_0NqT6hcDftBBLBUTgJc6P,pdt_0Nk9a6sOPWWJ4iOwu4bwl"
            ),
            checkoutURL: checkoutURL,
            offlineGracePeriod: 72 * 60 * 60,
            betaProductIDs: productIDs(
                info["HunBetaProductIDs"] as? String ?? "pdt_0Nk9a6sOPWWJ4iOwu4bwl"
            )
        )
    }

    private static func productIDs(_ list: String) -> Set<String> {
        Set(
            list.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}

nonisolated enum HunLicensePolicy {
    static func mayUseOffline(
        lastValidatedAt: Date,
        now: Date,
        configuration: HunLicenseConfiguration
    ) -> Bool {
        now.timeIntervalSince(lastValidatedAt) <= configuration.offlineGracePeriod
    }
}

struct HunLicenseSession: Equatable, Sendable {
    let productID: String
    let productName: String
    let lastValidatedAt: Date
    let isOffline: Bool
}

enum HunLicenseState: Equatable {
    case checking
    case needsActivation
    case activating
    case active(HunLicenseSession)
    case unavailable(String)
}

@MainActor
@Observable
final class HunLicenseManager {
    private(set) var state: HunLicenseState = .checking
    private(set) var errorMessage: String?
    /// The beta license on this Mac ran out, so activation asks for a paid
    /// license. Kept across launches until a new key is activated.
    private(set) var betaEnded: Bool {
        didSet { defaults.set(betaEnded, forKey: Self.betaEndedKey) }
    }

    let configuration: HunLicenseConfiguration

    private let service: HunLicenseServing
    private let store: HunLicenseStoring
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    private static let betaEndedKey = "HunBetaEnded"

    init(
        configuration: HunLicenseConfiguration = .current,
        service: HunLicenseServing? = nil,
        store: HunLicenseStoring = HunLicenseStores.default,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.service = service ?? HunDodoLicenseService(baseURL: configuration.apiBaseURL)
        self.store = store
        self.defaults = defaults
        self.now = now
        betaEnded = defaults.bool(forKey: Self.betaEndedKey)
        // A license validated within the offline grace period opens the app on
        // the first frame; restore() then confirms it with the server.
        if let stored = try? store.load(), mayUseCachedLicense(stored) {
            state = .active(stored.session(isOffline: false))
        }
    }

    private func mayUseCachedLicense(_ stored: HunStoredLicense) -> Bool {
        HunLicensePolicy.mayUseOffline(
            lastValidatedAt: stored.lastValidatedAt,
            now: now(),
            configuration: configuration
        )
    }

    var isLicensed: Bool {
        if case .active = state { return true }
        return false
    }

    var activeSession: HunLicenseSession? {
        guard case let .active(session) = state else { return nil }
        return session
    }

    func restore() async {
        errorMessage = nil

        guard let stored = try? store.load() else {
            state = .needsActivation
            return
        }
        let mayUseCached = mayUseCachedLicense(stored)
        if !mayUseCached {
            state = .checking
        }

        do {
            let valid = try await service.validate(
                licenseKey: stored.licenseKey,
                instanceID: stored.instanceID
            )
            guard valid else {
                try? store.delete()
                if configuration.betaProductIDs.contains(stored.productID) {
                    betaEnded = true
                } else {
                    errorMessage = "This license is no longer valid."
                }
                state = .needsActivation
                return
            }

            let validatedAt = now()
            let refreshed = stored.with(lastValidatedAt: validatedAt)
            try store.save(refreshed)
            state = .active(refreshed.session(isOffline: false))
        } catch {
            if mayUseCached {
                state = .active(stored.session(isOffline: true))
            } else {
                state = .unavailable(
                    "Hun could not validate your license. Check your connection and try again."
                )
            }
        }
    }

    func activate(_ licenseKey: String) async {
        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            errorMessage = "Enter the license key from your purchase email."
            return
        }

        state = .activating
        errorMessage = nil

        do {
            let activation = try await service.activate(
                licenseKey: trimmedKey,
                deviceName: Host.current().localizedName ?? "Mac"
            )
            do {
                guard configuration.allowedProductIDs.contains(activation.productID) else {
                    throw HunLicenseError.wrongProduct
                }
                let stored = HunStoredLicense(
                    licenseKey: trimmedKey,
                    instanceID: activation.instanceID,
                    productID: activation.productID,
                    productName: activation.productName,
                    lastValidatedAt: now()
                )
                try store.save(stored)
                betaEnded = false
                state = .active(stored.session(isOffline: false))
            } catch {
                try? await service.deactivate(
                    licenseKey: trimmedKey,
                    instanceID: activation.instanceID
                )
                throw error
            }
        } catch {
            errorMessage = HunLicenseUserMessage.activation(for: error)
            state = .needsActivation
        }
    }

    func retryValidation() async {
        await restore()
    }

    /// Rechecks an active license every few hours and when the Mac wakes, so a
    /// license that ends while Hun stays open is noticed without a relaunch.
    func startMonitoring(every interval: Duration = .seconds(6 * 60 * 60)) {
        guard monitor == nil else { return }
        // The manager lives as long as the app.
        monitor = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await self.recheck()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.recheck() }
            }
        }
    }

    /// Confirms an active license with the server; does nothing while Hun is
    /// asking for a key.
    func recheck() async {
        guard isLicensed else { return }
        await restore()
    }

    func deactivate() async -> Bool {
        guard let stored = try? store.load() else {
            state = .needsActivation
            return true
        }

        do {
            try await service.deactivate(
                licenseKey: stored.licenseKey,
                instanceID: stored.instanceID
            )
            try store.delete()
            errorMessage = nil
            state = .needsActivation
            return true
        } catch {
            errorMessage = "Hun could not deactivate this Mac. Check your connection and try again."
            return false
        }
    }
}

enum HunLicenseError: LocalizedError {
    case invalidResponse
    case rejected(statusCode: Int, providerMessage: String?)
    case wrongProduct

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Hun couldn’t verify that license key. Try again in a moment."
        case let .rejected(statusCode, providerMessage):
            Self.rejectionDescription(
                statusCode: statusCode,
                providerMessage: providerMessage
            )
        case .wrongProduct:
            "This key is not for Hun."
        }
    }

    static let activationLimitMessage =
        "This key is already active on as many Macs as it allows. Deactivate Hun on one of them and try again."

    private static func rejectionDescription(
        statusCode: Int,
        providerMessage: String?
    ) -> String {
        let message = providerMessage?.lowercased() ?? ""

        if message.contains("activation limit")
            || message.contains("maximum activation")
            || message.contains("too many activation")
        {
            return Self.activationLimitMessage
        }
        if message.contains("expired") {
            return "This license key has expired."
        }
        if message.contains("revoked")
            || message.contains("disabled")
            || message.contains("inactive")
        {
            return "This license key is no longer active."
        }

        switch statusCode {
        case 400, 404, 422:
            return "That license key isn’t valid. Check the key and try again."
        case 403:
            return Self.activationLimitMessage
        case 429:
            return "Too many activation attempts. Wait a moment and try again."
        case 500 ... 599:
            return "The license service is temporarily unavailable. Try again in a moment."
        default:
            return "Hun couldn’t activate this license key. Try again."
        }
    }
}

nonisolated enum HunLicenseUserMessage {
    static func activation(for error: Error) -> String {
        if let licenseError = error as? HunLicenseError {
            return licenseError.errorDescription
                ?? "Hun couldn’t activate this license key. Try again."
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .networkConnectionLost,
                 .timedOut:
                return "Couldn’t connect to the license service. Check your internet connection and try again."
            default:
                break
            }
        }

        return "Hun couldn’t activate this license key. Try again."
    }
}

nonisolated struct HunLicenseActivation: Sendable {
    let instanceID: String
    let productID: String
    let productName: String
}

nonisolated protocol HunLicenseServing: Sendable {
    func activate(licenseKey: String, deviceName: String) async throws -> HunLicenseActivation
    func validate(licenseKey: String, instanceID: String) async throws -> Bool
    func deactivate(licenseKey: String, instanceID: String) async throws
}

struct HunDodoLicenseService: HunLicenseServing {
    let baseURL: URL

    func activate(licenseKey: String, deviceName: String) async throws -> HunLicenseActivation {
        let request = try request(
            path: "licenses/activate",
            body: ActivateRequest(licenseKey: licenseKey, name: deviceName)
        )
        let response: ActivateResponse = try await send(request)
        return HunLicenseActivation(
            instanceID: response.id,
            productID: response.product.productID,
            productName: response.product.name
        )
    }

    func validate(licenseKey: String, instanceID: String) async throws -> Bool {
        let request = try request(
            path: "licenses/validate",
            body: ValidateRequest(
                licenseKey: licenseKey,
                licenseKeyInstanceID: instanceID
            )
        )
        let response: ValidateResponse = try await send(request)
        return response.valid
    }

    func deactivate(licenseKey: String, instanceID: String) async throws {
        let request = try request(
            path: "licenses/deactivate",
            body: ValidateRequest(
                licenseKey: licenseKey,
                licenseKeyInstanceID: instanceID
            )
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HunLicenseError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(DodoErrorResponse.self, from: data)
            throw HunLicenseError.rejected(
                statusCode: http.statusCode,
                providerMessage: error?.message
            )
        }
    }

    private func request<Body: Encodable>(path: String, body: Body) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)
        request.timeoutInterval = 15
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HunLicenseError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(DodoErrorResponse.self, from: data)
            throw HunLicenseError.rejected(
                statusCode: http.statusCode,
                providerMessage: error?.message
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw HunLicenseError.invalidResponse
        }
    }
}

nonisolated struct ActivateRequest: Encodable {
    let licenseKey: String
    let name: String
}

nonisolated struct ValidateRequest: Encodable {
    let licenseKey: String
    let licenseKeyInstanceID: String
}

nonisolated struct ActivateResponse: Decodable {
    let id: String
    let product: Product

    struct Product: Decodable {
        let productID: String
        let name: String

        private enum CodingKeys: String, CodingKey {
            case productID = "product_id"
            case name
        }
    }
}

nonisolated struct ValidateResponse: Decodable {
    let valid: Bool
}

nonisolated struct DodoErrorResponse: Decodable {
    let message: String?
}

nonisolated struct HunStoredLicense: Codable {
    let licenseKey: String
    let instanceID: String
    let productID: String
    let productName: String
    let lastValidatedAt: Date

    func with(lastValidatedAt: Date) -> HunStoredLicense {
        HunStoredLicense(
            licenseKey: licenseKey,
            instanceID: instanceID,
            productID: productID,
            productName: productName,
            lastValidatedAt: lastValidatedAt
        )
    }

    func session(isOffline: Bool) -> HunLicenseSession {
        HunLicenseSession(
            productID: productID,
            productName: productName,
            lastValidatedAt: lastValidatedAt,
            isOffline: isOffline
        )
    }
}

nonisolated protocol HunLicenseStoring: Sendable {
    func load() throws -> HunStoredLicense?
    func save(_ license: HunStoredLicense) throws
    func delete() throws
}

enum HunLicenseStores {
#if DEBUG
    /// Debug builds are re-signed on every build, so the Keychain treats each
    /// one as a new app and asks for the login password. Keep the dev license
    /// in a private file instead.
    static let `default`: HunLicenseStoring = HunFileLicenseStore(
        url: HunPaths.homeURL.appendingPathComponent("license.json"),
        migratingFrom: HunKeychainLicenseStore()
    )
#else
    static let `default`: HunLicenseStoring = HunKeychainLicenseStore()
#endif
}

struct HunFileLicenseStore: HunLicenseStoring {
    let url: URL
    /// Where a license saved by an earlier build lives; copied over once.
    var migratingFrom: HunLicenseStoring? = nil

    func load() throws -> HunStoredLicense? {
        if let data = try? Data(contentsOf: url) {
            return try JSONDecoder().decode(HunStoredLicense.self, from: data)
        }
        guard let previous = try migratingFrom?.load() else { return nil }
        try save(previous)
        try? migratingFrom?.delete()
        return previous
    }

    func save(_ license: HunStoredLicense) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(license).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

struct HunKeychainLicenseStore: HunLicenseStoring {
#if DEBUG
    private let service = "sh.hun.license.dev"
#else
    private let service = "sh.hun.license"
#endif
    private let account = "active-license"

    func load() throws -> HunStoredLicense? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw HunLicenseError.invalidResponse
        }
        return try JSONDecoder().decode(HunStoredLicense.self, from: data)
    }

    func save(_ license: HunStoredLicense) throws {
        let data = try JSONEncoder().encode(license)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw HunLicenseError.invalidResponse
        }

        var item = query
        item.merge(attributes) { _, new in new }
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw HunLicenseError.invalidResponse
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw HunLicenseError.invalidResponse
        }
    }
}
