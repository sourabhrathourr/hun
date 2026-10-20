import Foundation

nonisolated enum HunAgentPromptBuilder {
    static func bundledSkillURL() -> URL? {
        HunAgentSkillInstaller.bundledSkillDirectory()?.appendingPathComponent("SKILL.md")
    }

    static func prompt(
        for project: HunProject,
        bundledSkillURL: URL? = bundledSkillURL(),
        globalSkillURLs: [URL] = HunAgentSkillInstaller.existingGlobalSkillURLs()
    ) -> String {
        prompt(
            projectName: project.name,
            projectPath: project.path,
            bundledSkillURL: bundledSkillURL,
            globalSkillURLs: globalSkillURLs
        )
    }

    static func prompt(
        for review: HunProjectInitReview,
        bundledSkillURL: URL? = bundledSkillURL(),
        globalSkillURLs: [URL] = HunAgentSkillInstaller.existingGlobalSkillURLs()
    ) -> String {
        prompt(
            projectName: review.name,
            projectPath: review.path,
            bundledSkillURL: bundledSkillURL,
            globalSkillURLs: globalSkillURLs
        )
    }

    private static func prompt(
        projectName: String,
        projectPath: String,
        bundledSkillURL: URL?,
        globalSkillURLs: [URL]
    ) -> String {
        let configPath = URL(fileURLWithPath: projectPath).appendingPathComponent(".hun.yml").path
        let skillPaths = (globalSkillURLs + [bundledSkillURL].compactMap { $0 }).map { "- \($0.path)" }
        let skill = skillPaths.isEmpty
            ? "If the Hun skill isn't available, keep .hun.yml simple: one service per thing that runs in development, using the commands the project already uses."
            : "If your agent can't load skills, read the Hun skill from one of these:\n" + skillPaths.joined(separator: "\n")

        return """
        Use the Hun skill to set up .hun.yml for this project.

        - name: \(projectName)
        - path: \(projectPath)
        - config: \(configPath)

        \(skill)

        Keep it quick: use the commands the project already uses, change only what's wrong if a .hun.yml exists, run `hun validate .`, and tell me in a few lines what you set up. If there are more than three or so services, suggest profiles for what I usually run together.
        """
    }
}
