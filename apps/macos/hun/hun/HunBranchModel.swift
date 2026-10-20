import Foundation
import Observation

nonisolated enum HunGitSyncState: Equatable, Sendable {
    case upToDate(upstream: String)
    case ahead(count: Int, upstream: String)
    case behind(count: Int, upstream: String)
    case diverged(ahead: Int, behind: Int, upstream: String)
    case unpublished(branch: String)
    case detached
}

nonisolated enum HunGitRemoteCheckAge: Equatable, Sendable {
    case never
    case justNow
    case minutes(Int)
    case hours(Int)
    case days(Int)

    init(checkedAt: Date?, relativeTo now: Date) {
        guard let checkedAt else {
            self = .never
            return
        }

        let elapsed = max(0, now.timeIntervalSince(checkedAt))
        if elapsed < 60 {
            self = .justNow
        } else if elapsed < 3_600 {
            self = .minutes(max(1, Int(elapsed / 60)))
        } else if elapsed < 86_400 {
            self = .hours(max(1, Int(elapsed / 3_600)))
        } else {
            self = .days(max(1, Int(elapsed / 86_400)))
        }
    }
}

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

    var conflictedFiles: [HunGitFileChange] {
        files.filter(\.conflicted)
    }

    var syncState: HunGitSyncState {
        if detached {
            return .detached
        }
        if upstream.isEmpty {
            return .unpublished(branch: branch)
        }
        if ahead > 0, behind > 0 {
            return .diverged(ahead: ahead, behind: behind, upstream: upstream)
        }
        if ahead > 0 {
            return .ahead(count: ahead, upstream: upstream)
        }
        if behind > 0 {
            return .behind(count: behind, upstream: upstream)
        }
        return .upToDate(upstream: upstream)
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

/// Backs the branch switcher: loads git state only while the switcher is
/// open, so an idle project costs nothing.
@MainActor
@Observable
final class HunBranchModel {
    enum Operation: String {
        case refreshing
        case loadingBranches
        case switchingBranch
        case creatingBranch
        case fetching
    }

    var status: HunGitStatus?
    var branches: [HunGitBranch] = []
    var branchSearch = ""
    var errorMessage: String?
    var pendingBranchSwitch: String?
    var isBranchPickerPresented = false
    private(set) var lastRemoteCheckAt: Date?
    private(set) var operation: Operation?

    private let client: HunGitClientProtocol
    private var activeProjectID: String?
    private var statusGeneration = 0

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

    /// Points the switcher at a project without touching git.
    func select(projectID: String) {
        guard activeProjectID != projectID else { return }
        statusGeneration += 1
        activeProjectID = projectID
        status = nil
        branches = []
        branchSearch = ""
        pendingBranchSwitch = nil
        errorMessage = nil
        isBranchPickerPresented = false
        lastRemoteCheckAt = nil
        if operation == .refreshing {
            operation = nil
        }
    }

    /// Loads what the switcher shows: working-tree status and branches.
    func loadForPicker() async {
        await refresh()
        await loadBranches()
    }

    func refresh(silently: Bool = false) async {
        guard let projectID = activeProjectID, operation == nil else { return }
        statusGeneration += 1
        let generation = statusGeneration
        if !silently {
            operation = .refreshing
        }
        defer {
            if operation == .refreshing {
                operation = nil
            }
        }
        do {
            let newStatus = try await client.gitStatus(project: projectID)
            guard activeProjectID == projectID, generation == statusGeneration else { return }
            status = newStatus
            if !newStatus.isRepository {
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
        if !stash, let blocker = branchSwitchBlocker {
            pendingBranchSwitch = nil
            errorMessage = blocker
            return false
        }
        if !stash, status?.clean == false {
            pendingBranchSwitch = branch
            errorMessage = nil
            return false
        }
        let succeeded = await applyStatusOperation(.switchingBranch) {
            try await client.gitSwitchBranch(project: projectID, branch: branch, stash: stash)
        }
        if succeeded {
            pendingBranchSwitch = nil
            branchSearch = ""
            await loadBranches()
        } else {
            await refresh(silently: true)
            if let blocker = branchSwitchBlocker {
                pendingBranchSwitch = nil
                errorMessage = blocker
            } else if !stash, status?.clean == false {
                pendingBranchSwitch = branch
                errorMessage = nil
            }
        }
        return succeeded
    }

    func stashAndSwitchPendingBranch() async -> Bool {
        guard let branch = pendingBranchSwitch else { return false }
        return await switchBranch(branch, stash: true)
    }

    func cancelPendingBranchSwitch() {
        pendingBranchSwitch = nil
        errorMessage = nil
    }

    func cancelBranchPicker() {
        cancelPendingBranchSwitch()
        isBranchPickerPresented = false
    }

    private var branchSwitchBlocker: String? {
        guard let status else { return nil }
        if !status.conflictedFiles.isEmpty {
            return "Resolve the current conflicts before switching branches."
        }
        if let operation = status.operation, !operation.isEmpty {
            return "Finish or abort the current \(operation) before switching branches."
        }
        return nil
    }

    @discardableResult
    func fetch() async -> Bool {
        guard let projectID = activeProjectID else { return false }
        let succeeded = await applyStatusOperation(.fetching) {
            try await client.gitFetch(project: projectID)
        }
        if succeeded {
            lastRemoteCheckAt = Date()
            await loadBranches()
        }
        return succeeded
    }

    @discardableResult
    private func applyStatusOperation(
        _ newOperation: Operation,
        action: () async throws -> HunGitStatus
    ) async -> Bool {
        guard operation == nil else { return false }
        statusGeneration += 1
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
