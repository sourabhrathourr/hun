import Foundation

nonisolated enum HunShellEnvironment {
    static func loginEnvironment() async -> [String: String] {
        await Task.detached(priority: .utility) {
            do {
                return try captureLoginEnvironment()
            } catch {
                return ProcessInfo.processInfo.environment
            }
        }.value
    }

    static func captureLoginEnvironment() throws -> [String: String] {
        let parent = ProcessInfo.processInfo.environment
        let home = parent["HOME"] ?? NSHomeDirectory()
        let user = parent["USER"] ?? NSUserName()
        let shell = parent["SHELL"]?.isEmpty == false ? parent["SHELL"]! : "/bin/zsh"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "-i",
            "HOME=\(home)",
            "USER=\(user)",
            "LOGNAME=\(user)",
            "SHELL=\(shell)",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
            shell,
            "-lc",
            "/usr/bin/env -0"
        ]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw HunShellEnvironmentError.captureFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return merge(parent: parent, captured: parseNulSeparatedEnvironment(data))
    }

    static func parseNulSeparatedEnvironment(_ data: Data) -> [String: String] {
        var environment: [String: String] = [:]
        for rawEntry in data.split(separator: 0) {
            guard let entry = String(data: Data(rawEntry), encoding: .utf8),
                  let equals = entry.firstIndex(of: "=")
            else { continue }

            let key = String(entry[..<equals])
            guard !key.isEmpty, key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                continue
            }
            environment[key] = String(entry[entry.index(after: equals)...])
        }
        return environment
    }

    private static func merge(parent: [String: String], captured: [String: String]) -> [String: String] {
        var merged = parent
        for (key, value) in captured {
            merged[key] = value
        }
        return merged
    }
}

nonisolated enum HunShellEnvironmentError: Error, LocalizedError {
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .captureFailed(let message):
            return message.isEmpty ? "could not capture login shell environment" : message
        }
    }
}
