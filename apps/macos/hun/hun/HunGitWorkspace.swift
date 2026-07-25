import AppKit
import SwiftUI

@MainActor
private extension HunGitSyncState {
    var headline: String {
        switch self {
        case let .upToDate(upstream):
            "Up to date with \(upstream)"
        case let .ahead(count, _):
            "\(count) \(count == 1 ? "commit" : "commits") ready to push"
        case let .behind(count, _):
            "\(count) remote \(count == 1 ? "commit" : "commits") ready to update"
        case let .diverged(ahead, behind, _):
            "Diverged · \(ahead) local, \(behind) remote"
        case let .unpublished(branch):
            "\(branch) has not been published"
        case .detached:
            "Detached HEAD"
        }
    }

    var icon: String {
        switch self {
        case .upToDate:
            "checkmark"
        case .ahead:
            "arrow.up"
        case .behind:
            "arrow.down"
        case .diverged:
            "arrow.triangle.branch"
        case .unpublished:
            "icloud.and.arrow.up"
        case .detached:
            "link.badge.plus"
        }
    }

    var tone: Color {
        switch self {
        case .upToDate:
            AppTheme.success
        case .ahead, .behind, .unpublished:
            AppTheme.warning
        case .diverged, .detached:
            AppTheme.danger
        }
    }

    var guidance: String? {
        switch self {
        case .diverged:
            "Local and remote both changed · rebase or merge before pushing"
        case .detached:
            "Check out a branch before pulling or pushing"
        case .upToDate, .ahead, .behind, .unpublished:
            nil
        }
    }

    func headline(remoteCheckAge: HunGitRemoteCheckAge) -> String {
        if case let .upToDate(upstream) = self, remoteCheckAge == .never {
            return "Fetch to confirm with \(upstream)"
        }
        return headline
    }

    func icon(remoteCheckAge: HunGitRemoteCheckAge) -> String {
        isUnverified(remoteCheckAge) ? "arrow.clockwise" : icon
    }

    func tone(remoteCheckAge: HunGitRemoteCheckAge) -> Color {
        isUnverified(remoteCheckAge) ? AppTheme.textSecondary : tone
    }

    private func isUnverified(_ remoteCheckAge: HunGitRemoteCheckAge) -> Bool {
        guard case .upToDate = self else { return false }
        return switch remoteCheckAge {
        case .never, .hours, .days:
            true
        case .justNow, .minutes:
            false
        }
    }
}

@MainActor
private extension HunGitRemoteCheckAge {
    var detail: String {
        switch self {
        case .never:
            "Fetch checks the remote without changing your files"
        case .justNow:
            "Remote checked just now"
        case let .minutes(count):
            "Remote checked \(count)m ago"
        case let .hours(count):
            "Remote checked \(count)h ago · fetch to refresh"
        case let .days(count):
            "Remote checked \(count)d ago · fetch to refresh"
        }
    }
}

nonisolated struct HunRepositoryStatusCapsuleContent: Equatable, Sendable {
    let branchName: String
    let localDetail: String?

    init(projectBranch: String?, status: HunGitStatus?) {
        if status?.detached == true {
            branchName = "detached"
        } else if let branch = status?.branch, !branch.isEmpty {
            branchName = branch
        } else {
            branchName = projectBranch ?? "Repository"
        }

        let conflicts = status?.conflictedFiles.count ?? 0
        let changes = status?.changeCount ?? 0
        if conflicts > 0 {
            localDetail = "\(conflicts) \(conflicts == 1 ? "conflict" : "conflicts")"
        } else if changes > 0 {
            localDetail = "\(changes) \(changes == 1 ? "change" : "changes")"
        } else {
            localDetail = nil
        }
    }
}

struct HunRepositoryStatusCapsule: View {
    let project: HunProject
    @Bindable var model: HunGitWorkspaceModel
    @State private var hovering = false

    private var status: HunGitStatus? {
        model.status?.isRepository == true ? model.status : nil
    }

    private var content: HunRepositoryStatusCapsuleContent {
        HunRepositoryStatusCapsuleContent(projectBranch: project.branch, status: status)
    }

    var body: some View {
        Button {
            model.isBranchPickerPresented = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9.5, weight: .semibold))

                Text(content.branchName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let detail = content.localDetail {
                    Text("· \(detail)")
                        .monospacedDigit()
                } else if status == nil, model.operation == .refreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.55)
                        .frame(width: 9, height: 9)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .opacity(0.65)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? AppTheme.hover : AppTheme.chipFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        hovering ? AppTheme.textTertiary.opacity(0.32) : AppTheme.divider,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open branch switcher")
    }
}

struct HunGitBranchDialogOverlay: View {
    @Bindable var model: HunGitWorkspaceModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.cancelBranchPicker()
                }

            HunGitBranchDialog(model: model)
                .padding(28)
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }
}

struct HunGitUpdateBranchDialogOverlay: View {
    @Bindable var model: HunGitWorkspaceModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.dismissUpdateBranch()
                }

            if let status = model.updateBranchPreflightStatus ?? model.status {
                HunGitUpdateBranchDialog(model: model, status: status)
                    .padding(28)
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }
}

private struct HunGitUpdateBranchDialog: View {
    @Bindable var model: HunGitWorkspaceModel
    let status: HunGitStatus

    private var shouldProtectLocalChanges: Bool {
        !status.clean
    }

    private var isUpdating: Bool {
        model.operation == .updatingBranch
    }

    private var commitLabel: String {
        "\(status.behind) \(status.behind == 1 ? "commit" : "commits")"
    }

    var body: some View {
        VStack(spacing: 0) {
            dialogHeader

            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 16) {
                Text("Bring \(commitLabel) from \(status.upstream) into \(status.branch).")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    updateDetailRow(
                        label: "Remote update",
                        value: "\(status.upstream) → \(status.branch)",
                        systemImage: "arrow.down.to.line"
                    )
                    Rectangle().fill(AppTheme.divider).frame(height: 1)
                    updateDetailRow(
                        label: "Local work",
                        value: status.clean
                            ? "Working tree clean"
                            : "\(status.changeCount) changed \(status.changeCount == 1 ? "file" : "files")",
                        systemImage: status.clean ? "checkmark.circle" : "doc.badge.ellipsis"
                    )
                    Rectangle().fill(AppTheme.divider).frame(height: 1)
                    updateDetailRow(
                        label: "Strategy",
                        value: shouldProtectLocalChanges
                            ? "Protect work, fast-forward, then restore"
                            : "Fast-forward only",
                        systemImage: "shield.checkered"
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.searchField)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.divider, lineWidth: 1)
                )

                if shouldProtectLocalChanges {
                    statusCallout(
                        systemImage: "shield.fill",
                        title: "Your local work will be protected",
                        detail: "Hun will preserve staged, unstaged, and untracked changes, update the branch, then restore the same working state.",
                        tone: AppTheme.warning
                    )
                }

                if let result = model.lastUpdateResult, result.recoveryRequired {
                    statusCallout(
                        systemImage: "exclamationmark.triangle.fill",
                        title: "Local changes need attention",
                        detail: result.recoveryMessage ??
                            "The remote update completed and the safety stash was kept.",
                        tone: AppTheme.warning
                    )
                } else if let error = model.errorMessage {
                    statusCallout(
                        systemImage: "xmark.circle.fill",
                        title: "Branch was not updated",
                        detail: error,
                        tone: AppTheme.danger
                    )
                }
            }
            .padding(18)

            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 1)

            dialogFooter
        }
        .frame(width: 500)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.dialogBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.dividerStrong, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topLeading) {
            HunGitEscapeKeyMonitor {
                model.dismissUpdateBranch()
            }
            .frame(width: 0, height: 0)
        }
        .onExitCommand {
            model.dismissUpdateBranch()
        }
    }

    private var dialogHeader: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppTheme.warning.opacity(0.11))
                    .frame(width: 32, height: 32)
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Update \(status.branch)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Safe fast-forward from the tracked remote branch")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            Text(status.upstream)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(AppTheme.chipFill)
                )
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(AppTheme.dialogRaised)
    }

    private var dialogFooter: some View {
        HStack(spacing: 8) {
            Text("Hun fetches again before updating")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textTertiary)

            Spacer()

            Button("Cancel") {
                model.dismissUpdateBranch()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.chipFill)
            )
            .disabled(isUpdating)

            Button {
                if model.lastUpdateResult?.recoveryRequired == true {
                    model.dismissUpdateBranch()
                } else {
                    Task {
                        await model.updateBranch(
                            protectLocalChanges: shouldProtectLocalChanges
                        )
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if isUpdating {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: model.lastUpdateResult?.recoveryRequired == true
                            ? "checkmark"
                            : "shield.checkered")
                            .font(.system(size: 9, weight: .bold))
                    }
                    Text(primaryActionTitle)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.accent.opacity(isUpdating ? 0.62 : 0.92))
                )
            }
            .buttonStyle(.plain)
            .disabled(isUpdating)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(AppTheme.dialogRaised)
    }

    private var primaryActionTitle: String {
        if model.lastUpdateResult?.recoveryRequired == true {
            return "Close"
        }
        return shouldProtectLocalChanges ? "Protect & update" : "Update branch"
    }

    private func updateDetailRow(
        label: String,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
    }

    private func statusCallout(
        systemImage: String,
        title: String,
        detail: String,
        tone: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tone)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tone.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tone.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct HunGitEscapeKeyMonitor: NSViewRepresentable {
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.install(for: view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.install(for: view.window)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onDismiss: () -> Void
        private weak var window: NSWindow?
        private var eventMonitor: Any?

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func install(for window: NSWindow?) {
            guard let window, self.window !== window else { return }
            uninstall()
            self.window = window
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self, weak window] event in
                guard let self, event.window === window, event.keyCode == 53 else {
                    return event
                }
                onDismiss()
                return nil
            }
        }

        func uninstall() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            eventMonitor = nil
            window = nil
        }

        deinit {
            uninstall()
        }
    }
}

private struct HunGitBranchDialog: View {
    @Bindable var model: HunGitWorkspaceModel
    @FocusState private var searchFocused: Bool
    @State private var keyboardSelectionID: String?

    private var currentBranches: [HunGitBranch] {
        model.filteredBranches.filter(\.current)
    }

    private var localBranches: [HunGitBranch] {
        model.filteredBranches.filter { !$0.current && !$0.remote }
    }

    private var remoteBranches: [HunGitBranch] {
        model.filteredBranches.filter(\.remote)
    }

    private var switchableBranches: [HunGitBranch] {
        model.filteredBranches.filter { !$0.current }
    }

    var body: some View {
        VStack(spacing: 0) {
            branchSearch

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            if let status = model.status, status.isRepository {
                repositoryContext(status)
                Rectangle().fill(AppTheme.divider).frame(height: 1)
            }

            if let pendingBranch = model.pendingBranchSwitch {
                branchSwitchDecision(pendingBranch)
                Rectangle().fill(AppTheme.divider).frame(height: 1)
            } else if let error = model.errorMessage {
                branchError(error)
                Rectangle().fill(AppTheme.divider).frame(height: 1)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if model.canCreateSearchedBranch {
                            createBranchRow
                        }
                        branchSection("Current", branches: currentBranches)
                        branchSection("Local branches", branches: localBranches)
                        branchSection("Remote branches", branches: remoteBranches)

                        if model.filteredBranches.isEmpty && !model.canCreateSearchedBranch {
                            Text(model.operation == .loadingBranches ? "Loading branches…" : "No branches found")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 44)
                        }
                    }
                    .padding(8)
                }
                .hunScrollStyle()
                .onChange(of: keyboardSelectionID) { _, selection in
                    guard let selection else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(selection, anchor: .center)
                    }
                }
            }

            Rectangle().fill(AppTheme.divider).frame(height: 1)
            branchFooter
        }
        .frame(width: 540, height: 500)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.dialogBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.dividerStrong, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topLeading) {
            HunGitBranchKeyboardMonitor(
                onMove: moveBranchSelection,
                onSubmit: submitBranchSearch,
                onDismiss: { model.cancelBranchPicker() }
            )
            .frame(width: 0, height: 0)
        }
        .onAppear {
            searchFocused = true
            Task { await model.loadBranches() }
        }
        .onDisappear {
            model.branchSearch = ""
            keyboardSelectionID = nil
        }
        .onExitCommand {
            model.cancelBranchPicker()
        }
    }

    private var branchSearch: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            TextField("Search branches or create a new one…", text: $model.branchSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textPrimary)
                .focused($searchFocused)
            if model.operation == .loadingBranches || model.operation == .switchingBranch ||
                model.operation == .creatingBranch {
                ProgressView()
                    .controlSize(.small)
            } else if !model.branchSearch.isEmpty {
                Button {
                    model.branchSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(AppTheme.dialogRaised)
    }

    private func repositoryContext(_ status: HunGitStatus) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let remoteCheckAge = HunGitRemoteCheckAge(
                checkedAt: model.lastRemoteCheckAt,
                relativeTo: context.date
            )
            let tone = status.syncState.tone(remoteCheckAge: remoteCheckAge)

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tone.opacity(0.10))
                        .frame(width: 30, height: 30)
                    Image(systemName: status.syncState.icon(remoteCheckAge: remoteCheckAge))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tone)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.syncState.headline(remoteCheckAge: remoteCheckAge))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(model.operation == .fetching
                        ? "Checking the remote for new commits…"
                        : status.syncState.guidance ?? remoteCheckAge.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Spacer()

                Text(status.branch.isEmpty ? "DETACHED" : status.branch)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(AppTheme.chipFill)
                    )
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(AppTheme.dialogBackground)
    }

    private func submitBranchSearch() {
        let query = model.branchSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isBusy else { return }

        if let keyboardSelectionID,
           let selection = switchableBranches.first(where: { $0.id == keyboardSelectionID }) {
            switchToBranch(selection)
            return
        }

        guard !query.isEmpty else { return }

        if let exactMatch = model.filteredBranches.first(where: {
            $0.name.caseInsensitiveCompare(query) == .orderedSame && !$0.current
        }) {
            switchToBranch(exactMatch)
        } else if model.canCreateSearchedBranch {
            Task {
                if await model.createBranch(query) {
                    model.isBranchPickerPresented = false
                }
            }
        }
    }

    private func moveBranchSelection(_ direction: MoveCommandDirection) {
        guard direction == .up || direction == .down else { return }
        let branches = switchableBranches
        guard !branches.isEmpty else {
            keyboardSelectionID = nil
            return
        }

        guard let currentID = keyboardSelectionID,
              let currentIndex = branches.firstIndex(where: { $0.id == currentID })
        else {
            keyboardSelectionID = direction == .down ? branches.first?.id : branches.last?.id
            return
        }
        let offset = direction == .down ? 1 : -1
        keyboardSelectionID = branches[(currentIndex + offset + branches.count) % branches.count].id
    }

    private func switchToBranch(_ branch: HunGitBranch) {
        Task {
            if await model.switchBranch(branch.name) {
                model.isBranchPickerPresented = false
            }
        }
    }

    @ViewBuilder
    private func branchSection(_ title: String, branches: [HunGitBranch]) -> some View {
        if !branches.isEmpty {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.55)
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 2)

            ForEach(branches) { branch in
                Button {
                    guard !branch.current else { return }
                    switchToBranch(branch)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: branch.current ? "checkmark" : "arrow.triangle.branch")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(branch.current ? AppTheme.accent : AppTheme.textTertiary)
                            .frame(width: 14)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(branch.name)
                                .font(.system(size: 12.5, weight: branch.current ? .medium : .regular))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(1)
                            if let upstream = branch.upstream, !upstream.isEmpty {
                                Text(upstream)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if branch.remote {
                            Text("REMOTE")
                                .font(.system(size: 8.5, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(AppTheme.textTertiary)
                        } else if branch.current {
                            Text("CURRENT")
                                .font(.system(size: 8.5, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                branch.current || keyboardSelectionID == branch.id
                                    ? AppTheme.selection
                                    : Color.clear
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(HunGitRowButtonStyle())
                .disabled(branch.current || model.isBusy)
                .id(branch.id)
            }
        }
    }

    private var createBranchRow: some View {
        let name = model.branchSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            Task {
                if await model.createBranch(name) {
                    model.isBranchPickerPresented = false
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create “\(name)”")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Branch from the current HEAD")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                Spacer()
                Text("↩")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(HunGitRowButtonStyle())
        .disabled(model.isBusy)
    }

    private func branchSwitchDecision(_ destination: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.warning.opacity(0.10))
                        .frame(width: 28, height: 28)
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Finish current work before switching")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(localChangesDescription(destination: destination))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 6) {
                branchRouteChip(model.status?.branch ?? "Current")

                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)

                branchRouteChip(destination)

                Spacer()

                Button("Cancel") {
                    model.cancelPendingBranchSwitch()
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary)

                Button("Review & commit") {
                    Task {
                        await model.reviewChangesForPendingBranchSwitch()
                    }
                }
                .buttonStyle(HunGitSecondaryButtonStyle())

                Button("Stash & switch") {
                    Task {
                        if await model.stashAndSwitchPendingBranch() {
                            model.isBranchPickerPresented = false
                        }
                    }
                }
                .buttonStyle(HunGitProminentButtonStyle())
            }
            .font(.system(size: 11, weight: .medium))
        }
        .padding(12)
        .background(AppTheme.warning.opacity(0.06))
    }

    private func branchRouteChip(_ branch: String) -> some View {
        Text(branch)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .frame(maxWidth: 126)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(AppTheme.chipFill)
            )
    }

    private func localChangesDescription(destination: String) -> String {
        let count = model.status?.changeCount ?? 0
        let commitPronoun = count == 1 ? "it" : "them"
        return "\(count) local \(count == 1 ? "change needs" : "changes need") a home before moving to \(destination). Commit \(commitPronoun) here, or stash \(commitPronoun) for later."
    }

    private func branchError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.danger)
                .padding(.top, 2)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(3)
            Spacer()
        }
        .padding(12)
        .background(AppTheme.danger.opacity(0.06))
    }

    private var branchFooter: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await model.presentWorkspace()
                    model.isBranchPickerPresented = false
                }
            } label: {
                Label("Open Git workspace", systemImage: "rectangle.split.2x1")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary)

            Spacer()

            HStack(spacing: 8) {
                keyHint("↑↓", label: "Navigate")
                keyHint("↩", label: "Switch")
                keyHint("esc", label: "Close")
            }

            Rectangle()
                .fill(AppTheme.divider)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)

            Button {
                Task { await model.fetch() }
            } label: {
                Label("Fetch remote", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary)
            .disabled(model.isBusy)
            .help("Check the remote for new commits without changing local files")
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(AppTheme.dialogRaised)
    }

    private func keyHint(_ key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 4)
                .frame(height: 17)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AppTheme.chipFill)
                )
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(AppTheme.textTertiary)
        }
    }
}

private struct HunGitBranchKeyboardMonitor: NSViewRepresentable {
    let onMove: (MoveCommandDirection) -> Void
    let onSubmit: () -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMove: onMove, onSubmit: onSubmit, onDismiss: onDismiss)
    }

    func makeNSView(context: Context) -> HunGitBranchMonitorView {
        let view = HunGitBranchMonitorView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.install(for: window)
        }
        return view
    }

    func updateNSView(_ view: HunGitBranchMonitorView, context: Context) {
        context.coordinator.onMove = onMove
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onDismiss = onDismiss
        context.coordinator.install(for: view.window)
    }

    static func dismantleNSView(_ view: HunGitBranchMonitorView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var onMove: (MoveCommandDirection) -> Void
        var onSubmit: () -> Void
        var onDismiss: () -> Void
        private weak var window: NSWindow?
        private var eventMonitor: Any?

        init(
            onMove: @escaping (MoveCommandDirection) -> Void,
            onSubmit: @escaping () -> Void,
            onDismiss: @escaping () -> Void
        ) {
            self.onMove = onMove
            self.onSubmit = onSubmit
            self.onDismiss = onDismiss
        }

        func install(for window: NSWindow?) {
            guard let window else {
                removeMonitor()
                return
            }
            guard self.window !== window else { return }
            removeMonitor()
            self.window = window
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.window?.isVisible == true,
                      self.window?.isKeyWindow == true
                else {
                    return event
                }
                switch event.keyCode {
                case 125:
                    onMove(.down)
                    return nil
                case 126:
                    onMove(.up)
                    return nil
                case 36, 76:
                    onSubmit()
                    return nil
                case 53:
                    onDismiss()
                    return nil
                default:
                    return event
                }
            }
        }

        func removeMonitor() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            window = nil
        }

        deinit {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
        }
    }
}

private final class HunGitBranchMonitorView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

struct HunProjectWorkspaceSwitcher: View {
    @Bindable var model: HunGitWorkspaceModel

    var body: some View {
        HStack(spacing: 2) {
            workspaceButton(
                title: "Services",
                systemImage: "square.stack.3d.up",
                selected: !model.isWorkspacePresented
            ) {
                model.isWorkspacePresented = false
            }

            workspaceButton(
                title: "Git",
                systemImage: "arrow.triangle.branch",
                selected: model.isWorkspacePresented,
                badge: model.status?.changeCount
            ) {
                Task { await model.presentWorkspace() }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(AppTheme.appBackground)
    }

    private func workspaceButton(
        title: String,
        systemImage: String,
        selected: Bool,
        badge: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(selected ? AppTheme.warning : AppTheme.textTertiary)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(selected ? AppTheme.textPrimary : AppTheme.textTertiary)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(selected ? AppTheme.textPrimary.opacity(0.72) : Color.clear)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) workspace")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct HunGitWorkspaceView: View {
    @AppStorage(HunWorkspacePanelPreference.gitChangesWidth)
    private var changesPanelWidth = Double(HunWorkspacePanelMetrics.gitDefaultWidth)

    let project: HunProject
    @Bindable var model: HunGitWorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            workspaceToolbar

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            if let pendingBranch = model.pendingBranchSwitch {
                pendingBranchSwitchBanner(pendingBranch)
                Rectangle().fill(AppTheme.divider).frame(height: 1)
            }

            if let error = model.errorMessage {
                workspaceError(error)
                Rectangle().fill(AppTheme.divider).frame(height: 1)
            }

            if let status = model.status {
                if status.isRepository {
                    HunResizableWorkspaceSplit(
                        preferredWidth: $changesPanelWidth,
                        accessibilityLabel: "Resize Git changes panel"
                    ) {
                        HunGitChangesPanel(model: model, status: status)
                    } detail: {
                        HunGitDiffPanel(model: model)
                    }
                } else {
                    gitEmptyState(
                        icon: "folder.badge.questionmark",
                        title: "Not a Git repository",
                        detail: "\(project.name) does not contain a Git working tree."
                    )
                }
            } else {
                gitEmptyState(
                    icon: "arrow.triangle.branch",
                    title: "Reading repository",
                    detail: "Inspecting the working tree and branch state."
                )
            }
        }
        .background(AppTheme.appBackground)
    }

    private func pendingBranchSwitchBanner(_ destination: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.warning.opacity(0.10))
                    .frame(width: 28, height: 28)
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("Preparing to switch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(model.status?.branch ?? "current")
                        .foregroundStyle(AppTheme.textTertiary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(destination)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(pendingSwitchDetail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            Button("Cancel") {
                model.cancelPendingBranchSwitch()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)

            Button("Stash & switch") {
                Task {
                    _ = await model.stashAndSwitchPendingBranch()
                }
            }
            .buttonStyle(HunGitSecondaryButtonStyle())
            .font(.system(size: 10.5, weight: .medium))
            .disabled(model.isBusy)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(AppTheme.warning.opacity(0.05))
    }

    private var pendingSwitchDetail: String {
        let count = model.status?.changeCount ?? 0
        return "\(count) local \(count == 1 ? "change remains" : "changes remain"). Stage the work to keep, then commit below; Hun switches once the tree is clean."
    }

    private var workspaceToolbar: some View {
        HStack(spacing: 10) {
            if let status = model.status, status.isRepository {
                syncSummary(status)
            } else {
                Text("Git status")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Spacer()

            HunGitToolbarButton(
                title: "Fetch remote",
                systemImage: "arrow.down.circle",
                loading: model.operation == .fetching,
                disabled: model.isBusy,
                help: "Check the remote for new commits without changing local files"
            ) {
                Task { await model.fetch() }
            }

            if let status = model.status {
                syncAction(status)
            }

            HunGitToolbarButton(
                title: nil,
                systemImage: "arrow.clockwise",
                loading: model.operation == .refreshing,
                disabled: model.isBusy,
                help: "Refresh repository"
            ) {
                Task { await model.refresh() }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(AppTheme.appBackground)
    }

    private func syncSummary(_ status: HunGitStatus) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let remoteCheckAge = HunGitRemoteCheckAge(
                checkedAt: model.lastRemoteCheckAt,
                relativeTo: context.date
            )
            let tone = status.syncState.tone(remoteCheckAge: remoteCheckAge)

            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(tone.opacity(0.10))
                        .frame(width: 26, height: 26)
                    Image(systemName: status.syncState.icon(remoteCheckAge: remoteCheckAge))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(tone)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.syncState.headline(remoteCheckAge: remoteCheckAge))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text(syncDetail(status, remoteCheckAge: remoteCheckAge))
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func syncDetail(
        _ status: HunGitStatus,
        remoteCheckAge: HunGitRemoteCheckAge
    ) -> String {
        switch model.operation {
        case .fetching:
            return "Checking the remote without changing local files…"
        case .pulling:
            return "Fast-forwarding to the remote branch…"
        case .updatingBranch:
            return status.clean
                ? "Fast-forwarding to the remote branch…"
                : "Protecting local work and updating the branch…"
        case .pushing:
            return "Sending local commits to the remote…"
        default:
            break
        }
        if let operation = status.operation {
            return "\(operation.capitalized) in progress"
        }
        if !status.conflictedFiles.isEmpty {
            return "\(status.conflictedFiles.count) conflicts need attention"
        }
        if let guidance = status.syncState.guidance {
            return guidance
        }
        let workingTree =
            status.changeCount == 0
                ? "Working tree clean"
                : "\(status.changeCount) uncommitted \(status.changeCount == 1 ? "change" : "changes")"
        return "\(workingTree) · \(remoteCheckAge.detail.lowercased())"
    }

    @ViewBuilder
    private func syncAction(_ status: HunGitStatus) -> some View {
        switch status.syncState {
        case let .ahead(count, _):
            HunGitToolbarButton(
                title: "Push \(count)",
                systemImage: "arrow.up.to.line",
                loading: model.operation == .pushing,
                disabled: model.isBusy,
                help: "Push \(count) local \(count == 1 ? "commit" : "commits") to the remote"
            ) {
                Task { await model.push() }
            }
        case let .behind(count, _):
            HunGitToolbarButton(
                title: "Update branch",
                systemImage: "arrow.down.to.line",
                loading: model.operation == .updatingBranch,
                disabled: model.isBusy || !status.conflictedFiles.isEmpty,
                help: "Safely bring \(count) remote \(count == 1 ? "commit" : "commits") into this branch"
            ) {
                model.presentUpdateBranch()
            }
        case .unpublished:
            HunGitToolbarButton(
                title: "Publish branch",
                systemImage: "icloud.and.arrow.up",
                loading: model.operation == .pushing,
                disabled: model.isBusy,
                help: "Push this branch to origin and set its upstream"
            ) {
                Task { await model.push() }
            }
        case .upToDate, .diverged, .detached:
            EmptyView()
        }
    }

    private func workspaceError(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.warning)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
            Spacer()
            Button {
                model.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(AppTheme.warning.opacity(0.06))
    }

    private func gitEmptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(AppTheme.textTertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HunGitChangesPanel: View {
    @Bindable var model: HunGitWorkspaceModel
    let status: HunGitStatus
    @FocusState private var commitMessageFocused: Bool

    private var conflicts: [HunGitFileChange] {
        status.conflictedFiles
    }

    private var staged: [HunGitFileChange] {
        status.stagedFiles
    }

    private var unstaged: [HunGitFileChange] {
        status.unstagedFiles
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Working tree")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                HunGitToolbarButton(
                    title: "Stage all",
                    systemImage: "plus",
                    loading: model.operation == .staging,
                    disabled: unstaged.isEmpty || !conflicts.isEmpty || model.isBusy,
                    help: conflicts.isEmpty
                        ? "Stage every unstaged change"
                        : "Resolve conflicts before staging all changes"
                ) {
                    Task { await model.stageAll() }
                }
                Text("\(status.changeCount)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .frame(height: 38)

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            if status.clean {
                VStack(spacing: 9) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(AppTheme.success.opacity(0.75))
                    Text("Working tree clean")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    if !status.head.isEmpty {
                        Text(String(status.head.prefix(8)))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        changeSection("Conflicts", changes: conflicts, staged: false, tone: AppTheme.danger)
                        changeSection("Staged", changes: staged, staged: true, tone: AppTheme.success)
                        changeSection("Changes", changes: unstaged, staged: false, tone: AppTheme.warning)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 12)
                }
                .hunScrollStyle()
            }

            Rectangle().fill(AppTheme.divider).frame(height: 1)
            commitComposer
        }
        .background(AppTheme.appBackground)
    }

    @ViewBuilder
    private func changeSection(
        _ title: String,
        changes: [HunGitFileChange],
        staged: Bool,
        tone: Color
    ) -> some View {
        if !changes.isEmpty {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.55)
                    .foregroundStyle(tone.opacity(0.9))
                Spacer()
                Text("\(changes.count)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 3)

            ForEach(changes.map { HunGitChangeRowItem(change: $0, staged: staged) }) { item in
                HunGitChangeRow(
                    change: item.change,
                    staged: item.staged,
                    selected: model.selectedPath == item.change.path &&
                        model.selectedStaged == item.staged,
                    busy: model.isBusy,
                    onSelect: {
                        Task { await model.loadDiff(for: item.change, staged: item.staged) }
                    },
                    onToggleStage: {
                        Task {
                            if item.staged {
                                await model.unstage(item.change)
                            } else {
                                await model.stage(item.change)
                            }
                        }
                    }
                )
            }
        }
    }

    private var commitComposer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("COMMIT")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(AppTheme.textTertiary)

                Spacer(minLength: 8)

                Button {
                    Task { await model.generateCommitMessage() }
                } label: {
                    HStack(spacing: 5) {
                        if model.isGeneratingCommitMessage {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 11, height: 11)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9.5, weight: .semibold))
                        }

                        Text(model.isGeneratingCommitMessage ? "Generating…" : "Generate")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(
                        commitMessageGenerationDisabled
                            ? AppTheme.textTertiary
                            : AppTheme.textSecondary
                    )
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(AppTheme.buttonFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(AppTheme.divider, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(commitMessageGenerationDisabled)
                .help(commitMessageGenerationHelp)
                .accessibilityLabel("Generate commit message")
            }
            .frame(height: 22)

            TextEditor(text: $model.commitMessage)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .hunScrollStyle()
                .focused($commitMessageFocused)
                .padding(7)
                .frame(height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.appBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            commitMessageFocused ? AppTheme.dividerStrong : AppTheme.divider,
                            lineWidth: 1
                        )
                )
                .overlay(alignment: .topLeading) {
                    if model.commitMessage.isEmpty {
                        Text(commitPlaceholder)
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textTertiary)
                            .padding(.leading, 12)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                Text(commitMessageGenerationStatus)
                    .font(.system(size: 9.5))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(AppTheme.textTertiary)
            .frame(height: 12)

            HStack(spacing: 6) {
                commitButton(
                    title: primaryCommitTitle,
                    systemImage: "checkmark",
                    prominent: true,
                    loading: model.operation == .committing && !model.isCommitAndPushInFlight
                ) {
                    Task { _ = await model.commit() }
                }

                commitButton(
                    title: "Commit & Push",
                    systemImage: "arrow.up",
                    prominent: false,
                    loading: model.isCommitAndPushInFlight
                ) {
                    Task { _ = await model.commitAndPush() }
                }
            }
        }
        .padding(10)
        .background(AppTheme.buttonFill.opacity(0.45))
    }

    private func commitButton(
        title: String,
        systemImage: String,
        prominent: Bool,
        loading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HunGitCommitActionButton(
            title: title,
            systemImage: systemImage,
            primary: prominent,
            loading: loading,
            disabled: commitDisabled,
            helpText: prominent
                ? "Create a local commit from staged changes"
                : "Create the commit, then push it to the remote",
            action: action
        )
    }

    private var commitDisabled: Bool {
        staged.isEmpty ||
            model.isCommitAndPushInFlight ||
            model.isGeneratingCommitMessage ||
            model.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            model.isBusy
    }

    private var commitMessageGenerationDisabled: Bool {
        staged.isEmpty ||
            model.isBusy ||
            model.isGeneratingCommitMessage ||
            model.commitMessageGenerationAvailability != .available
    }

    private var commitMessageGenerationStatus: String {
        if let notice = model.commitMessageGenerationNotice {
            return notice
        }
        switch model.commitMessageGenerationAvailability {
        case .available:
            return "On-device · staged changes only"
        case let .unavailable(reason):
            return reason
        }
    }

    private var commitMessageGenerationHelp: String {
        switch model.commitMessageGenerationAvailability {
        case .available:
            return "Generate a Conventional Commit message from staged changes on this Mac"
        case let .unavailable(reason):
            return reason
        }
    }

    private var primaryCommitTitle: String {
        guard model.pendingBranchSwitch != nil,
              unstaged.isEmpty,
              conflicts.isEmpty
        else {
            return "Commit"
        }
        return "Commit & switch"
    }

    private var commitPlaceholder: String {
        guard let destination = model.pendingBranchSwitch else {
            return "Commit message…"
        }
        return "Commit before switching to \(destination)…"
    }
}

private struct HunGitCommitActionButton: View {
    let title: String
    let systemImage: String
    let primary: Bool
    let loading: Bool
    let disabled: Bool
    let helpText: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if loading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            HunGitCommitButtonStyle(
                primary: primary,
                disabled: disabled,
                hovering: hovering
            )
        )
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(helpText)
    }
}

private struct HunGitCommitButtonStyle: ButtonStyle {
    let primary: Bool
    let disabled: Bool
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var foregroundColor: Color {
        guard !disabled else { return AppTheme.textTertiary.opacity(0.55) }
        return primary ? AppTheme.textPrimary : AppTheme.textSecondary
    }

    private func backgroundColor(pressed: Bool) -> Color {
        guard !disabled else { return AppTheme.buttonFill.opacity(0.55) }
        if pressed {
            return primary ? Color.white.opacity(0.12) : AppTheme.selection
        }
        if hovering {
            return primary ? Color.white.opacity(0.10) : AppTheme.hover
        }
        return primary ? Color.white.opacity(0.075) : AppTheme.buttonFill
    }

    private var borderColor: Color {
        guard !disabled else { return AppTheme.divider.opacity(0.55) }
        return primary ? AppTheme.dividerStrong : AppTheme.divider
    }
}

private struct HunGitChangeRow: View {
    let change: HunGitFileChange
    let staged: Bool
    let selected: Bool
    let busy: Bool
    let onSelect: () -> Void
    let onToggleStage: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Text(statusLetter)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(statusColor)
                        .frame(width: 13)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(change.displayName)
                            .font(.system(size: 10.75, weight: selected ? .medium : .regular))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        if !change.parentPath.isEmpty {
                            Text(change.parentPath)
                                .font(.system(size: 9.25))
                                .foregroundStyle(AppTheme.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggleStage) {
                Image(systemName: staged ? "minus" : "plus")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(
                        hovering
                            ? AppTheme.textPrimary
                            : (staged ? AppTheme.success.opacity(0.82) : AppTheme.warning.opacity(0.82))
                    )
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(hovering ? AppTheme.hover : AppTheme.buttonFill.opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(AppTheme.divider.opacity(hovering ? 1 : 0.7), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityLabel(staged ? "Unstage \(change.displayName)" : "Stage \(change.displayName)")
            .help(staged ? "Unstage \(change.path)" : "Stage \(change.path)")
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? AppTheme.selection : (hovering ? AppTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var statusLetter: String {
        if change.conflicted { return "!" }
        return selectedFileStatus.displayLetter
    }

    private var selectedFileStatus: HunGitFileStatus {
        staged ? change.indexState : change.worktreeState
    }

    private var statusColor: Color {
        if change.conflicted { return AppTheme.danger }
        switch selectedFileStatus {
        case .untracked, .added: return AppTheme.success
        case .deleted: return AppTheme.danger
        case .renamed, .copied: return AppTheme.accent
        default: return AppTheme.warning
        }
    }
}

private struct HunGitDiffPanel: View {
    @Bindable var model: HunGitWorkspaceModel
    @AppStorage("hun.git.diff.presentation")
    private var presentationRawValue = HunGitDiffPresentation.unified.rawValue
    @AppStorage("hun.git.diff.showWhitespace")
    private var showWhitespace = false

    private var presentation: HunGitDiffPresentation {
        get { HunGitDiffPresentation(rawValue: presentationRawValue) ?? .unified }
        nonmutating set { presentationRawValue = newValue.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let path = model.selectedPath {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(path)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(model.selectedStaged ? "STAGED" : "WORKING TREE")
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.45)
                        .foregroundStyle(model.selectedStaged ? AppTheme.success : AppTheme.warning)
                } else {
                    Text("Diff")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                if model.selectedDiffMetadata?.truncated == true {
                    Text("TRUNCATED")
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.45)
                        .foregroundStyle(AppTheme.warning)
                }
                HunGitDiffPresentationControl(selection: presentation) {
                    presentation = $0
                }
                Menu {
                    Toggle("Show whitespace characters", isOn: $showWhitespace)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Diff display options")
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 38)

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            Group {
                if model.operation == .loadingDiff && model.selectedDiffMetadata == nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let diff = model.selectedDiffMetadata {
                    if diff.binary {
                        diffEmptyState(
                            icon: "doc.badge.ellipsis",
                            title: "Binary file",
                            detail: "A textual diff is not available for this file."
                        )
                    } else if model.selectedDiffDocument?.lines.isEmpty != false {
                        diffEmptyState(
                            icon: "checkmark",
                            title: "No textual changes",
                            detail: "The selected side of this file has no diff."
                        )
                    } else if let document = model.selectedDiffDocument {
                        HunGitDiffView(
                            document: document,
                            path: diff.path,
                            presentation: presentation,
                            showWhitespace: showWhitespace
                        )
                    }
                } else {
                    diffEmptyState(
                        icon: "arrow.left",
                        title: "Select a changed file",
                        detail: "Choose a staged or working-tree change to inspect its diff."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.appBackground)
    }

    private func diffEmptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(AppTheme.textTertiary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)
        }
    }
}

private struct HunGitDiffPresentationControl: View {
    let selection: HunGitDiffPresentation
    let onSelect: (HunGitDiffPresentation) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HunGitDiffPresentation.allCases, id: \.rawValue) { presentation in
                Button {
                    onSelect(presentation)
                } label: {
                    Text(presentation.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(
                            selection == presentation ? AppTheme.textPrimary : AppTheme.textTertiary
                        )
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            selection == presentation ? AppTheme.selection : Color.clear
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == presentation ? .isSelected : [])
            }
        }
        .background(AppTheme.buttonFill)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
    }
}

private struct HunGitToolbarButton: View {
    let title: String?
    let systemImage: String
    let loading: Bool
    let disabled: Bool
    var help: String?
    let action: () -> Void
    @State private var hovering = false

    init(
        title: String?,
        systemImage: String,
        loading: Bool = false,
        disabled: Bool = false,
        help: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.loading = loading
        self.disabled = disabled
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if loading {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 9.5, weight: .semibold))
                        .frame(width: 11, height: 11)
                }
                if let title {
                    Text(title)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(disabled ? AppTheme.textTertiary.opacity(0.55) : AppTheme.textSecondary)
            .padding(.horizontal, title == nil ? 7 : 9)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering && !disabled ? AppTheme.hover : AppTheme.buttonFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(help ?? title ?? "")
    }
}

private struct HunGitRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.selection : Color.clear)
            )
    }
}

private struct HunGitProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.accent.opacity(configuration.isPressed ? 0.72 : 0.92))
            )
    }
}

private struct HunGitSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.selection : AppTheme.chipFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
    }
}
