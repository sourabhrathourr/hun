import Foundation

// For the welcome's "your first project": the git repos this person worked
// in most recently, from the folders developers usually keep them in. Only
// plain home folders are read: Desktop, Documents and Downloads would make
// macOS ask for permission, so they're left to the folder picker.

nonisolated struct HunProjectSuggestion: Identifiable, Hashable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    /// Where it lives, for display: "~/side-projects".
    let place: String
    /// What it looks like: "Next.js", "Docker Compose", "Swift"…
    let kind: String?
    /// Already has a .hun.yml, so it's added as it is.
    let hasConfig: Bool
    let lastWorkedOn: Date
}

nonisolated enum HunProjectSuggestions {
    private static let roots = [
        "code", "Code", "projects", "Projects", "dev", "Dev", "Developer", "src",
        "work", "Work", "side-projects", "repos", "Repos", "github", "GitHub", "git", "Sites",
    ]

    /// Up to `limit` repos, most recently worked on first, leaving out `excluding`.
    static func find(limit: Int = 4, excluding registered: Set<String> = []) -> [HunProjectSuggestion] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var found: [HunProjectSuggestion] = []
        var seen = Set<String>()

        for root in roots {
            let rootURL = home.appendingPathComponent(root, isDirectory: true)
            guard let children = try? fileManager.contentsOfDirectory(
                at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children {
                // A repo directly in the root, or one level down (an org folder).
                if let suggestion = suggestion(at: child, home: home) {
                    if seen.insert(suggestion.path).inserted { found.append(suggestion) }
                } else if let nested = try? fileManager.contentsOfDirectory(
                    at: child, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
                ) {
                    for grandchild in nested.prefix(40) {
                        if let suggestion = suggestion(at: grandchild, home: home),
                           seen.insert(suggestion.path).inserted {
                            found.append(suggestion)
                        }
                    }
                }
            }
        }

        let registeredPaths = Set(registered.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        return Array(
            found
                .filter { !registeredPaths.contains($0.path) }
                // Repos already set up for Hun first, then the most recent.
                .sorted { ($0.hasConfig ? 1 : 0, $0.lastWorkedOn) > ($1.hasConfig ? 1 : 0, $1.lastWorkedOn) }
                .prefix(limit)
        )
    }

    private static func suggestion(at url: URL, home: URL) -> HunProjectSuggestion? {
        let fileManager = FileManager.default
        let git = url.appendingPathComponent(".git")
        guard fileManager.fileExists(atPath: git.path) else { return nil }
        let configured = fileManager.fileExists(atPath: url.appendingPathComponent(".hun.yml").path)
        guard let kind = projectKind(at: url) ?? (configured ? "" : nil) else { return nil }
        // When the repo was last worked on: its index changes on every commit and stage.
        let index = git.appendingPathComponent("index")
        let date = (try? fileManager.attributesOfItem(atPath: index.path)[.modificationDate] as? Date)
            ?? (try? fileManager.attributesOfItem(atPath: git.path)[.modificationDate] as? Date)
            ?? .distantPast
        let parent = url.deletingLastPathComponent().path
        let place = parent.hasPrefix(home.path) ? "~" + parent.dropFirst(home.path.count) : parent
        return HunProjectSuggestion(
            name: url.lastPathComponent,
            path: url.standardizedFileURL.path,
            place: place,
            kind: kind.isEmpty ? nil : kind,
            hasConfig: fileManager.fileExists(atPath: url.appendingPathComponent(".hun.yml").path),
            lastWorkedOn: date
        )
    }

    /// A short label for what runs here, or nil if nothing looks runnable.
    private static func projectKind(at url: URL) -> String? {
        let fileManager = FileManager.default
        func has(_ name: String) -> Bool {
            fileManager.fileExists(atPath: url.appendingPathComponent(name).path)
        }
        let hasCompose = ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"].contains(where: has)
        if has("package.json") {
            let manifest = (try? String(contentsOf: url.appendingPathComponent("package.json"), encoding: .utf8)) ?? ""
            var label = "Node"
            if manifest.contains("\"next\"") { label = "Next.js" }
            else if manifest.contains("\"vite\"") { label = "Vite" }
            else if manifest.contains("\"expo\"") { label = "Expo" }
            else if manifest.contains("\"@remix-run") || manifest.contains("\"react-router\"") { label = "React" }
            return hasCompose ? "\(label) + Docker" : label
        }
        if hasCompose { return "Docker Compose" }
        if has("pyproject.toml") || has("requirements.txt") || has("manage.py") { return "Python" }
        if has("go.mod") { return "Go" }
        if has("Cargo.toml") { return "Rust" }
        if has("Gemfile") { return "Ruby" }
        if has("Package.swift") { return "Swift" }
        if has("mix.exs") { return "Elixir" }
        if has("Makefile") || has("Procfile") { return "" }
        return nil
    }
}
