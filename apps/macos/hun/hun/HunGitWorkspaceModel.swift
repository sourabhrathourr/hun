import Foundation
import Observation

nonisolated struct HunGitStatus: Decodable, Equatable, Sendable {
    let isRepository: Bool
    let branch: String
    let head: String
    let upstream: String
    let ahead: Int
    let behind: Int
    let detached: Bool
    let clean: Bool
    let operation: String?
    var files: [HunGitFileChange]

    enum CodingKeys: String, CodingKey {
        case isRepository = "is_repository"
        case branch
        case head
        case upstream
        case ahead
        case behind
        case detached
        case clean
        case operation
        case files
    }

    init(
        isRepository: Bool,
        branch: String,
        head: String,
        upstream: String,
        ahead: Int,
        behind: Int,
        detached: Bool,
        clean: Bool,
        operation: String?,
        files: [HunGitFileChange]
    ) {
        self.isRepository = isRepository
        self.branch = branch
        self.head = head
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.detached = detached
        self.clean = clean
        self.operation = operation
        self.files = files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isRepository = try container.decode(Bool.self, forKey: .isRepository)
        branch = try container.decodeIfPresent(String.self, forKey: .branch) ?? ""
        head = try container.decodeIfPresent(String.self, forKey: .head) ?? ""
        upstream = try container.decodeIfPresent(String.self, forKey: .upstream) ?? ""
        ahead = try container.decodeIfPresent(Int.self, forKey: .ahead) ?? 0
        behind = try container.decodeIfPresent(Int.self, forKey: .behind) ?? 0
        detached = try container.decodeIfPresent(Bool.self, forKey: .detached) ?? false
        clean = try container.decodeIfPresent(Bool.self, forKey: .clean) ?? true
        operation = try container.decodeIfPresent(String.self, forKey: .operation)
        files = try container.decodeIfPresent([HunGitFileChange].self, forKey: .files) ?? []
    }

    var changeCount: Int {
        files.count
    }

    var stagedFiles: [HunGitFileChange] {
        files.filter { $0.staged && !$0.conflicted }
    }

    var unstagedFiles: [HunGitFileChange] {
        files.filter { $0.unstaged && !$0.conflicted }
    }

    var conflictedFiles: [HunGitFileChange] {
        files.filter(\.conflicted)
    }
}

nonisolated enum HunGitFileStatus: Equatable, Sendable {
    case unchanged
    case untracked
    case ignored
    case added
    case modified
    case deleted
    case renamed
    case copied
    case typeChanged
    case unmerged
    case unknown(String)

    init(code: String) {
        switch code {
        case ".", " ": self = .unchanged
        case "?": self = .untracked
        case "!": self = .ignored
        case "A": self = .added
        case "M": self = .modified
        case "D": self = .deleted
        case "R": self = .renamed
        case "C": self = .copied
        case "T": self = .typeChanged
        case "U": self = .unmerged
        default: self = .unknown(code)
        }
    }

    var displayLetter: String {
        switch self {
        case .unchanged: "M"
        case .untracked: "?"
        case .ignored: "!"
        case .added: "A"
        case .modified: "M"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .typeChanged: "T"
        case .unmerged: "U"
        case let .unknown(code): code
        }
    }
}

nonisolated struct HunGitFileChange: Decodable, Hashable, Sendable {
    let path: String
    let originalPath: String?
    let indexStatus: String
    let worktreeStatus: String
    let untracked: Bool
    let conflicted: Bool

    enum CodingKeys: String, CodingKey {
        case path
        case originalPath = "original_path"
        case indexStatus = "index_status"
        case worktreeStatus = "worktree_status"
        case untracked
        case conflicted
    }

    var indexState: HunGitFileStatus {
        HunGitFileStatus(code: indexStatus)
    }

    var worktreeState: HunGitFileStatus {
        HunGitFileStatus(code: worktreeStatus)
    }

    var staged: Bool {
        conflicted || (!untracked && indexState != .unchanged)
    }

    var unstaged: Bool {
        conflicted || untracked || worktreeState != .unchanged
    }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var parentPath: String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }
}

nonisolated struct HunGitBranch: Decodable, Hashable, Identifiable, Sendable {
    let name: String
    let current: Bool
    let remote: Bool
    let upstream: String?
    let updatedAt: Int64

    var id: String {
        (remote ? "remote:" : "local:") + name
    }

    enum CodingKeys: String, CodingKey {
        case name
        case current
        case remote
        case upstream
        case updatedAt = "updated_at"
    }
}

nonisolated struct HunGitDiff: Decodable, Equatable, Sendable {
    let path: String
    let staged: Bool
    let content: String
    let binary: Bool
    let truncated: Bool
}

@MainActor
@Observable
final class HunGitWorkspaceModel {
    enum Operation: String {
        case refreshing
        case loadingBranches
        case loadingDiff
        case staging
        case unstaging
        case committing
        case switchingBranch
        case creatingBranch
        case fetching
        case pulling
        case pushing
    }

    var status: HunGitStatus?
    var branches: [HunGitBranch] = []
    var selectedDiff: HunGitDiff?
    var selectedPath: String?
    var selectedStaged = false
    var commitMessage = ""
    var branchSearch = ""
    var errorMessage: String?
    var pendingBranchSwitch: String?
    var isWorkspacePresented = false
    var isBranchPickerPresented = false
    private(set) var operation: Operation?

    private let client: HunGitClientProtocol
    private var activeProjectID: String?
    private var diffGeneration = 0
    private var statusGeneration = 0
    private var silentRefreshInFlight = false

    init(client: HunGitClientProtocol = HunDaemonClient()) {
        self.client = client
    }

    var isBusy: Bool {
        operation != nil
    }

    var filteredBranches: [HunGitBranch] {
        let query = branchSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return branches }
        return branches.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var canCreateSearchedBranch: Bool {
        let query = branchSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        return !branches.contains { $0.name.caseInsensitiveCompare(query) == .orderedSame }
    }

    func load(projectID: String) async {
        if activeProjectID != projectID {
            statusGeneration += 1
            silentRefreshInFlight = false
            activeProjectID = projectID
            status = nil
            branches = []
            selectedDiff = nil
            selectedPath = nil
            selectedStaged = false
            branchSearch = ""
            pendingBranchSwitch = nil
            errorMessage = nil
        }
        await refresh()
    }

    func monitor(projectID: String) async {
        await load(projectID: projectID)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, activeProjectID == projectID else { return }
            await refresh(silently: true)
        }
    }

    func refresh(silently: Bool = false) async {
        guard let projectID = activeProjectID else { return }
        if operation != nil {
            return
        }
        if silently {
            guard !silentRefreshInFlight else { return }
            silentRefreshInFlight = true
        }
        statusGeneration += 1
        let generation = statusGeneration
        if !silently {
            operation = .refreshing
        }
        defer {
            if silently, generation == statusGeneration {
                silentRefreshInFlight = false
            }
            if operation == .refreshing {
                operation = nil
            }
        }
        do {
            let newStatus = try await client.gitStatus(project: projectID)
            guard activeProjectID == projectID, generation == statusGeneration else { return }
            status = newStatus
            if !newStatus.isRepository {
                isWorkspacePresented = false
                isBranchPickerPresented = false
            }
            if !silently {
                errorMessage = nil
            }
        } catch {
            guard !silently else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadBranches() async {
        guard let projectID = activeProjectID, operation == nil else { return }
        operation = .loadingBranches
        defer { operation = nil }
        do {
            branches = try await client.gitBranches(project: projectID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadDiff(for change: HunGitFileChange, staged: Bool) async {
        guard let projectID = activeProjectID else { return }
        selectedPath = change.path
        selectedStaged = staged
        diffGeneration += 1
        let generation = diffGeneration
        operation = .loadingDiff
        do {
            let diff = try await client.gitDiff(project: projectID, path: change.path, staged: staged)
            guard generation == diffGeneration,
                  selectedPath == change.path,
                  selectedStaged == staged
            else {
                return
            }
            selectedDiff = diff
            errorMessage = nil
        } catch {
            guard generation == diffGeneration else { return }
            selectedDiff = nil
            errorMessage = error.localizedDescription
        }
        if generation == diffGeneration, operation == .loadingDiff {
            operation = nil
        }
    }

    func stage(_ change: HunGitFileChange) async {
        guard let projectID = activeProjectID else { return }
        let succeeded = await applyStatusOperation(.staging) {
            try await client.gitStage(project: projectID, path: change.path)
        }
        if succeeded,
           status?.files.contains(where: { $0.path == change.path && $0.staged }) == true,
           let updated = status?.files.first(where: { $0.path == change.path }) {
            await loadDiff(for: updated, staged: true)
        }
    }

    func unstage(_ change: HunGitFileChange) async {
        guard let projectID = activeProjectID else { return }
        let succeeded = await applyStatusOperation(.unstaging) {
            try await client.gitUnstage(project: projectID, path: change.path)
        }
        if succeeded,
           status?.files.contains(where: { $0.path == change.path && $0.unstaged }) == true,
           let updated = status?.files.first(where: { $0.path == change.path }) {
            await loadDiff(for: updated, staged: false)
        }
    }

    func commit() async -> Bool {
        guard let projectID = activeProjectID else { return false }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            errorMessage = "Write a commit message first."
            return false
        }
        let succeeded = await applyStatusOperation(.committing) {
            try await client.gitCommit(project: projectID, message: message)
        }
        if succeeded {
            commitMessage = ""
            selectedDiff = nil
            selectedPath = nil
        }
        return succeeded
    }

    func createBranch(_ branch: String) async -> Bool {
        guard let projectID = activeProjectID else { return false }
        let name = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let succeeded = await applyStatusOperation(.creatingBranch) {
            try await client.gitCreateBranch(project: projectID, branch: name)
        }
        if succeeded {
            branchSearch = ""
            await loadBranches()
        }
        return succeeded
    }

    func switchBranch(_ branch: String, stash: Bool = false) async -> Bool {
        guard let projectID = activeProjectID else { return false }
        let succeeded = await applyStatusOperation(.switchingBranch) {
            try await client.gitSwitchBranch(project: projectID, branch: branch, stash: stash)
        }
        if succeeded {
            pendingBranchSwitch = nil
            branchSearch = ""
            selectedDiff = nil
            selectedPath = nil
            await loadBranches()
        } else if !stash, status?.clean == false {
            pendingBranchSwitch = branch
        }
        return succeeded
    }

    func stashAndSwitchPendingBranch() async -> Bool {
        guard let branch = pendingBranchSwitch else { return false }
        return await switchBranch(branch, stash: true)
    }

    func fetch() async {
        guard let projectID = activeProjectID else { return }
        let succeeded = await applyStatusOperation(.fetching) {
            try await client.gitFetch(project: projectID)
        }
        if succeeded {
            await loadBranches()
        }
    }

    func pull() async {
        guard let projectID = activeProjectID else { return }
        await applyStatusOperation(.pulling) {
            try await client.gitPull(project: projectID)
        }
    }

    func push() async {
        guard let projectID = activeProjectID else { return }
        await applyStatusOperation(.pushing) {
            try await client.gitPush(project: projectID)
        }
    }

    func dismissError() {
        errorMessage = nil
        pendingBranchSwitch = nil
    }

    @discardableResult
    private func applyStatusOperation(
        _ newOperation: Operation,
        action: () async throws -> HunGitStatus
    ) async -> Bool {
        guard operation == nil else { return false }
        statusGeneration += 1
        silentRefreshInFlight = false
        operation = newOperation
        defer { operation = nil }
        do {
            status = try await action()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
