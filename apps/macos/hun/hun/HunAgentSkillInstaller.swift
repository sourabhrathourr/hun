import Foundation

nonisolated enum HunAgentSkillInstaller {
    static let skillName = "hun"

    static func installBundledSkillGlobally() throws -> [URL] {
        guard let source = bundledSkillDirectory() else {
            throw HunAgentSkillInstallError.missingBundledSkill
        }
        return try installSkill(from: source, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Installs one copy in ~/.agents/skills, which Codex and other agents
    /// read, and links the other agents' folders to it. Codex reads both
    /// ~/.agents/skills and ~/.codex/skills and lists a real second copy
    /// twice, but a link once.
    static func installSkill(from source: URL, homeDirectory: URL) throws -> [URL] {
        let destinations = globalSkillDirectories(homeDirectory: homeDirectory)
        let shared = destinations[0]
        try installSkill(from: source, to: shared)
        for destination in destinations.dropFirst() {
            try link(destination, to: shared)
        }
        return destinations.map { $0.appendingPathComponent("SKILL.md") }
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
        try removeHunSkill(at: destination)
        try fileManager.copyItem(at: source, to: destination)
    }

    /// Points destination at the shared copy with a relative link
    /// (../../.agents/skills/hun), the way other skill installers do.
    private static func link(_ destination: URL, to shared: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try removeHunSkill(at: destination)
        let target = "../../" + shared.pathComponents.suffix(3).joined(separator: "/")
        try fileManager.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
    }

    /// Clears what's at url so Hun's skill can go there: a link of any kind,
    /// or an earlier copy of Hun's skill. Anything else is someone else's
    /// skill and is left alone.
    private static func removeHunSkill(at url: URL) throws {
        let fileManager = FileManager.default
        // attributesOfItem doesn't follow links, so a broken one is seen too.
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return }
        if attributes[.type] as? FileAttributeType != .typeSymbolicLink {
            guard isHunSkill(at: url.appendingPathComponent("SKILL.md")) else {
                throw HunAgentSkillInstallError.conflictingSkill(url.path)
            }
        }
        try fileManager.removeItem(at: url)
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
