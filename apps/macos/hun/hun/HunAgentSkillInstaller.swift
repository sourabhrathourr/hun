import Foundation

nonisolated enum HunAgentSkillInstaller {
    static let skillName = "hun"

    static func installBundledSkillGlobally() throws -> [URL] {
        guard let source = bundledSkillDirectory() else {
            throw HunAgentSkillInstallError.missingBundledSkill
        }
        return try installSkill(from: source, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    static func installSkill(from source: URL, homeDirectory: URL) throws -> [URL] {
        let destinations = globalSkillDirectories(homeDirectory: homeDirectory)
        var installed: [URL] = []
        for destination in destinations {
            try installSkill(from: source, to: destination)
            installed.append(destination.appendingPathComponent("SKILL.md"))
        }
        return installed
    }

    static func existingGlobalSkillURLs(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        globalSkillDirectories(homeDirectory: homeDirectory)
            .map { $0.appendingPathComponent("SKILL.md") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func bundledSkillDirectory() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent("hun-skill")
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("SKILL.md").path) ? url : nil
    }

    static func globalSkillDirectories(homeDirectory: URL) -> [URL] {
        [
            homeDirectory.appendingPathComponent(".agents/skills/\(skillName)"),
            homeDirectory.appendingPathComponent(".codex/skills/\(skillName)"),
            homeDirectory.appendingPathComponent(".cursor/skills/\(skillName)"),
            homeDirectory.appendingPathComponent(".claude/skills/\(skillName)")
        ]
    }

    private static func installSkill(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let sourceSkill = source.appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: sourceSkill.path) else {
            throw HunAgentSkillInstallError.missingSkillFile(sourceSkill.path)
        }

        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            guard isHunSkill(at: destination.appendingPathComponent("SKILL.md")) else {
                throw HunAgentSkillInstallError.conflictingSkill(destination.path)
            }
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func isHunSkill(at url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains("name: hun") && text.contains(".hun.yml")
    }
}

nonisolated enum HunAgentSkillInstallError: Error, LocalizedError {
    case missingBundledSkill
    case missingSkillFile(String)
    case conflictingSkill(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledSkill:
            return "Bundled Hun skill was not found in the app resources."
        case .missingSkillFile(let path):
            return "Hun skill is missing SKILL.md at \(path)."
        case .conflictingSkill(let path):
            return "A non-Hun skill already exists at \(path)."
        }
    }
}
