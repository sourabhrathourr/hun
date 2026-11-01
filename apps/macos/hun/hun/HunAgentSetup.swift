import Foundation

// Hun asks the coding agent already on the Mac (Claude Code, then Codex) to
// write a project's .hun.yml, because an agent that reads the repo gets
// ports, dependencies and "local or Docker?" right where fixed rules can't.
//
// The agent only reads. It returns the whole file and a one-line summary as
// structured output; Hun saves it through the daemon, which validates it.
// Follow-up requests ("put the API in Docker") resume the same session.

// MARK: - Agents

nonisolated enum HunAgentKind: String, CaseIterable, Sendable, Codable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    /// For sentences: "Claude is reading…", "Ask Codex…".
    var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    fileprivate var executable: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        }
    }
}

nonisolated struct HunAgent: Sendable, Equatable {
    let kind: HunAgentKind
    let url: URL
}

nonisolated enum HunAgentLocator {
    /// The agent to use: Claude Code if it's installed, then Codex.
    static func preferred(environment: [String: String]) -> HunAgent? {
        installed(environment: environment).first
    }

    static func installed(environment: [String: String]) -> [HunAgent] {
        HunAgentKind.allCases.compactMap { kind in
            find(kind.executable, environment: environment).map { HunAgent(kind: kind, url: $0) }
        }
    }

    /// Looks on PATH, then where installers usually put these tools: a login
    /// shell's PATH often misses nvm, Volta and friends, which are set up in
    /// the interactive shell only.
    static func find(_ name: String, environment: [String: String]) -> URL? {
        let home = environment["HOME"] ?? NSHomeDirectory()
        var directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        directories += [
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "\(home)/.npm-global/bin",
            "\(home)/Library/pnpm",
        ]
        directories += nvmBinDirectories(home: home)
        let fileManager = FileManager.default
        for directory in directories where !directory.isEmpty {
            let path = (directory as NSString).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// nvm's node versions, newest first.
    private static func nvmBinDirectories(home: String) -> [String] {
        let root = "\(home)/.nvm/versions/node"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        return versions
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { "\(root)/\($0)/bin" }
    }
}

// MARK: - Results

nonisolated struct HunAgentResult: Sendable, Equatable {
    let yaml: String
    let summary: String
    /// For follow-ups. Nil if the agent didn't report one.
    let sessionID: String?
}

nonisolated enum HunAgentError: LocalizedError, Equatable {
    case failed(String)
    case timedOut
    case noOutput

    var errorDescription: String? {
        switch self {
        case let .failed(message): return message
        case .timedOut: return "That took too long. Try again, or ask for something smaller."
        case .noOutput: return "The agent finished without returning a setup. Try asking again."
        }
    }

    /// A sentence a person can act on, for an error from `agent`.
    static func friendly(_ error: Error, agent: HunAgentKind) -> String {
        let message = error.localizedDescription
        let lower = message.lowercased()
        if lower.contains("not logged in") || lower.contains("/login") || lower.contains("unauthorized")
            || lower.contains("authentication") || lower.contains("api key") {
            return "\(agent.displayName) isn't signed in. Open a terminal, run `\(agent == .claude ? "claude" : "codex")` and sign in, then try again."
        }
        if lower.contains("rate limit") || lower.contains("usage limit") || lower.contains("quota") || lower.contains("overloaded") {
            return "\(agent.displayName) is at its usage limit right now. Try again in a little while."
        }
        if lower.contains("network") || lower.contains("connection") || lower.contains("offline") || lower.contains("enotfound") {
            return "\(agent.displayName) couldn't reach its servers. Check your connection and try again."
        }
        return message
    }
}

// MARK: - What Hun asks

nonisolated enum HunAgentBrief {
    /// The first setup of a project.
    static let setup = """
    Write the .hun.yml for the project in the current directory. Hun (a macOS app) runs a project's dev services from this file.

    A .hun.yml may already be in the folder: it's a rough first guess. Work out the setup yourself from the project, and don't mention that file.

    You can only read files. Do not run, install or change anything. Be quick: look at the README, package.json scripts, lockfiles, docker-compose files, Makefile, Procfile and the folder layout, and stop once you know how each part is started in development.

    Deciding how each part runs:
    1. Follow the project's own instructions first (README, Makefile, docs): how the team actually runs it in development wins.
    2. Otherwise run code people edit (frontends, APIs, workers) locally, with the project's dev scripts, so it hot-reloads.
    3. Run infrastructure people don't edit (databases, caches, queues, mail catchers, emulators) in Docker, as `docker compose up <name>`, when the compose file defines it.
    4. Run app code in Docker only when the project is clearly built for that (source mounted for hot reload, or no local setup documented).
    5. Never run the same thing both ways: one service per thing.
    6. In the summary, say what you chose where it wasn't obvious (e.g. "the API runs locally; its Docker container is left out").

    Rules:
    - `name`: the folder name.
    - Don't open `.env` files or anything else that may hold secrets.
    - Use the package manager the lockfile shows (package-lock.json is npm, pnpm-lock.yaml is pnpm, yarn.lock is yarn, bun.lock or bun.lockb is bun).
    - Before giving a service a port, check its own package.json, config or entry point.
    - If one root command starts several apps at once (turbo, concurrently, npm-run-all), give each app its own service so each gets its own logs.
    - Leave out mobile apps, simulators and one-off tools unless the README's everyday dev flow starts them. Compose services behind a `profiles:` entry are optional: leave them out unless the README's everyday flow starts them.
    - One service for each thing that runs in development, using the commands the project already uses. Don't add install, build, migration or test steps.
    - There is always at least one service. For an app with no server (a Mac or desktop app, a CLI, a game), the service is how it's run during development: `swift run <name>`, `make run`, `cargo run` or similar.
    - Each Docker Compose service gets its own Hun service: `docker compose up <name>` (with `cwd` if the compose file isn't at the root).
    - `cwd: ./sub` only when it isn't the project root.
    - `port:` when the service listens on a known port. If its command fixes the port, use `$PORT` in the command (`--port $PORT`, or `npm run dev -- --port $PORT` for Vite) and keep `port:` as the usual number.
    - `port_env: NAME` only if the app reads its port from a variable other than PORT.
    - `depends_on: [service]` when a service needs another running first (an API on its database, a worker on its queue).
    - `ready: "text"` only if you know the exact line the service prints when it's up.
    - `env:` only if the app can't start without it, and never secrets.
    - If there are more than three services, add a few obvious `profiles` named after what someone works on (`web`, `api`, `workers`). List only services people work on; `depends_on` services (databases, caches) come along, so don't list them.

    Example:

    ```yaml
    name: shop
    services:
      web:
        cmd: npm run dev -- --port $PORT
        cwd: ./web
        port: 5173
        depends_on: [api]
      api:
        cmd: uv run uvicorn app.main:app --reload --port $PORT
        cwd: ./api
        port: 8000
        depends_on: [db]
      db:
        cmd: docker compose up db
        port: 5432
    profiles:
      web: [web]
    ```

    Return the whole file in `yaml`, and a one or two sentence `summary` for the person using the app: what runs and how, in plain words. Don't mention validating the file or reading and writing permissions.
    """

    /// A message from the setup chat. `state` is what's running now and the
    /// latest log lines, so questions like "why did the API crash?" can be answered.
    static func change(_ request: String, current: String, state: String? = nil) -> String {
        let stateSection = state.map { "\n\nWhat's happening in Hun right now:\n\n\($0)" } ?? ""
        return """
        The person using Hun says:

        \(request)

        The current file:

        ```yaml
        \(current)
        ```\(stateSection)

        If they're asking for a change, read what you need, change only that, and follow the same rules as before. Return the whole updated file in `yaml`, and one sentence in `summary` saying what changed.

        If they're asking a question, answer it in `summary` in a few plain sentences (use the logs above when they ask why something failed), and return the file exactly as it is, without adding comments. If a fix belongs in .hun.yml, offer it; if it belongs in their code, say what to change.

        You can still only read files.

        \(replyStyle)
        """
    }

    /// How replies read in the chat.
    static let replyStyle = """
    How to write `summary`, your reply in the chat: two or three short sentences, unless they asked for an explanation. When you list things, put each on its own line starting with "- ". Plain words, no headings. Don't mention validating the file, reading or writing permissions, or how Hun works inside: Hun checks and saves the file for you.
    """

    /// When the daemon rejects what the agent returned.
    static func fix(_ problem: String) -> String {
        """
        Hun couldn't use that file: \(problem)

        Fix it and return the whole file again in `yaml`, with the same `summary`.
        """
    }

    /// `summary` comes first so the reply streams before the file.
    static let schema = """
    {"type":"object","additionalProperties":false,"required":["summary","yaml"],"properties":{"summary":{"type":"string","description":"Your reply to the person, in plain sentences: what you set up or changed, or the answer to their question"},"yaml":{"type":"string","description":"The complete .hun.yml file"}}}
    """
}

// MARK: - Progress

/// What the agent is doing, as it happens.
nonisolated enum HunAgentEvent: Sendable, Equatable {
    /// A step, with the project files it reads.
    case step(String, files: [String])
    /// Between steps, working out what to do next.
    case thinking
    /// The reply so far, as it's written.
    case reply(String)
}

// MARK: - Running an agent

nonisolated enum HunAgentRunner {
    /// Runs the agent in `directory` with `prompt` (resuming `sessionID` when
    /// given) and returns its file. `onEvent` gets progress as the
    /// agent works ("Reading README.md"). Cancelling the task stops the agent.
    static func run(
        _ agent: HunAgent,
        in directory: URL,
        prompt: String,
        resuming sessionID: String? = nil,
        environment: [String: String],
        timeout: TimeInterval = 150,
        onEvent: @escaping @Sendable (HunAgentEvent) -> Void
    ) async throws -> HunAgentResult {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("hun-agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let schemaURL = scratch.appendingPathComponent("schema.json")
        let outputURL = scratch.appendingPathComponent("output.json")
        try HunAgentBrief.schema.write(to: schemaURL, atomically: true, encoding: .utf8)

        let arguments: [String]
        switch agent.kind {
        case .claude:
            arguments = claudeArguments(prompt: prompt, sessionID: sessionID)
        case .codex:
            arguments = codexArguments(prompt: prompt, sessionID: sessionID, schema: schemaURL, output: outputURL)
        }

        let parser = HunAgentStreamParser(kind: agent.kind, onEvent: onEvent)
        let process = Process()
        process.executableURL = agent.url
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = agentEnvironment(environment, agent: agent)
        // Codex waits for more input on stdin if it's left open.
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let errorBuffer = HunLockedData()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { parser.consume(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errorBuffer.append(data) }
        }

        let status: Int32 = try await withTaskCancellationHandler {
            try process.run()
            return try await waitForExit(process, timeout: timeout)
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        parser.consume(stdout.fileHandleForReading.readDataToEndOfFile())
        parser.finish()
        try Task.checkCancellation()

        var structured = parser.result
        if agent.kind == .codex, let data = try? Data(contentsOf: outputURL) {
            structured = HunAgentStreamParser.decodeOutput(data) ?? structured
        }
        if let structured, !structured.yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return HunAgentResult(yaml: structured.yaml, summary: structured.summary, sessionID: parser.sessionID ?? sessionID)
        }
        if let message = parser.errorMessage {
            throw HunAgentError.failed(message)
        }
        if status != 0 {
            let text = String(data: errorBuffer.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw HunAgentError.failed(lastLine(of: text) ?? "\(agent.kind.displayName) stopped (exit \(status)).")
        }
        throw HunAgentError.noOutput
    }

    static func claudeArguments(prompt: String, sessionID: String?) -> [String] {
        var arguments = [
            "-p", prompt,
            // Read-only: plan mode can look but not change anything.
            "--permission-mode", "plan",
            "--output-format", "stream-json",
            "--verbose",
            // Streams the reply as it's written.
            "--include-partial-messages",
            "--json-schema", HunAgentBrief.schema,
            "--model", "sonnet",
            // The person's own hooks and MCP servers are for their sessions,
            // not for Hun's.
            "--settings", #"{"disableAllHooks":true}"#,
            "--strict-mcp-config",
        ]
        if let sessionID {
            arguments += ["--resume", sessionID]
        }
        return arguments
    }

    static func codexArguments(prompt: String, sessionID: String?, schema: URL, output: URL) -> [String] {
        // Config overrides go before the subcommand so they apply to resume too.
        var arguments = [
            "-c", #"sandbox_mode="read-only""#,
            "-c", #"model_reasoning_effort="low""#,
            "exec",
        ]
        if let sessionID {
            arguments += ["resume", sessionID]
        }
        arguments += [
            "--json",
            "--skip-git-repo-check",
            "--output-schema", schema.path,
            "-o", output.path,
            prompt,
        ]
        return arguments
    }

    /// The person's environment, with the agent's own folder first on PATH:
    /// tools installed with nvm need their `node` next to them.
    private static func agentEnvironment(_ environment: [String: String], agent: HunAgent) -> [String: String] {
        var result = environment
        let directory = agent.url.deletingLastPathComponent().path
        let path = result["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        result["PATH"] = "\(directory):\(path)"
        result["NO_COLOR"] = "1"
        return result
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) async throws -> Int32 {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                throw CancellationError()
            }
            if Date() > deadline {
                process.terminate()
                throw HunAgentError.timedOut
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return process.terminationStatus
    }

    private static func lastLine(of text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }
}

// MARK: - Reading the agent's stream

/// Turns the agent's JSON event stream into progress lines and its result.
nonisolated final class HunAgentStreamParser: @unchecked Sendable {
    struct Output: Equatable {
        let yaml: String
        let summary: String
    }

    private let kind: HunAgentKind
    private let onEvent: @Sendable (HunAgentEvent) -> Void
    private let lock = NSLock()
    private var buffer = Data()
    private var lastStep: String?
    /// The structured reply's content block, and its JSON so far.
    private var outputBlockIndex: Int?
    private var outputJSON = ""
    private var lastReply = ""

    private(set) var sessionID: String?
    private(set) var result: Output?
    private(set) var errorMessage: String?

    init(kind: HunAgentKind, onEvent: @escaping @Sendable (HunAgentEvent) -> Void) {
        self.kind = kind
        self.onEvent = onEvent
    }

    func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        lock.unlock()
        lines.forEach(handle)
    }

    func finish() {
        lock.lock()
        let rest = buffer
        buffer.removeAll()
        lock.unlock()
        if !rest.isEmpty { handle(rest) }
    }

    static func decodeOutput(_ data: Data) -> Output? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return output(from: object)
    }

    private static func output(from object: [String: Any]) -> Output? {
        guard let yaml = object["yaml"] as? String else { return nil }
        return Output(yaml: yaml, summary: (object["summary"] as? String) ?? "")
    }

    private func handle(_ line: Data) {
        guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        switch kind {
        case .claude: handleClaude(event)
        case .codex: handleCodex(event)
        }
    }

    private func handleClaude(_ event: [String: Any]) {
        if let id = event["session_id"] as? String, !id.isEmpty { sessionID = id }
        switch event["type"] as? String {
        case "stream_event":
            handleClaudeStreamEvent(event["event"] as? [String: Any] ?? [:])
        case "user":
            // A tool came back; the agent decides what to do next.
            onEvent(.thinking)
        case "assistant":
            let message = event["message"] as? [String: Any]
            for part in (message?["content"] as? [[String: Any]]) ?? [] where part["type"] as? String == "tool_use" {
                let name = part["name"] as? String ?? ""
                let input = part["input"] as? [String: Any] ?? [:]
                switch name {
                case "StructuredOutput":
                    if let output = Self.output(from: input) { result = output }
                    step("Writing .hun.yml")
                case "Read":
                    if let path = input["file_path"] as? String {
                        let file = Self.displayPath(path)
                        step("Reading \(file)", files: [file])
                    }
                case "Glob", "Grep", "LS":
                    step("Looking through the project")
                case "Bash":
                    let described = Self.describe(command: input["command"] as? String ?? "")
                    step(described.text, files: described.files)
                default:
                    break
                }
            }
        case "result":
            if let output = (event["structured_output"] as? [String: Any]).flatMap(Self.output(from:)) {
                result = output
            }
            if event["is_error"] as? Bool == true, result == nil {
                errorMessage = (event["result"] as? String) ?? "Claude Code couldn't finish."
            }
        default:
            break
        }
    }

    private func handleCodex(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "thread.started":
            if let id = event["thread_id"] as? String { sessionID = id }
        case "item.started":
            let item = event["item"] as? [String: Any] ?? [:]
            if item["type"] as? String == "command_execution" {
                let described = Self.describe(command: item["command"] as? String ?? "")
                step(described.text, files: described.files)
            }
        case "item.completed":
            let item = event["item"] as? [String: Any] ?? [:]
            if item["type"] as? String == "agent_message", let text = item["text"] as? String,
               let data = text.data(using: .utf8), let output = Self.decodeOutput(data) {
                result = output
                step("Writing .hun.yml")
                onEvent(.reply(output.summary))
            } else if item["type"] as? String == "command_execution" {
                onEvent(.thinking)
            }
        case "turn.failed", "error":
            let error = event["error"] as? [String: Any]
            errorMessage = (error?["message"] as? String) ?? (event["message"] as? String) ?? "Codex couldn't finish."
        default:
            break
        }
    }

    private func handleClaudeStreamEvent(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "content_block_start":
            let block = event["content_block"] as? [String: Any] ?? [:]
            if block["type"] as? String == "thinking" {
                onEvent(.thinking)
            } else if block["type"] as? String == "tool_use", block["name"] as? String == "StructuredOutput" {
                outputBlockIndex = event["index"] as? Int
                outputJSON = ""
                step("Writing .hun.yml")
            }
        case "content_block_delta":
            guard let index = event["index"] as? Int, index == outputBlockIndex,
                  let delta = event["delta"] as? [String: Any],
                  let partial = delta["partial_json"] as? String
            else { return }
            outputJSON += partial
            if let reply = Self.partialStringValue(forKey: "summary", in: outputJSON), reply != lastReply {
                lastReply = reply
                onEvent(.reply(reply))
            }
        default:
            break
        }
    }

    /// The value of a string key in JSON that may still be arriving, decoded
    /// up to where it has got: `{"summary": "Postgres runs in Do` → "Postgres runs in Do".
    static func partialStringValue(forKey key: String, in json: String) -> String? {
        guard let keyRange = json.range(of: "\"\(key)\"") else { return nil }
        var index = keyRange.upperBound
        // Skip to the opening quote after the colon.
        while index < json.endIndex, json[index] != "\"" {
            if !(json[index] == ":" || json[index].isWhitespace) { return nil }
            index = json.index(after: index)
        }
        guard index < json.endIndex else { return nil }
        index = json.index(after: index)
        var value = ""
        while index < json.endIndex {
            let character = json[index]
            if character == "\"" { return value }
            if character == "\\" {
                let next = json.index(after: index)
                guard next < json.endIndex else { return value }
                switch json[next] {
                case "n": value.append("\n")
                case "t": value.append("\t")
                case "\"": value.append("\"")
                case "\\": value.append("\\")
                case "/": value.append("/")
                case "u":
                    let hexStart = json.index(after: next)
                    guard let hexEnd = json.index(hexStart, offsetBy: 4, limitedBy: json.endIndex),
                          let scalar = UInt32(json[hexStart..<hexEnd], radix: 16).flatMap(Unicode.Scalar.init)
                    else { return value }
                    value.unicodeScalars.append(scalar)
                    index = hexEnd
                    continue
                default: break
                }
                index = json.index(after: next)
                continue
            }
            value.append(character)
            index = json.index(after: index)
        }
        return value
    }

    private func step(_ text: String, files: [String] = []) {
        guard text != lastStep else { return }
        lastStep = text
        onEvent(.step(text, files: files))
    }

    // MARK: Describing what the agent is doing

    private static let notableFile = try! NSRegularExpression(
        pattern: #"(?:[\w.\-]+/)*(?:README[\w.\-]*|package\.json|pnpm-workspace\.yaml|turbo\.json|(?:docker-)?compose[\w.\-]*\.ya?ml|Dockerfile[\w.\-]*|Makefile|Procfile|pyproject\.toml|requirements[\w.\-]*\.txt|Cargo\.toml|go\.mod|Gemfile|mix\.exs|manage\.py|vite\.config\.\w+|next\.config\.\w+|AGENTS\.md|CLAUDE\.md|[\w.\-]+\.(?:py|ts|tsx|js|mjs|go|rb|toml|ya?ml|json|md))"#
    )

    /// "cat README.md apps/web/package.json" → "Reading README.md and apps/web/package.json".
    static func describe(command: String) -> (text: String, files: [String]) {
        let unwrapped = command
            .replacingOccurrences(of: #"^/bin/(?:zsh|bash|sh) -lc "#, with: "", options: .regularExpression)
        let range = NSRange(unwrapped.startIndex..., in: unwrapped)
        var files: [String] = []
        for match in notableFile.matches(in: unwrapped, range: range) {
            guard let swiftRange = Range(match.range, in: unwrapped) else { continue }
            let path = displayPath(String(unwrapped[swiftRange]))
            if !files.contains(path) { files.append(path) }
        }
        if !files.isEmpty {
            if files.count == 1 { return ("Reading \(files[0])", files) }
            if files.count == 2 { return ("Reading \(files[0]) and \(files[1])", files) }
            return ("Reading \(files[0]), \(files[1]) and \(files.count - 2) more", files)
        }
        let lower = unwrapped.lowercased()
        if lower.contains("rg ") || lower.contains("grep") { return ("Searching the project", []) }
        return ("Looking through the project", [])
    }

    /// Paths relative to the project, without a leading "./".
    static func displayPath(_ path: String) -> String {
        var display = path
        if let range = display.range(of: #"^.*/(?=(?:apps|packages|services|frontend|backend|web|api|src|docs)/)"#, options: .regularExpression) {
            display.removeSubrange(range)
        } else if display.hasPrefix("/") {
            display = (display as NSString).lastPathComponent
        }
        if display.hasPrefix("./") { display.removeFirst(2) }
        return display
    }
}

/// A byte buffer filled from a pipe's background handler.
nonisolated final class HunLockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

// MARK: - The conversation

/// A project's setup conversation with its agent: the first setup, then
/// every change asked for. Kept on disk, so it (and the agent's session)
/// carries on after Hun restarts.
nonisolated struct HunAgentChat: Codable, Equatable, Sendable {
    var agent: HunAgentKind
    var sessionID: String?
    var messages: [HunAgentMessage]

    var isWorking: Bool { messages.last?.status == .working }

    /// A new project's first setup, still running: it takes over the window.
    var isFirstSetupRunning: Bool {
        messages.count == 1 && messages[0].isSetup && isWorking
    }
}

nonisolated struct HunAgentMessage: Codable, Equatable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case agent
    }

    enum Status: Codable, Equatable, Sendable {
        case working
        case done
        case failed
    }

    let id: UUID
    let role: Role
    var text: String
    /// The agent's progress lines, oldest first.
    var steps: [String]
    /// Project files the agent read, in order.
    var files: [String]?
    /// Between steps, while the agent works out what to do next.
    var isThinking: Bool?
    var status: Status
    /// The first setup of the project, rather than a reply.
    var isSetup: Bool
    var change: HunAgentChange?
    let date: Date

    static func user(_ text: String) -> HunAgentMessage {
        HunAgentMessage(id: UUID(), role: .user, text: text, steps: [], files: nil, isThinking: nil, status: .done, isSetup: false, change: nil, date: Date())
    }

    static func agentWorking(isSetup: Bool) -> HunAgentMessage {
        HunAgentMessage(id: UUID(), role: .agent, text: "", steps: [], files: nil, isThinking: nil, status: .working, isSetup: isSetup, change: nil, date: Date())
    }
}

/// A message typed while the agent was busy.
nonisolated struct HunQueuedMessage: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
}

/// What a reply changed, service by service, and how to put it back.
nonisolated struct HunAgentChange: Codable, Equatable, Sendable {
    struct Line: Codable, Equatable, Sendable, Hashable {
        enum Kind: String, Codable, Sendable {
            case added
            case removed
            case changed
        }

        let kind: Kind
        let text: String
    }

    let lines: [Line]
    /// The .hun.yml before the change, for Undo.
    let previousConfig: String
    var undone: Bool
}

/// The parts of a project's setup worth showing in a change.
nonisolated struct HunSetupOutline: Equatable, Sendable {
    struct Service: Equatable, Sendable {
        let command: String
        let port: Int
    }

    var services: [String: Service]
    var profiles: [String: [String]]

    /// Plain lines: "+ worker", "website  port 3000 → 3100", "+ profile site".
    static func changes(from old: HunSetupOutline, to new: HunSetupOutline) -> [HunAgentChange.Line] {
        var lines: [HunAgentChange.Line] = []
        for name in new.services.keys.sorted() where old.services[name] == nil {
            let port = new.services[name]!.port
            lines.append(.init(kind: .added, text: port > 0 ? "\(name)  :\(port)" : name))
        }
        for name in old.services.keys.sorted() where new.services[name] == nil {
            lines.append(.init(kind: .removed, text: name))
        }
        for name in new.services.keys.sorted() {
            guard let before = old.services[name], let after = new.services[name] else { continue }
            if before.port != after.port {
                let from = before.port > 0 ? ":\(before.port)" : "no port"
                let to = after.port > 0 ? ":\(after.port)" : "no port"
                lines.append(.init(kind: .changed, text: "\(name)  \(from) → \(to)"))
            }
            if before.command != after.command {
                lines.append(.init(kind: .changed, text: "\(name)  \(after.command)"))
            }
        }
        for name in new.profiles.keys.sorted() {
            if let before = old.profiles[name] {
                if before != new.profiles[name] {
                    lines.append(.init(kind: .changed, text: "profile \(name): \(new.profiles[name]!.joined(separator: ", "))"))
                }
            } else {
                lines.append(.init(kind: .added, text: "profile \(name)"))
            }
        }
        for name in old.profiles.keys.sorted() where new.profiles[name] == nil {
            lines.append(.init(kind: .removed, text: "profile \(name)"))
        }
        return lines
    }
}

/// Conversations on disk, one file per project folder.
nonisolated enum HunAgentChatArchive {
    private static var directory: URL {
        HunPaths.homeURL.appendingPathComponent("agent-chats", isDirectory: true)
    }

    private static func fileURL(for path: String) -> URL {
        // A stable, filename-safe name for the folder path.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
            .replacingOccurrences(of: #"[^A-Za-z0-9_-]"#, with: "-", options: .regularExpression)
        return directory.appendingPathComponent("\(name)-\(String(hash, radix: 16)).json")
    }

    static func load(for path: String) -> HunAgentChat? {
        guard let data = try? Data(contentsOf: fileURL(for: path)) else { return nil }
        return try? JSONDecoder().decode(HunAgentChat.self, from: data)
    }

    static func remove(for path: String) {
        try? FileManager.default.removeItem(at: fileURL(for: path))
    }

    static func save(_ chat: HunAgentChat, for path: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(chat).write(to: fileURL(for: path), options: .atomic)
        } catch {
            HunTrace.addProject("agent chat save failed path=\(path) error=\(HunTrace.compact(error.localizedDescription))")
        }
    }
}
