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

    var stagedFiles: [HunGitFileChange] {
        files.filter { $0.staged && !$0.conflicted }
    }

    var unstagedFiles: [HunGitFileChange] {
        files.filter { $0.unstaged && !$0.conflicted }
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

nonisolated struct HunGitUpdateResult: Decodable, Equatable, Sendable {
    let status: HunGitStatus
    let updatedCommits: Int
    let protectedChanges: Bool
    let restoredChanges: Bool
    let recoveryRequired: Bool
    let recoveryMessage: String?

    enum CodingKeys: String, CodingKey {
        case status
        case updatedCommits = "updated_commits"
        case protectedChanges = "protected_changes"
        case restoredChanges = "restored_changes"
        case recoveryRequired = "recovery_required"
        case recoveryMessage = "recovery_message"
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
        case .untracked: "U"
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

nonisolated struct HunGitChangeRowIdentity: Hashable, Sendable {
    let path: String
    let staged: Bool
}

nonisolated struct HunGitChangeRowItem: Identifiable, Sendable {
    let change: HunGitFileChange
    let staged: Bool

    var id: HunGitChangeRowIdentity {
        HunGitChangeRowIdentity(path: change.path, staged: staged)
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

nonisolated struct HunGitDiffMetadata: Equatable, Sendable {
    let path: String
    let staged: Bool
    let binary: Bool
    let truncated: Bool

    init(_ diff: HunGitDiff) {
        path = diff.path
        staged = diff.staged
        binary = diff.binary
        truncated = diff.truncated
    }
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
        case updatingBranch
        case pushing
    }

    var status: HunGitStatus?
    var branches: [HunGitBranch] = []
    var selectedDiffMetadata: HunGitDiffMetadata?
    var selectedDiffDocument: HunGitDiffDocument?
    var selectedPath: String?
    var selectedStaged = false
    var commitMessage = ""
    var branchSearch = ""
    var errorMessage: String?
    var pendingBranchSwitch: String?
    var isWorkspacePresented = false
    var isBranchPickerPresented = false
    var isUpdateBranchPresented = false
    private(set) var isCommitAndPushInFlight = false
    private(set) var isGeneratingCommitMessage = false
    private(set) var commitMessageGenerationNotice: String?
    private(set) var lastRemoteCheckAt: Date?
    private(set) var lastUpdateResult: HunGitUpdateResult?
    private(set) var updateBranchPreflightStatus: HunGitStatus?
    private(set) var operation: Operation?

    private let client: HunGitClientProtocol
    private let commitMessageGenerator: any HunCommitMessageGenerating
    private var activeProjectID: String?
    private var commitMessageGeneration = 0
    private var diffGeneration = 0
    private var diffParsingTask: Task<HunGitDiffDocument, Never>?
    private var statusGeneration = 0
    private var silentRefreshInFlight = false

    init(
        client: HunGitClientProtocol = HunDaemonClient(),
        commitMessageGenerator: any HunCommitMessageGenerating =
            HunCommitMessageGeneratorFactory.makeDefault()
    ) {
        self.client = client
        self.commitMessageGenerator = commitMessageGenerator
    }

    var isBusy: Bool {
        operation != nil
    }

    var commitMessageGenerationAvailability: HunCommitMessageGenerationAvailability {
        commitMessageGenerator.availability
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
            diffGeneration += 1
            commitMessageGeneration += 1
            diffParsingTask?.cancel()
            diffParsingTask = nil
            silentRefreshInFlight = false
            if operation == .loadingDiff || operation == .updatingBranch {
                operation = nil
            }
            activeProjectID = projectID
            status = nil
            branches = []
            selectedDiffMetadata = nil
            selectedDiffDocument = nil
            selectedPath = nil
            selectedStaged = false
            branchSearch = ""
            pendingBranchSwitch = nil
            errorMessage = nil
            isBranchPickerPresented = false
            isUpdateBranchPresented = false
            isCommitAndPushInFlight = false
            isGeneratingCommitMessage = false
            commitMessageGenerationNotice = nil
            lastRemoteCheckAt = nil
            lastUpdateResult = nil
            updateBranchPreflightStatus = nil
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

    func presentWorkspace() async {
        isWorkspacePresented = true

        guard selectedPath == nil else { return }
        if let change = status?.unstagedFiles.first ?? status?.conflictedFiles.first {
            await loadDiff(for: change, staged: false)
        } else if let change = status?.stagedFiles.first {
            await loadDiff(for: change, staged: true)
        }
    }

    func loadDiff(for change: HunGitFileChange, staged: Bool) async {
        guard let projectID = activeProjectID else { return }
        selectedPath = change.path
        selectedStaged = staged
        selectedDiffMetadata = nil
        selectedDiffDocument = nil
        diffParsingTask?.cancel()
        diffGeneration += 1
        let generation = diffGeneration
        operation = .loadingDiff
        defer {
            if generation == diffGeneration {
                diffParsingTask = nil
                if operation == .loadingDiff {
                    operation = nil
                }
            }
        }
        do {
            let diff = try await client.gitDiff(project: projectID, path: change.path, staged: staged)
            guard generation == diffGeneration,
                  activeProjectID == projectID,
                  selectedPath == change.path,
                  selectedStaged == staged
            else {
                return
            }
            let parsingTask = Task.detached(priority: .userInitiated) {
                HunGitDiffDocument(
                    patch: diff.content,
                    syntaxPath: diff.path,
                    shouldCancel: { Task.isCancelled }
                )
            }
            diffParsingTask = parsingTask
            let document = await parsingTask.value
            guard generation == diffGeneration,
                  activeProjectID == projectID,
                  selectedPath == change.path,
                  selectedStaged == staged
            else {
                return
            }
            selectedDiffMetadata = HunGitDiffMetadata(diff)
            selectedDiffDocument = document
            errorMessage = nil
        } catch {
            guard generation == diffGeneration else { return }
            selectedDiffMetadata = nil
            selectedDiffDocument = nil
            errorMessage = error.localizedDescription
        }
    }

    func stage(_ change: HunGitFileChange) async {
        guard let projectID = activeProjectID else { return }
        let succeeded = await applyStatusOperation(.staging) {
            try await client.gitStage(project: projectID, path: change.path)
        }
        if succeeded {
            commitMessageGenerationNotice = nil
        }
        if succeeded,
           status?.files.contains(where: { $0.path == change.path && $0.staged }) == true,
           let updated = status?.files.first(where: { $0.path == change.path }) {
            await loadDiff(for: updated, staged: true)
        }
    }

    func stageAll() async {
        guard let projectID = activeProjectID,
              status?.unstagedFiles.isEmpty == false,
              status?.conflictedFiles.isEmpty == true
        else {
            return
        }
        let selectedPathBeforeStaging = selectedPath
        let succeeded = await applyStatusOperation(.staging) {
            try await client.gitStageAll(project: projectID)
        }
        if succeeded {
            commitMessageGenerationNotice = nil
        }
        if succeeded,
           let selectedPathBeforeStaging,
           let updated = status?.files.first(where: {
               $0.path == selectedPathBeforeStaging && $0.staged
           }) {
            await loadDiff(for: updated, staged: true)
        }
    }

    func unstage(_ change: HunGitFileChange) async {
        guard let projectID = activeProjectID else { return }
        let succeeded = await applyStatusOperation(.unstaging) {
            try await client.gitUnstage(project: projectID, path: change.path)
        }
        if succeeded {
            commitMessageGenerationNotice = nil
        }
        if succeeded,
           status?.files.contains(where: { $0.path == change.path && $0.unstaged }) == true,
           let updated = status?.files.first(where: { $0.path == change.path }) {
            await loadDiff(for: updated, staged: false)
        }
    }

    func generateCommitMessage() async {
        guard !isGeneratingCommitMessage else { return }
        guard case .available = commitMessageGenerator.availability else {
            commitMessageGenerationNotice =
                commitMessageGenerator.availability.unavailableReason ??
                "Apple Intelligence is unavailable."
            return
        }
        guard let projectID = activeProjectID,
              let stagedChanges = status?.stagedFiles,
              !stagedChanges.isEmpty
        else {
            commitMessageGenerationNotice = "Stage changes before generating a commit message."
            return
        }

        commitMessageGeneration += 1
        let generation = commitMessageGeneration
        isGeneratingCommitMessage = true
        commitMessageGenerationNotice = nil
        defer {
            if generation == commitMessageGeneration {
                isGeneratingCommitMessage = false
            }
        }

        do {
            var diffs: [HunGitDiff] = []
            var collectedCharacters = 0
            let diffBudget = 10_000

            for change in stagedChanges.prefix(12) where collectedCharacters < diffBudget {
                let diff = try await client.gitDiff(
                    project: projectID,
                    path: change.path,
                    staged: true
                )
                let remaining = max(0, diffBudget - collectedCharacters)
                let excerpt = String(diff.content.prefix(remaining))
                diffs.append(
                    HunGitDiff(
                        path: diff.path,
                        staged: true,
                        content: excerpt,
                        binary: diff.binary,
                        truncated: diff.truncated || excerpt.count < diff.content.count
                    )
                )
                collectedCharacters += excerpt.count
            }

            let context = HunCommitMessageContext.build(
                stagedChanges: stagedChanges,
                diffs: diffs
            )
            let message = try await commitMessageGenerator.generate(from: context)
            guard generation == commitMessageGeneration,
                  activeProjectID == projectID,
                  status?.stagedFiles == stagedChanges
            else {
                return
            }
            commitMessage = message
            commitMessageGenerationNotice = "Generated on this Mac. Review before committing."
        } catch {
            guard generation == commitMessageGeneration,
                  activeProjectID == projectID
            else {
                return
            }
            commitMessageGenerationNotice = error.localizedDescription
        }
    }

    func commit() async -> Bool {
        await performCommit(continuePendingBranchSwitch: true)
    }

    private func performCommit(continuePendingBranchSwitch: Bool) async -> Bool {
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
            commitMessageGenerationNotice = nil
            selectedDiffMetadata = nil
            selectedDiffDocument = nil
            selectedPath = nil
            if continuePendingBranchSwitch {
                await continuePendingBranchSwitchIfReady()
            }
        }
        return succeeded
    }

    func commitAndPush() async -> Bool {
        guard !isCommitAndPushInFlight else { return false }
        isCommitAndPushInFlight = true
        defer { isCommitAndPushInFlight = false }
        guard await performCommit(continuePendingBranchSwitch: false) else { return false }
        guard await push() else { return false }
        await continuePendingBranchSwitchIfReady()
        return true
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
            selectedDiffMetadata = nil
            selectedDiffDocument = nil
            selectedPath = nil
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

    func reviewChangesForPendingBranchSwitch() async {
        guard pendingBranchSwitch != nil else { return }
        errorMessage = nil
        isBranchPickerPresented = false
        await presentWorkspace()
    }

    func cancelPendingBranchSwitch() {
        pendingBranchSwitch = nil
        errorMessage = nil
    }

    func cancelBranchPicker() {
        cancelPendingBranchSwitch()
        isBranchPickerPresented = false
    }

    private func continuePendingBranchSwitchIfReady() async {
        guard status?.clean == true, let branch = pendingBranchSwitch else { return }
        _ = await switchBranch(branch)
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
    func pull() async -> Bool {
        guard let projectID = activeProjectID else { return false }
        let succeeded = await applyStatusOperation(.pulling) {
            try await client.gitPull(project: projectID)
        }
        if succeeded {
            lastRemoteCheckAt = Date()
        }
        return succeeded
    }

    func presentUpdateBranch() {
        lastUpdateResult = nil
        errorMessage = nil
        updateBranchPreflightStatus = status
        isUpdateBranchPresented = true
    }

    func dismissUpdateBranch() {
        guard operation != .updatingBranch else { return }
        isUpdateBranchPresented = false
        lastUpdateResult = nil
        updateBranchPreflightStatus = nil
    }

    @discardableResult
    func updateBranch(protectLocalChanges: Bool) async -> Bool {
        guard let projectID = activeProjectID, operation == nil else { return false }
        statusGeneration += 1
        let generation = statusGeneration
        silentRefreshInFlight = false
        operation = .updatingBranch
        defer {
            if generation == statusGeneration, operation == .updatingBranch {
                operation = nil
            }
        }

        do {
            let result = try await client.gitUpdateBranch(
                project: projectID,
                protectLocalChanges: protectLocalChanges
            )
            guard activeProjectID == projectID, generation == statusGeneration else {
                return false
            }
            status = result.status
            lastUpdateResult = result
            lastRemoteCheckAt = Date()
            errorMessage = nil
            if !result.recoveryRequired {
                isUpdateBranchPresented = false
                updateBranchPreflightStatus = nil
            }
            return true
        } catch {
            guard activeProjectID == projectID, generation == statusGeneration else {
                return false
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func push() async -> Bool {
        guard let projectID = activeProjectID else { return false }
        let succeeded = await applyStatusOperation(.pushing) {
            try await client.gitPush(project: projectID)
        }
        if succeeded {
            lastRemoteCheckAt = Date()
        }
        return succeeded
    }

    func dismissError() {
        errorMessage = nil
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
