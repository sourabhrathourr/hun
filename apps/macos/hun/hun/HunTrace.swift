import Foundation

nonisolated enum HunTrace {
    static var addProjectLogPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Hun/add-project.log")
            .path
    }

    static func addProject(_ message: String) {
        append(category: "add-project", message: message)
    }

    static func compact(_ text: String, limit: Int = 1_200) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        if singleLine.count <= limit {
            return singleLine
        }
        return String(singleLine.prefix(limit)) + "...(truncated)"
    }

    private static let queue = DispatchQueue(label: "hun.trace")

    private static func append(category: String, message: String) {
        let path = addProjectLogPath
        let line = "\(timestamp()) [\(category)] \(message)\n"
        queue.async {
            let url = URL(fileURLWithPath: path)
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: path) {
                    FileManager.default.createFile(atPath: path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } catch {
                // Tracing must never break app actions.
            }
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
