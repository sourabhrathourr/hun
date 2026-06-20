import Foundation

nonisolated protocol HunProjectInitializing {
    func initializeProject(at url: URL) async throws -> HunProjectInitReview
}

nonisolated struct HunProjectInitializer: HunProjectInitializing {
    func initializeProject(at url: URL) async throws -> HunProjectInitReview {
        let binary = try HunPaths.resolveHunBinary()
        return try await Task.detached(priority: .userInitiated) {
            let configURL = url.appendingPathComponent(".hun.yml")
            let hadConfigBefore = FileManager.default.fileExists(atPath: configURL.path)
            HunTrace.addProject("init start path=\(url.path) binary=\(binary) had_config=\(hadConfigBefore)")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["init", "--profile", "hybrid", "--yes", "--no-register"]
            process.currentDirectoryURL = url

            let input = Pipe()
            let output = Pipe()
            let error = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = error

            try process.run()
            input.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            HunTrace.addProject("init exit status=\(process.terminationStatus) path=\(url.path) stderr=\(HunTrace.compact(stderr)) stdout=\(HunTrace.compact(stdout))")
            guard process.terminationStatus == 0 else {
                throw HunProjectInitError.failed(HunProjectInitError.message(stdout: stdout, stderr: stderr))
            }

            guard FileManager.default.fileExists(atPath: configURL.path) else {
                HunTrace.addProject("init missing_config path=\(configURL.path)")
                throw HunProjectInitError.failed("hun init completed but did not create .hun.yml")
            }
            let contents = try String(contentsOf: configURL, encoding: .utf8)
            HunTrace.addProject("init review_ready path=\(url.path) config=\(configURL.path) created_config=\(!hadConfigBefore)")
            return HunProjectInitReview(
                name: HunProjectInitReview.projectName(in: contents) ?? url.lastPathComponent,
                path: url.path,
                configPath: configURL.path,
                configContents: contents,
                commandOutput: HunProjectInitError.message(stdout: stdout, stderr: stderr),
                createdConfig: !hadConfigBefore
            )
        }.value
    }
}

nonisolated struct HunProjectInitReview: Identifiable, Hashable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    let configPath: String
    let configContents: String
    let commandOutput: String
    let createdConfig: Bool

    var serviceNames: [String] {
        var names: [String] = []
        var inServices = false
        for line in configContents.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed == "services:" {
                inServices = true
                continue
            }
            guard inServices else { continue }
            if !raw.hasPrefix(" ") && !trimmed.isEmpty {
                break
            }
            if raw.hasPrefix("  "),
               !raw.hasPrefix("    "),
               trimmed.hasSuffix(":") {
                names.append(String(trimmed.dropLast()))
            }
        }
        return names
    }

    static func projectName(in contents: String) -> String? {
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("name:") else { continue }
            let raw = trimmed.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
            return raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }
}

nonisolated enum HunProjectInitError: Error, LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }

    static func message(stdout: String, stderr: String) -> String {
        let combined = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return combined.isEmpty ? "hun init failed" : combined
    }
}
