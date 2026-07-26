import Foundation
import Observation
import Security

nonisolated struct HunLicenseConfiguration: Sendable {
    let apiBaseURL: URL
    let betaProductID: String
    let allowedProductIDs: Set<String>
    let betaEndsAt: Date
    let checkoutURL: URL
    let offlineGracePeriod: TimeInterval

    static var current: HunLicenseConfiguration {
        let info = Bundle.main.infoDictionary ?? [:]
        let apiBaseURL = URL(
            string: info["HunLicenseAPIBaseURL"] as? String
                ?? "https://test.dodopayments.com"
        )!
        let betaProductID = info["HunBetaProductID"] as? String
            ?? "pdt_0Nk1wmmFa4aRYUmVDGXSO"
        let productIDs = (info["HunLicenseProductIDs"] as? String ?? betaProductID)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let betaEndsAt = ISO8601DateFormatter().date(
            from: info["HunBetaEndsAt"] as? String
                ?? "2026-08-31T18:29:59Z"
        )!
        let checkoutURL = URL(
            string: info["HunBetaCheckoutURL"] as? String
                ?? "https://test.checkout.dodopayments.com/buy/pdt_0Nk1wmmFa4aRYUmVDGXSO?quantity=1&redirect_url=https://hun.sh%2Fbeta%2Fsuccess"
        )!

        return HunLicenseConfiguration(
            apiBaseURL: apiBaseURL,
            betaProductID: betaProductID,
            allowedProductIDs: Set(productIDs),
            betaEndsAt: betaEndsAt,
            checkoutURL: checkoutURL,
            offlineGracePeriod: 72 * 60 * 60
        )
    }
}

nonisolated enum HunLicensePolicy {
    static func betaHasEnded(
        productID: String,
        now: Date,
        configuration: HunLicenseConfiguration
    ) -> Bool {
        productID == configuration.betaProductID && now >= configuration.betaEndsAt
    }

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
    case expired
    case unavailable(String)
}

@MainActor
@Observable
final class HunLicenseManager {
    private(set) var state: HunLicenseState = .checking
    private(set) var errorMessage: String?

    let configuration: HunLicenseConfiguration

    private let service: HunLicenseServing
    private let store: HunLicenseStoring
    private let now: @Sendable () -> Date

    init(
        configuration: HunLicenseConfiguration = .current,
        service: HunLicenseServing? = nil,
        store: HunLicenseStoring = HunKeychainLicenseStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.service = service ?? HunDodoLicenseService(baseURL: configuration.apiBaseURL)
        self.store = store
        self.now = now
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
        state = .checking
        errorMessage = nil

        guard let stored = try? store.load() else {
            state = .needsActivation
            return
        }

        if HunLicensePolicy.betaHasEnded(
            productID: stored.productID,
            now: now(),
            configuration: configuration
        ) {
            state = .expired
            return
        }

        do {
            let valid = try await service.validate(
                licenseKey: stored.licenseKey,
                instanceID: stored.instanceID
            )
            guard valid else {
                try? store.delete()
                errorMessage = "This license is no longer valid."
                state = .needsActivation
                return
            }

            let validatedAt = now()
            let refreshed = stored.with(lastValidatedAt: validatedAt)
            try store.save(refreshed)
            state = .active(refreshed.session(isOffline: false))
        } catch {
            if HunLicensePolicy.mayUseOffline(
                lastValidatedAt: stored.lastValidatedAt,
                now: now(),
                configuration: configuration
            ) {
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
            errorMessage = "Enter the license key from your beta email."
            return
        }

        state = .activating
        errorMessage = nil

        do {
            let activation = try await service.activate(
                licenseKey: trimmedKey,
                deviceName: Host.current().localizedName ?? "Mac"
            )
            guard configuration.allowedProductIDs.contains(activation.productID) else {
                try? await service.deactivate(
                    licenseKey: trimmedKey,
                    instanceID: activation.instanceID
                )
                throw HunLicenseError.wrongProduct
            }
            guard !HunLicensePolicy.betaHasEnded(
                productID: activation.productID,
                now: now(),
                configuration: configuration
            ) else {
                try? await service.deactivate(
                    licenseKey: trimmedKey,
                    instanceID: activation.instanceID
                )
                state = .expired
                return
            }

            let stored = HunStoredLicense(
                licenseKey: trimmedKey,
                instanceID: activation.instanceID,
                productID: activation.productID,
                productName: activation.productName,
                lastValidatedAt: now()
            )
            try store.save(stored)
            state = .active(stored.session(isOffline: false))
        } catch {
            errorMessage = error.localizedDescription
            state = .needsActivation
        }
    }

    func retryValidation() async {
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
    case rejected(String)
    case wrongProduct

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Dodo Payments returned an unexpected response."
        case let .rejected(message):
            message
        case .wrongProduct:
            "This key is not for Hun."
        }
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
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw HunLicenseError.rejected("Dodo Payments could not deactivate this Mac.")
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
                error?.message ?? "That license key could not be activated."
            )
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data)
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

struct HunKeychainLicenseStore: HunLicenseStoring {
    private let service = "sh.hun.license"
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
