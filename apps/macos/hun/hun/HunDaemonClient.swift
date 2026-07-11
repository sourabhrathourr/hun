import Darwin
import Foundation

nonisolated protocol HunDaemonSupervisorProtocol {
    func ensureDaemon() async throws
    func restartDaemon() async throws
}

nonisolated protocol HunDaemonClientProtocol: AnyObject {
    func daemonInfo() async throws -> HunDaemonInfo
    func snapshot(force: Bool) async throws -> HunDaemonSnapshot
    func registerProject(path: String) async throws
    func startProject(_ project: String, mode: HunDaemonStartMode) async throws
    func startService(_ project: String, service: String, mode: HunDaemonStartMode) async throws
    func setProjectIcon(_ project: String, path: String) async throws
    func clearProjectIcon(_ project: String) async throws
    func stopProject(_ project: String) async throws
    func stopService(_ project: String, service: String) async throws
    func restartProject(_ project: String) async throws
    func restartService(_ project: String, service: String) async throws
    func removeService(_ project: String, service: String) async throws
    func setMode(_ mode: HunMode, preferredProject: String?) async throws
    func logs(project: String, service: String?, lines: Int) async throws -> [HunDaemonLogLine]
    func subscribe(
        project: String,
        service: String?,
        onLine: @escaping @Sendable (HunDaemonLogLine) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws -> HunLogSubscribing
}

nonisolated struct HunDaemonInfo: Decodable, Equatable {
    let status: String
    let protocolVersion: Int
    let version: String
    let commit: String
    let pid: Int
    let startedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case protocolVersion = "protocol"
        case version
        case commit
        case pid
        case startedAt = "started_at"
    }

    init(
        status: String,
        protocolVersion: Int,
        version: String,
        commit: String,
        pid: Int,
        startedAt: String
    ) {
        self.status = status
        self.protocolVersion = protocolVersion
        self.version = version
        self.commit = commit
        self.pid = pid
        self.startedAt = startedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        protocolVersion = try container.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? 0
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "unknown"
        commit = try container.decodeIfPresent(String.self, forKey: .commit) ?? "none"
        pid = try container.decodeIfPresent(Int.self, forKey: .pid) ?? 0
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt) ?? ""
    }
}

nonisolated protocol HunLogSubscribing: AnyObject {
    func cancel()
}

nonisolated enum HunDaemonStartMode: String {
    case exclusive
    case parallel
}

nonisolated struct HunDaemonSnapshot: Decodable, Equatable {
    let protocolVersion: Int
    let mode: String
    let activeProject: String?
    let scanDirs: [String]
    let lastScanAt: String?
    let projects: [HunDaemonProject]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case mode
        case activeProject = "active_project"
        case scanDirs = "scan_dirs"
        case lastScanAt = "last_scan_at"
        case projects
        case warnings
    }

    init(
        protocolVersion: Int,
        mode: String,
        activeProject: String?,
        scanDirs: [String],
        lastScanAt: String?,
        projects: [HunDaemonProject],
        warnings: [String]
    ) {
        self.protocolVersion = protocolVersion
        self.mode = mode
        self.activeProject = activeProject
        self.scanDirs = scanDirs
        self.lastScanAt = lastScanAt
        self.projects = projects
        self.warnings = warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "focus"
        activeProject = try container.decodeIfPresent(String.self, forKey: .activeProject)
        scanDirs = try container.decodeIfPresent([String].self, forKey: .scanDirs) ?? []
        lastScanAt = try container.decodeIfPresent(String.self, forKey: .lastScanAt)
        projects = try container.decodeIfPresent([HunDaemonProject].self, forKey: .projects) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

nonisolated struct HunDaemonProject: Decodable, Equatable {
    let id: String
    let name: String
    let path: String
    let iconPath: String?
    let iconCustom: Bool
    let status: String
    let isActive: Bool
    let branch: String?
    let lastNote: String?
    let startedAt: String?
    let services: [HunDaemonService]
    let configError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case iconPath = "icon_path"
        case iconCustom = "icon_custom"
        case status
        case isActive = "is_active"
        case branch
        case lastNote = "last_note"
        case startedAt = "started_at"
        case services
        case configError = "config_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        iconPath = try container.decodeIfPresent(String.self, forKey: .iconPath)
        iconCustom = try container.decodeIfPresent(Bool.self, forKey: .iconCustom) ?? false
        status = try container.decode(String.self, forKey: .status)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        lastNote = try container.decodeIfPresent(String.self, forKey: .lastNote)
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        services = try container.decodeIfPresent([HunDaemonService].self, forKey: .services) ?? []
        configError = try container.decodeIfPresent(String.self, forKey: .configError)
    }

    init(
        id: String,
        name: String,
        path: String,
        iconPath: String? = nil,
        iconCustom: Bool = false,
        status: String,
        isActive: Bool,
        branch: String?,
        lastNote: String?,
        startedAt: String?,
        services: [HunDaemonService],
        configError: String?
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.iconPath = iconPath
        self.iconCustom = iconCustom
        self.status = status
        self.isActive = isActive
        self.branch = branch
        self.lastNote = lastNote
        self.startedAt = startedAt
        self.services = services
        self.configError = configError
    }
}

nonisolated struct HunDaemonService: Decodable, Equatable {
    let id: String
    let name: String
    let cmd: String?
    let pid: Int
    let port: Int
    let status: String
    let running: Bool
    let ready: Bool
}

nonisolated struct HunDaemonLogLine: Decodable, Equatable {
    let timestamp: String
    let service: String
    let project: String
    let text: String
    let isErr: Bool

    enum CodingKeys: String, CodingKey {
        case timestamp
        case service
        case project
        case text
        case isErr = "is_err"
    }
}

nonisolated final class HunDaemonClient: HunDaemonClientProtocol {
    private static let requiredProtocol = 12
    private let socketPath: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(socketPath: String = HunPaths.socketPath) {
        self.socketPath = socketPath
    }

    func daemonInfo() async throws -> HunDaemonInfo {
        try await request(HunDaemonRequest(action: "ping"), timeoutNanoseconds: 500_000_000)
    }

    func snapshot(force: Bool) async throws -> HunDaemonSnapshot {
        try await request(HunDaemonRequest(action: force ? "refresh" : "snapshot"))
    }

    func registerProject(path: String) async throws {
        try await send(HunDaemonRequest(action: "register_project", path: path))
    }

    func startProject(_ project: String, mode: HunDaemonStartMode) async throws {
        try await send(HunDaemonRequest(action: "start", project: project, mode: mode.rawValue))
    }

    func startService(_ project: String, service: String, mode: HunDaemonStartMode) async throws {
        try await send(HunDaemonRequest(action: "start_service", project: project, service: service, mode: mode.rawValue))
    }

    func setProjectIcon(_ project: String, path: String) async throws {
        try await send(HunDaemonRequest(action: "set_project_icon", project: project, path: path))
    }

    func clearProjectIcon(_ project: String) async throws {
        try await send(HunDaemonRequest(action: "clear_project_icon", project: project))
    }

    func stopProject(_ project: String) async throws {
        try await send(HunDaemonRequest(action: "stop", project: project))
    }

    func stopService(_ project: String, service: String) async throws {
        try await send(HunDaemonRequest(action: "stop_service", project: project, service: service))
    }

    func restartProject(_ project: String) async throws {
        try await send(HunDaemonRequest(action: "restart", project: project))
    }

    func restartService(_ project: String, service: String) async throws {
        try await send(HunDaemonRequest(action: "restart", project: project, service: service))
    }

    func removeService(_ project: String, service: String) async throws {
        try await send(HunDaemonRequest(action: "remove_service", project: project, service: service))
    }

    func setMode(_ mode: HunMode, preferredProject: String?) async throws {
        try await send(HunDaemonRequest(
            action: "focus",
            project: preferredProject,
            mode: mode.rawValue
        ))
    }

    func logs(project: String, service: String?, lines: Int) async throws -> [HunDaemonLogLine] {
        try await request(HunDaemonRequest(action: "logs", project: project, service: service, lines: lines))
    }

    func subscribe(
        project: String,
        service: String?,
        onLine: @escaping @Sendable (HunDaemonLogLine) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws -> HunLogSubscribing {
        try HunLogSubscription(socketPath: socketPath, project: project, service: service, onLine: onLine, onError: onError)
    }

    func ping() async -> Bool {
        (try? await daemonInfo())?.status == "pong"
    }

    func isCompatibleDaemon() async -> Bool {
        await daemonProtocol() == Self.requiredProtocol
    }

    private func daemonProtocol() async -> Int? {
        guard let info = try? await daemonInfo(), info.status == "pong" else { return nil }
        return info.protocolVersion
    }

    func supportsSnapshot() async -> Bool {
        do {
            let _: HunDaemonSnapshot = try await request(HunDaemonRequest(action: "snapshot"), timeoutNanoseconds: 500_000_000)
            return true
        } catch {
            return false
        }
    }

    private func send(_ request: HunDaemonRequest) async throws {
        let _: StatusPayload = try await self.request(request)
    }

    private func request<T: Decodable>(_ request: HunDaemonRequest, timeoutNanoseconds: UInt64? = nil) async throws -> T {
        let payload = try encoder.encode(request)
        let socketPath = self.socketPath
        let responseData = try await Task.detached(priority: .userInitiated) {
            try UnixSocket.roundTrip(socketPath: socketPath, payload: payload, timeoutNanoseconds: timeoutNanoseconds)
        }.value
        let envelope = try decoder.decode(HunDaemonEnvelope<T>.self, from: responseData)
        guard envelope.ok else {
            throw HunDaemonError.daemon(envelope.error ?? "unknown daemon error")
        }
        guard let data = envelope.data else {
            throw HunDaemonError.missingData
        }
        return data
    }
}

nonisolated final class HunDaemonSupervisor: HunDaemonSupervisorProtocol {
    private let client: HunDaemonClient

    init(client: HunDaemonClient = HunDaemonClient()) {
        self.client = client
    }

    func ensureDaemon() async throws {
        if await client.isCompatibleDaemon() {
            return
        }

        try await restartDaemon()
    }

    func restartDaemon() async throws {
        let info = try? await client.daemonInfo()
        try terminateExistingDaemon(
            reportedPID: info?.pid ?? 0,
            socketResponded: info?.status == "pong"
        )
        try await launchDaemon()
    }

    private func launchDaemon() async throws {
        let binary = try HunPaths.resolveHunBinary()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["daemon"]
        var environment = await HunShellEnvironment.loginEnvironment()
        environment["HUN_HOME"] = HunPaths.homeURL.path
        process.environment = environment
        process.standardInput = nil
        process.standardOutput = nil
        process.standardError = nil
        try process.run()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            if await client.isCompatibleDaemon() {
                return
            }
        }
        throw HunDaemonError.daemon("daemon did not become ready")
    }

    private func terminateExistingDaemon(reportedPID: Int, socketResponded: Bool) throws {
        let pid = resolvedDaemonProcessID(reportedPID: reportedPID, pidPath: HunPaths.pidPath)
        guard let pid else {
            if socketResponded {
                throw HunDaemonError.daemon("daemon is healthy but did not report a process ID")
            }
            return
        }

        terminateDaemonProcess(pid)
        try? FileManager.default.removeItem(atPath: HunPaths.socketPath)
        try? FileManager.default.removeItem(atPath: HunPaths.pidPath)
    }

    private func terminateDaemonProcess(_ pid: Int32) {
        Darwin.kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if Darwin.kill(pid, 0) != 0 {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if Darwin.kill(pid, 0) == 0 {
            Darwin.kill(pid, SIGKILL)
        }
    }

}

nonisolated final class HunLogSubscription: HunLogSubscribing {
    private let socket: SocketHandle
    private let task: Task<Void, Never>

    init(
        socketPath: String,
        project: String,
        service: String?,
        onLine: @escaping @Sendable (HunDaemonLogLine) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        let fd = try UnixSocket.connect(path: socketPath, timeoutNanoseconds: nil)
        let socket = SocketHandle(fd)
        self.socket = socket
        let request = HunDaemonRequest(action: "subscribe", project: project, service: service)
        let payload = try JSONEncoder().encode(request) + Data([0x0A])
        try UnixSocket.writeAll(socket: fd, payload: payload)

        task = Task.detached(priority: .utility) {
            do {
                defer { socket.close() }
                _ = try UnixSocket.readLine(socket: fd)
                let decoder = JSONDecoder()
                while !Task.isCancelled {
                    let lineData = try UnixSocket.readLine(socket: fd)
                    if lineData.isEmpty {
                        continue
                    }
                    let line = try decoder.decode(HunDaemonLogLine.self, from: lineData)
                    onLine(line)
                }
            } catch {
                if !Task.isCancelled {
                    onError(error)
                }
            }
        }
    }

    func cancel() {
        task.cancel()
        socket.shutdown()
        socket.close()
    }

    deinit {
        cancel()
    }
}

nonisolated func resolvedDaemonProcessID(reportedPID: Int, pidPath: String) -> Int32? {
    if reportedPID > 0, reportedPID <= Int(Int32.max) {
        return Int32(reportedPID)
    }
    guard let pidText = try? String(contentsOfFile: pidPath, encoding: .utf8),
          let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)),
          pid > 0
    else {
        return nil
    }
    return pid
}

nonisolated private final class SocketHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32?

    init(_ fd: Int32) {
        self.fd = fd
    }

    func shutdown() {
        lock.lock()
        let current = fd
        lock.unlock()
        if let current {
            Darwin.shutdown(current, SHUT_RDWR)
        }
    }

    func close() {
        lock.lock()
        let current = fd
        fd = nil
        lock.unlock()
        if let current {
            Darwin.close(current)
        }
    }
}

nonisolated private struct HunDaemonRequest: Encodable {
    let action: String
    var project: String?
    var service: String?
    var path: String?
    var mode: String?
    var lines: Int?
}

nonisolated private struct HunDaemonEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let error: String?
    let data: T?
}

nonisolated private struct StatusPayload: Decodable {}

nonisolated enum HunDaemonError: Error, LocalizedError {
    case daemon(String)
    case missingData
    case socket(String)
    case binaryNotFound

    var errorDescription: String? {
        switch self {
        case .daemon(let message):
            return message
        case .missingData:
            return "daemon response did not include data"
        case .socket(let message):
            return message
        case .binaryNotFound:
            return "could not find hun binary"
        }
    }
}

nonisolated enum HunPaths {
    #if DEBUG
    static let environmentName = "Development"
    private static let directoryName = ".hun-dev"
    #else
    static let environmentName = "Production"
    private static let directoryName = ".hun"
    #endif

    static var homeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static var socketPath: String {
        homeURL.appendingPathComponent("daemon.sock").path
    }

    static var pidPath: String {
        homeURL.appendingPathComponent("daemon.pid").path
    }

    static var configURL: URL { homeURL.appendingPathComponent("config.yml") }
    static var stateURL: URL { homeURL.appendingPathComponent("state.json") }
    static var logsURL: URL { homeURL.appendingPathComponent("logs", isDirectory: true) }

    static func resolveHunBinary() throws -> String {
        var candidates: [String] = []
        if let bundled = Bundle.main.url(forResource: "hun", withExtension: nil)?.path {
            candidates.append(bundled)
        }
        candidates.append(contentsOf: ["/opt/homebrew/bin/hun", "/usr/local/bin/hun"])
        let pathCandidates = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map { String($0) + "/hun" } ?? []
        candidates.append(contentsOf: pathCandidates)

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw HunDaemonError.binaryNotFound
    }
}

nonisolated enum UnixSocket {
    static func roundTrip(socketPath: String, payload: Data, timeoutNanoseconds: UInt64?) throws -> Data {
        let fd = try connect(path: socketPath, timeoutNanoseconds: timeoutNanoseconds)
        defer { Darwin.close(fd) }
        try writeAll(socket: fd, payload: payload + Data([0x0A]))
        return try readLine(socket: fd)
    }

    static func connect(path: String, timeoutNanoseconds: UInt64?) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw HunDaemonError.socket(String(cString: strerror(errno)))
        }

        if let timeoutNanoseconds {
            var timeout = timeval(
                tv_sec: Int(timeoutNanoseconds / 1_000_000_000),
                tv_usec: Int32((timeoutNanoseconds % 1_000_000_000) / 1_000)
            )
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString.map { UInt8(bitPattern: $0) }
        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= maxPathLength else {
            Darwin.close(fd)
            throw HunDaemonError.socket("socket path is too long")
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.copyBytes(from: pathBytes)
        }

        let length = socklen_t(MemoryLayout<sockaddr_un>.offset(of: \.sun_path)! + pathBytes.count)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, length)
            }
        }
        guard result == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fd)
            throw HunDaemonError.socket(message)
        }
        return fd
    }

    static func writeAll(socket: Int32, payload: Data) throws {
        try payload.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var written = 0
            while written < payload.count {
                let result = Darwin.write(socket, base.advanced(by: written), payload.count - written)
                if result < 0 {
                    throw HunDaemonError.socket(String(cString: strerror(errno)))
                }
                written += result
            }
        }
    }

    static func readLine(socket: Int32) throws -> Data {
        var data = Data()
        var byte: UInt8 = 0
        while true {
            let count = Darwin.read(socket, &byte, 1)
            if count == 0 {
                if data.isEmpty {
                    throw HunDaemonError.socket("connection closed")
                }
                return data
            }
            if count < 0 {
                throw HunDaemonError.socket(String(cString: strerror(errno)))
            }
            if byte == 0x0A {
                return data
            }
            data.append(byte)
        }
    }
}
