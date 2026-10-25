import Foundation

/// Puts the `hun` command the app ships on the user's PATH, so terminals and
/// coding agents can run `hun` without any setup.
nonisolated enum HunCLILinker {
    /// Folders shells search, most preferred first. The last one is created
    /// when none of them can take the link.
    static func directories(home: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/usr/local/bin"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            home.appendingPathComponent(".local/bin", isDirectory: true),
        ]
    }

    /// Links the release app's bundled CLI, once it is installed in
    /// /Applications. Dev builds and test hosts leave the PATH alone.
    static func linkBundledCLI() {
        guard let cli = Bundle.main.url(forResource: "hun", withExtension: nil),
              cli.path.hasPrefix("/Applications/")
        else { return }
        link(
            cli: cli,
            into: directories(home: FileManager.default.homeDirectoryForCurrentUser)
        )
    }

    /// Makes `hun` in one of `directories` point at `cli`. A link Hun made
    /// earlier is kept current; any other `hun` is the user's own and is left
    /// alone. Returns the link, or nil when nothing was linked.
    @discardableResult
    static func link(cli: URL, into directories: [URL], fileManager: FileManager = .default) -> URL? {
        for directory in directories {
            let link = directory.appendingPathComponent("hun")
            if let destination = try? fileManager.destinationOfSymbolicLink(atPath: link.path) {
                guard isHunAppCLI(destination) else { return nil }
                if destination != cli.path {
                    try? fileManager.removeItem(at: link)
                    try? fileManager.createSymbolicLink(at: link, withDestinationURL: cli)
                }
                return link
            }
            if fileManager.fileExists(atPath: link.path) {
                return nil
            }
        }

        for (index, directory) in directories.enumerated() {
            let isLast = index == directories.count - 1
            if isLast {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            guard fileManager.isWritableFile(atPath: directory.path) else { continue }
            let link = directory.appendingPathComponent("hun")
            if (try? fileManager.createSymbolicLink(at: link, withDestinationURL: cli)) != nil {
                return link
            }
        }
        return nil
    }

    private static func isHunAppCLI(_ path: String) -> Bool {
        path.hasSuffix("hun.app/Contents/Resources/hun")
    }
}
