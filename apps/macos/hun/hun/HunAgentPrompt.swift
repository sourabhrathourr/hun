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
        let skillPath = bundledSkillURL?.path ?? "Not available in this app build. Use the fallback instructions below."
        let globalSkillPaths = globalSkillURLs.isEmpty
            ? "No global Hun skill install detected. Use the bundled skill path or fallback instructions below."
            : globalSkillURLs.map { "- \($0.path)" }.joined(separator: "\n")
        let configPath = URL(fileURLWithPath: projectPath).appendingPathComponent(".hun.yml").path

        return """
        Use the Hun skill to inspect this repository and create or improve .hun.yml.

        Project:
        - name: \(projectName)
        - path: \(projectPath)
        - config: \(configPath)

        Hun skill:
        - If your agent supports local skills, load/use the Hun skill.
        - Global Hun skill install paths:
        \(globalSkillPaths)
        - Bundled fallback path from the Hun macOS app: \(skillPath)
        - If the skill cannot be loaded, follow the fallback workflow in this prompt.

        Goal:
        Configure Hun so this project runs reliably in local development. Hun should manage app services and supporting infrastructure in the way that best matches the repo and my preference.

        First inspect the repo properly:
        - Scan the file tree a few levels deep, skipping .git, node_modules, .venv, vendor, dist, build, target, and Library.
        - Read relevant files such as README, package.json, workspace files, docker-compose.yml/compose.yaml, Dockerfile, Makefile, justfile, Taskfile.yml, Procfile, .env.example, pyproject.toml, requirements.txt, manage.py, go.mod, Cargo.toml, and .github/workflows.
        - Inspect any existing .hun.yml before changing it.

        Run strategy:
        - Prefer hybrid when frontend/backend/workers have clear local commands and infra like postgres, redis, queues, search, or object stores can run in Docker.
        - Prefer local when the repo clearly supports running every needed service locally.
        - Prefer full Docker Compose when compose is clearly the intended dev path or local setup is incomplete.
        - Do not invent services without repo evidence or my confirmation.

        Before editing:
        - Ask me focused questions if there are multiple valid ways to run the app.
        - Ask at most three questions at a time.
        - Focus on choices like local vs Docker vs hybrid, which infra Hun should manage, and which workers/schedulers are needed in dev.

        After editing .hun.yml:
        - Run `hun validate .`.
        - Fix any validation errors.
        - Summarize the chosen strategy, services, commands, ports, and assumptions.
        """
    }
}
