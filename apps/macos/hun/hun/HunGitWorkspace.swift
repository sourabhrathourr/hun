import AppKit
import SwiftUI

struct HunRepositoryStatusCapsule: View {
    let project: HunProject
    @Bindable var model: HunGitWorkspaceModel
    @State private var hovering = false

    private var status: HunGitStatus? {
        model.status?.isRepository == true ? model.status : nil
    }

    private var branchName: String {
        if let status {
            if status.detached {
                return "detached"
            }
            if !status.branch.isEmpty {
                return status.branch
            }
        }
        return project.branch ?? "Repository"
    }

    private var tone: Color {
        guard let status else { return AppTheme.textTertiary }
        if !status.conflictedFiles.isEmpty { return AppTheme.danger }
        if status.operation != nil || !status.clean || status.ahead > 0 || status.behind > 0 {
            return AppTheme.warning
        }
        return AppTheme.textSecondary
    }

    var body: some View {
        Button {
            model.isBranchPickerPresented.toggle()
            if model.isBranchPickerPresented {
                Task { await model.loadBranches() }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9.5, weight: .semibold))

                Text(branchName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let status {
                    if !status.conflictedFiles.isEmpty {
                        Text("· \(status.conflictedFiles.count) conflicts")
                    } else if status.changeCount > 0 {
                        Text("· \(status.changeCount) changes")
                    }
                    if status.ahead > 0 {
                        Text("↑\(status.ahead)")
                            .monospacedDigit()
                    }
                    if status.behind > 0 {
                        Text("↓\(status.behind)")
                            .monospacedDigit()
                    }
                } else if model.operation == .refreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.55)
                        .frame(width: 9, height: 9)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .opacity(0.7)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tone)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? tone.opacity(0.10) : AppTheme.chipFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(hovering ? tone.opacity(0.24) : AppTheme.divider, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Switch branch or open Git changes")
        .popover(isPresented: $model.isBranchPickerPresented, arrowEdge: .bottom) {
            HunGitBranchPopover(model: model)
        }
    }
}

private struct HunGitBranchPopover: View {
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

            if let error = model.errorMessage {
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
        .frame(width: 480, height: 450)
        .background(AppTheme.elevated)
        .overlay(alignment: .topLeading) {
            HunGitBranchKeyboardMonitor(
                onMove: moveBranchSelection,
                onSubmit: submitBranchSearch
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
    }

    private var branchSearch: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            TextField("Search or create a branch…", text: $model.branchSearch)
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
        .background(AppTheme.searchField)
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

    private func branchError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.warning)
                    .padding(.top, 2)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(3)
                Spacer()
            }

            if model.pendingBranchSwitch != nil {
                HStack {
                    Spacer()
                    Button("Cancel") {
                        model.dismissError()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.textSecondary)

                    Button("Stash and switch") {
                        Task {
                            if await model.stashAndSwitchPendingBranch() {
                                model.isBranchPickerPresented = false
                            }
                        }
                    }
                    .buttonStyle(HunGitProminentButtonStyle())
                }
                .font(.system(size: 11.5, weight: .medium))
            }
        }
        .padding(12)
        .background(AppTheme.warning.opacity(0.06))
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

            Button {
                Task { await model.fetch() }
            } label: {
                Label("Fetch", systemImage: "arrow.down")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary)
            .disabled(model.isBusy)
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(AppTheme.buttonFill)
    }
}

private struct HunGitBranchKeyboardMonitor: NSViewRepresentable {
    let onMove: (MoveCommandDirection) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMove: onMove, onSubmit: onSubmit)
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
        context.coordinator.install(for: view.window)
    }

    static func dismantleNSView(_ view: HunGitBranchMonitorView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var onMove: (MoveCommandDirection) -> Void
        var onSubmit: () -> Void
        private weak var window: NSWindow?
        private var eventMonitor: Any?

        init(
            onMove: @escaping (MoveCommandDirection) -> Void,
            onSubmit: @escaping () -> Void
        ) {
            self.onMove = onMove
            self.onSubmit = onSubmit
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
    let project: HunProject
    @Bindable var model: HunGitWorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            workspaceToolbar

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            if let error = model.errorMessage {
                workspaceError(error)
                Rectangle().fill(AppTheme.divider).frame(height: 1)
            }

            if let status = model.status {
                if status.isRepository {
                    HStack(spacing: 0) {
                        HunGitChangesPanel(model: model, status: status)
                            .frame(width: 310)

                        Rectangle().fill(AppTheme.divider).frame(width: 1)

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

    private var workspaceToolbar: some View {
        HStack(spacing: 8) {
            Text("Changes")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            if let status = model.status {
                Text(repositorySummary(status))
                    .font(.system(size: 10.5))
                    .foregroundStyle(summaryColor(status))
                    .lineLimit(1)
            }

            Spacer()

            HunGitToolbarButton(
                title: "Fetch",
                systemImage: "arrow.down",
                loading: model.operation == .fetching,
                disabled: model.isBusy
            ) {
                Task { await model.fetch() }
            }
            HunGitToolbarButton(
                title: "Pull",
                systemImage: "arrow.down.to.line",
                loading: model.operation == .pulling,
                disabled: model.isBusy || model.status?.upstream.isEmpty != false
            ) {
                Task { await model.pull() }
            }
            HunGitToolbarButton(
                title: "Push",
                systemImage: "arrow.up.to.line",
                loading: model.operation == .pushing,
                disabled: model.isBusy || model.status?.detached == true
            ) {
                Task { await model.push() }
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
        .frame(height: 42)
        .background(AppTheme.appBackground)
    }

    private func repositorySummary(_ status: HunGitStatus) -> String {
        if let operation = status.operation {
            return "\(operation.capitalized) in progress"
        }
        if !status.conflictedFiles.isEmpty {
            return "\(status.conflictedFiles.count) conflicts"
        }
        if status.clean {
            return status.ahead == 0 && status.behind == 0 ? "Clean" : divergence(status)
        }
        return "\(status.changeCount) changes\(divergence(status).isEmpty ? "" : " · \(divergence(status))")"
    }

    private func divergence(_ status: HunGitStatus) -> String {
        [status.ahead > 0 ? "↑\(status.ahead)" : nil, status.behind > 0 ? "↓\(status.behind)" : nil]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func summaryColor(_ status: HunGitStatus) -> Color {
        if !status.conflictedFiles.isEmpty { return AppTheme.danger }
        if status.operation != nil || !status.clean || status.ahead > 0 || status.behind > 0 {
            return AppTheme.warning
        }
        return AppTheme.textTertiary
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

            ForEach(changes, id: \.path) { change in
                HunGitChangeRow(
                    change: change,
                    staged: staged,
                    selected: model.selectedPath == change.path && model.selectedStaged == staged,
                    busy: model.isBusy,
                    onSelect: {
                        Task { await model.loadDiff(for: change, staged: staged) }
                    },
                    onToggleStage: {
                        Task {
                            if staged {
                                await model.unstage(change)
                            } else {
                                await model.stage(change)
                            }
                        }
                    }
                )
            }
        }
    }

    private var commitComposer: some View {
        VStack(spacing: 8) {
            TextEditor(text: $model.commitMessage)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .hunScrollStyle()
                .padding(7)
                .frame(height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.searchField)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(AppTheme.divider, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if model.commitMessage.isEmpty {
                        Text("Commit message…")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textTertiary)
                            .padding(.leading, 12)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                Task { _ = await model.commit() }
            } label: {
                HStack(spacing: 6) {
                    if model.operation == .committing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    Text(staged.isEmpty ? "Commit staged changes" : "Commit \(staged.count) \(staged.count == 1 ? "file" : "files")")
                    Spacer()
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.accent.opacity(staged.isEmpty ? 0.35 : 0.92))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(
                staged.isEmpty ||
                    model.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    model.isBusy
            )
        }
        .padding(10)
        .background(AppTheme.buttonFill)
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
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Text(statusLetter)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(statusColor)
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(change.displayName)
                            .font(.system(size: 11.5, weight: selected ? .medium : .regular))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        if !change.parentPath.isEmpty {
                            Text(change.parentPath)
                                .font(.system(size: 9.5))
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
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(hovering ? AppTheme.hover : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .help(staged ? "Unstage \(change.path)" : "Stage \(change.path)")
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? AppTheme.selection : (hovering ? AppTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var statusLetter: String {
        if change.conflicted { return "!" }
        if change.untracked { return "?" }
        return selectedFileStatus.displayLetter
    }

    private var selectedFileStatus: HunGitFileStatus {
        staged ? change.indexState : change.worktreeState
    }

    private var statusColor: Color {
        if change.conflicted { return AppTheme.danger }
        if change.untracked { return AppTheme.textSecondary }
        switch selectedFileStatus {
        case .added: return AppTheme.success
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
