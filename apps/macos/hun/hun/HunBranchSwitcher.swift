import AppKit
import SwiftUI

private extension HunGitSyncState {
    /// A few words for the switcher footer.
    var summary: String {
        switch self {
        case let .upToDate(upstream):
            "Up to date with \(upstream)"
        case let .ahead(count, _):
            "\(count) to push"
        case let .behind(count, _):
            "\(count) to pull"
        case let .diverged(ahead, behind, _):
            "\(ahead) to push, \(behind) to pull"
        case .unpublished:
            "Not published"
        case .detached:
            "Detached HEAD"
        }
    }
}

private extension HunGitRemoteCheckAge {
    var shortDetail: String? {
        switch self {
        case .never:
            nil
        case .justNow:
            "checked just now"
        case let .minutes(count):
            "checked \(count)m ago"
        case let .hours(count):
            "checked \(count)h ago"
        case let .days(count):
            "checked \(count)d ago"
        }
    }
}

/// The branch chip in the project header; opens the branch switcher.
struct HunRepositoryStatusCapsule: View {
    let branch: String
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9.5, weight: .semibold))

                Text(branch)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .opacity(0.65)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                HunRoundedShape()
                    .fill(hovering ? AppTheme.hover : AppTheme.chipFill)
            )
            .overlay(
                HunRoundedShape()
                    .stroke(
                        hovering ? AppTheme.textTertiary.opacity(0.32) : AppTheme.divider,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Switch branch")
    }
}

struct HunGitBranchDialogOverlay: View {
    @Bindable var model: HunBranchModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
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

private struct HunGitBranchDialog: View {
    @Bindable var model: HunBranchModel
    @FocusState private var searchFocused: Bool
    @State private var keyboardSelectionID: String?

    private var currentBranch: HunGitBranch? {
        model.filteredBranches.first(where: \.current)
    }

    private var localBranches: [HunGitBranch] {
        model.filteredBranches.filter { !$0.current && !$0.remote }
    }

    /// Remote branches you do not already have locally; `origin/main` next
    /// to a local `main` is noise.
    private var remoteOnlyBranches: [HunGitBranch] {
        let localNames = Set(model.branches.filter { !$0.remote }.map(\.name))
        return model.filteredBranches.filter { branch in
            guard branch.remote else { return false }
            let shortName = branch.name.split(separator: "/", maxSplits: 1).last.map(String.init) ?? branch.name
            return !localNames.contains(shortName) && !branch.name.hasSuffix("/HEAD")
        }
    }

    /// Branches the keyboard moves through, in display order.
    private var switchableBranches: [HunGitBranch] {
        localBranches + remoteOnlyBranches
    }

    /// Leading inset of branch names, so section labels line up with them.
    static let textInset: CGFloat = 30
    private static let rowHeight: CGFloat = 31
    private static let maxListHeight: CGFloat = 340

    /// The list grows with its rows up to a cap, so short lists leave no
    /// empty panel.
    private var listHeight: CGFloat {
        var rows = localBranches.count + remoteOnlyBranches.count
        if currentBranch != nil { rows += 1 }
        if model.canCreateSearchedBranch { rows += 1 }
        var height = CGFloat(rows) * Self.rowHeight + 12
        if !remoteOnlyBranches.isEmpty { height += 29 }
        if isEmpty { height = 110 }
        return min(height, Self.maxListHeight)
    }

    private var isEmpty: Bool {
        currentBranch == nil && switchableBranches.isEmpty && !model.canCreateSearchedBranch
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            if let pendingBranch = model.pendingBranchSwitch {
                switchDecision(pendingBranch)
            } else if let error = model.errorMessage {
                errorBanner(error)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        if model.canCreateSearchedBranch {
                            createBranchRow
                        }
                        if let currentBranch {
                            branchRow(currentBranch)
                        }
                        ForEach(localBranches) { branchRow($0) }
                        if !remoteOnlyBranches.isEmpty {
                            Text("Remote")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(AppTheme.textTertiary)
                                .padding(.leading, Self.textInset)
                                .padding(.top, 10)
                                .padding(.bottom, 3)
                            ForEach(remoteOnlyBranches) { branchRow($0) }
                        }
                        if isEmpty {
                            Text(model.operation == .loadingBranches ? "Loading branches…" : "No branches match")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        }
                    }
                    .padding(6)
                }
                .hunScrollStyle()
                .frame(height: listHeight)
                .onChange(of: keyboardSelectionID) { _, selection in
                    guard let selection else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(selection, anchor: .center)
                    }
                }
            }

            Rectangle().fill(AppTheme.divider).frame(height: 1)
            footer
        }
        .frame(width: 440)
        .background(
            HunRoundedShape()
                .fill(AppTheme.dialogBackground)
        )
        .overlay(
            HunRoundedShape()
                .stroke(AppTheme.dividerStrong, lineWidth: 1)
        )
        .clipShape(HunRoundedShape())
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
            Task { await model.loadForPicker() }
        }
        .onDisappear {
            model.branchSearch = ""
            keyboardSelectionID = nil
        }
        .onExitCommand {
            model.cancelBranchPicker()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            TextField("Switch to a branch or create one", text: $model.branchSearch)
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
    }

    private func branchRow(_ branch: HunGitBranch) -> some View {
        HunBranchRow(
            name: branch.name,
            isCurrent: branch.current,
            isKeyboardSelected: keyboardSelectionID == branch.id,
            isDisabled: model.isBusy,
            onSelect: { switchToBranch(branch) }
        )
        .id(branch.id)
    }

    private var createBranchRow: some View {
        let name = model.branchSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return HunBranchRow(
            name: "Create branch “\(name)”",
            leadingSymbol: "plus",
            isDisabled: model.isBusy,
            onSelect: {
                Task {
                    if await model.createBranch(name) {
                        model.isBranchPickerPresented = false
                    }
                }
            }
        )
    }

    private func switchDecision(_ destination: String) -> some View {
        let count = model.status?.changeCount ?? 0
        let changes = count == 1 ? "1 uncommitted change" : "\(count) uncommitted changes"
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(changes). Stash \(count == 1 ? "it" : "them") to switch to \(destination)?")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Bring \(count == 1 ? "it" : "them") back later with git stash pop.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    model.cancelPendingBranchSwitch()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

                Button("Stash & switch") {
                    Task {
                        if await model.stashAndSwitchPendingBranch() {
                            model.isBranchPickerPresented = false
                        }
                    }
                }
                .buttonStyle(HunGitProminentButtonStyle())
                .font(.system(size: 11.5, weight: .medium))
            }
        }
        .padding(12)
        .background(AppTheme.warning.opacity(0.07))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.divider).frame(height: 1)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.danger)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.danger.opacity(0.06))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.divider).frame(height: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let status = model.status, status.isRepository {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let checked = HunGitRemoteCheckAge(
                        checkedAt: model.lastRemoteCheckAt,
                        relativeTo: context.date
                    ).shortDetail
                    Text([status.syncState.summary, checked].compactMap { $0 }.joined(separator: " · "))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            Button {
                Task { await model.fetch() }
            } label: {
                HStack(spacing: 5) {
                    if model.operation == .fetching {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text("Fetch")
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .help("Check the remote for new branches and commits without changing your files")
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
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
        guard !branch.current else { return }
        Task {
            if await model.switchBranch(branch.name) {
                model.isBranchPickerPresented = false
            }
        }
    }
}

/// One single-line row in the branch switcher.
private struct HunBranchRow: View {
    let name: String
    var leadingSymbol: String? = nil
    var isCurrent = false
    var isKeyboardSelected = false
    var isDisabled = false
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Always reserve the column so names line up.
                Image(systemName: isCurrent ? "checkmark" : (leadingSymbol ?? "checkmark"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .opacity(isCurrent || leadingSymbol != nil ? 1 : 0)
                    .frame(width: 14)

                Text(name)
                    .font(.system(size: 12.5, weight: isCurrent ? .medium : .regular))
                    .foregroundStyle(isCurrent ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                HunRoundedShape()
                    .fill(isKeyboardSelected || (hovering && !isCurrent) ? AppTheme.selection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        // The current branch is not a target, but stays fully legible.
        .allowsHitTesting(!isCurrent)
        .onHover { hovering = $0 }
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

private struct HunGitProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                HunRoundedShape()
                    .fill(AppTheme.accent.opacity(configuration.isPressed ? 0.72 : 0.92))
            )
    }
}
