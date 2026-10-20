import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(HunStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sidebarSearch = ""
    @State private var logSearch = ""
    @State private var sidebarDocked = true
    @State private var sidebarRevealed = false
    @State private var sidebarRevealShowTask: Task<Void, Never>?
    @State private var sidebarRevealHideTask: Task<Void, Never>?
    @State private var collapsedSections: Set<String> = []
    /// The Settings section on screen; nil shows the projects.
    @State private var settingsSection: HunSettingsSection?
    @State private var terminalController = HunTerminalController()
    @State private var branchSwitcher = HunBranchModel()
    @FocusState private var sidebarSearchFocused: Bool
    @AppStorage(HunLayout.roundedPanelsKey) private var roundedPanels = HunLayout.roundedPanelsDefault
    @AppStorage(HunSidebarMetrics.preferenceKey) private var sidebarWidthPreference = HunSidebarMetrics.defaultWidth
    private var sidebarWidth: CGFloat { HunSidebarMetrics.clamp(sidebarWidthPreference) }

    /// With the rounded layout the sidebar tone frames the window and the
    /// main pane sits on it as a rounded card.
    private var canvas: Color {
        roundedPanels ? AppTheme.sidebar : AppTheme.appBackground
    }

    private var model: HunDashboardModel { store.model }

    private var activeProject: HunProject? {
        model.projects.first { $0.id == store.selectedProjectID }
    }

    private var openProjects: [HunProject] {
        store.openTabIDs.compactMap { id in model.projects.first { $0.id == id } }
    }

    private var workspaceGroups: [(name: String, projects: [HunProject])] {
        let grouped = Dictionary(grouping: model.projects) { project -> String in
            let parts = project.path.split(separator: "/")
            guard parts.count >= 2 else { return "Projects" }
            return String(parts[parts.count - 2])
        }
        return grouped
            .map { (humanize($0.key), $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        @Bindable var store = store
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if sidebarDocked {
                    sidebar(docked: true)
                        .frame(width: sidebarWidth)
                        .background(AppTheme.sidebar)
                        .clipped()
                        .zIndex(1)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .topLeading) {
                if sidebarDocked {
                    // Centred on the gap between the sidebar and the card (or
                    // on the divider in the classic layout).
                    HunSidebarResizeHandle(preferredWidth: $sidebarWidthPreference, showsDivider: !roundedPanels)
                        .frame(maxHeight: .infinity)
                        .offset(x: sidebarWidth + (roundedPanels ? HunLayout.shellInset / 2 : -0.5) - HunWorkspacePanelMetrics.splitterWidth / 2)
                }
            }

            if !sidebarDocked {
                sidebarRevealLayer
            }

            if branchSwitcher.isBranchPickerPresented {
                HunGitBranchDialogOverlay(model: branchSwitcher)
                    .zIndex(20)
            }
        }
        .background(canvas)
        .background(WindowChromeConfigurator())
        .background(
            WindowInteractionMonitor(
                onToggleSidebar: toggleSidebar,
                onFocusProjectSearch: focusProjectSearch,
                onOpenSettings: openSettings,
                onClearProjectSearchFocus: clearProjectSearchFocus
            )
        )
        .ignoresSafeArea(.container, edges: .top)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: sidebarDocked)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: sidebarRevealed)
        .animation(.easeOut(duration: 0.14), value: branchSwitcher.isBranchPickerPresented)
        // A branch switched from Hun shows in the header without waiting for the next poll.
        .onChange(of: branchSwitcher.status?.branch) { _, _ in
            store.refreshNow()
        }
        .focusedSceneValue(
            \.hunTerminalCommand,
            HunTerminalCommandAction(
                canToggle: activeProject != nil,
                canClear: terminalController.isPresented && terminalController.activeSession != nil,
                toggle: toggleTerminal,
                clear: terminalController.clearActiveTerminal
            )
        )
        .task {
            await store.refresh(force: true)
        }
        .onChange(of: store.selectedProjectID) { _, projectID in
            settingsSection = nil
            guard let projectID,
                  let project = model.projects.first(where: { $0.id == projectID })
            else {
                terminalController.hide()
                return
            }
            terminalController.projectDidChange(
                HunTerminalProjectContext(
                    id: project.id,
                    name: project.name,
                    rootPath: project.path
                )
            )
        }
        .onChange(of: model.projects.map(\.id)) { _, projectIDs in
            terminalController.pruneSessions(validProjectIDs: Set(projectIDs))
        }
        .onDisappear {
            terminalController.shutdown()
        }
        .sheet(item: $store.configEditor) { target in
            HunConfigEditorSheet(
                target: target,
                validate: { await store.configProblem(in: $0) },
                save: { await store.saveConfig($0, for: target) }
            )
        }
    }

    private var mainContent: some View {
        @Bindable var store = store
        let mode = Binding(
            get: { store.displayedMode },
            set: { store.changeMode($0, preferredProject: store.selectedProjectID) }
        )
        // Even margins: the card keeps the same inset from the sidebar as from
        // the window's other edges.
        return VStack(spacing: 0) {
            // Top bar (tabs, DEV badge, Focus/Multitask) hidden while trying the
            // layout without it; uncomment to bring it back.
            // TopBarView(
            //     openProjects: openProjects,
            //     activeID: $store.selectedProjectID,
            //     mode: mode,
            //     isModePending: store.isChangingMode,
            //     showSidebarControl: !sidebarDocked,
            //     onSelect: selectProjectTab,
            //     onClose: closeTab,
            //     onToggleSidebar: dockSidebar
            // )
            // // Refined layout: the tabs sit on the window above the card, lined up with its edges.
            // .padding(.leading, roundedPanels ? HunLayout.shellInset : 0)
            // .padding(.trailing, roundedPanels ? HunLayout.shellInset : 0)
            // .background(roundedPanels ? Color.clear : AppTheme.appBackground)

            // With the top bar hidden, a collapsed sidebar still needs room for
            // the traffic lights and a way back.
            if !sidebarDocked {
                HStack(spacing: 2) {
                    Spacer().frame(width: 72) // traffic light reservation
                    ToolbarIconButton(
                        systemImage: "sidebar.left",
                        helpText: "Show sidebar",
                        action: dockSidebar
                    )
                    Spacer()
                }
                .frame(height: 38)
            }

            VStack(spacing: 0) {
                if !roundedPanels {
                    Rectangle().fill(AppTheme.divider).frame(height: 1)
                }

                if let lastError = store.lastError {
                    ErrorBanner(
                        message: lastError,
                        actionTitle: store.portConflict == nil ? nil : "Stop it & retry",
                        onAction: { store.resolvePortConflict() },
                        onDismiss: { store.clearLastError() }
                    )
                    Rectangle().fill(AppTheme.divider).frame(height: 1)
                }

                Group {
                    if let section = settingsSection {
                        HunSettingsPage(section: section, onClose: closeSettings)
                    } else if let project = activeProject {
                        projectWorkspace(project)
                    } else {
                        EmptyStateView(
                            projectCount: model.projects.count,
                            isRecovering: store.isRecoveringServices,
                            onRefresh: { store.refreshNow() }
                        )
                    }
                }
                .id(settingsSection.map { "settings:\($0.rawValue)" } ?? store.selectedProjectID)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.selectedProjectID)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: settingsSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Refined layout: the project header sits on the window body;
                // only services and logs form the card (see ProjectDetailView).
                .background(roundedPanels ? Color.clear : AppTheme.appBackground)
            }
        }
        .padding(.leading, sidebarDocked || roundedPanels ? 0 : 8)
    }

    private func projectWorkspace(_ project: HunProject) -> some View {
        @Bindable var store = store
        @Bindable var terminalController = terminalController

        return GeometryReader { proxy in
            VStack(spacing: 0) {
                ProjectDetailView(
                    project: project,
                    onOpenBranchSwitcher: { branchSwitcher.isBranchPickerPresented = true },
                    mode: store.globalMode,
                    pendingAction: store.projectAction(for: project),
                    logSearch: $logSearch,
                    selectedServiceID: $store.selectedServiceID,
                    selectedLogScope: $store.selectedLogScope,
                    logFeed: store.logFeed,
                    onFocus: { store.focus(project) },
                    onRun: { store.run(project) },
                    onRunProfile: { profile in store.run(project, profile: profile) },
                    onSaveProfile: { name in store.saveRunningServicesAsProfile(named: name, for: project) },
                    onRestart: { store.restart(project) },
                    onStop: { store.stop(project) },
                    onOpenConfig: { store.openConfig(for: project) },
                    onChooseLogo: { store.chooseLogo(for: project) },
                    onClearLogo: { store.clearLogo(for: project) },
                    onCopyAgentPrompt: { store.copyAgentPrompt(for: project) },
                    onClearLogs: { store.clearLogs(for: project) },
                    onRunService: { service in store.run(service, in: project) },
                    onRestartService: { service in store.restart(service, in: project) },
                    onStopService: { service in store.stop(service, in: project) },
                    onRemoveService: { service in store.remove(service, from: project) },
                    onStopHolderAndRun: { service in store.stopHolderAndRun(service, in: project) },
                    isServiceBusy: { service in store.serviceAction(for: service, in: project) != nil }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if terminalController.isPresented,
                   let session = terminalController.activeSession
                {
                    HunTerminalPanel(
                        session: session,
                        preferredHeight: $terminalController.panelHeight,
                        availableHeight: proxy.size.height,
                        onClose: terminalController.hide
                    )
                    .frame(
                        height: HunTerminalPanelMetrics.clamp(
                            terminalController.panelHeight,
                            availableHeight: proxy.size.height
                        )
                    )
                    .hunRoundedShell(roundedPanels, leadingInset: HunLayout.shellInset, topInset: 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: terminalController.isPresented
            )
            .onAppear { branchSwitcher.select(projectID: project.id) }
            .onChange(of: project.id) { _, id in branchSwitcher.select(projectID: id) }
        }
    }

    private func openSettings() {
        if settingsSection == nil {
            settingsSection = .appearance
        }
    }

    private func closeSettings() {
        settingsSection = nil
    }

    @ViewBuilder
    private func sidebar(docked: Bool) -> some View {
        if let section = settingsSection {
            VStack(spacing: 0) {
                SidebarTitlebarChrome(
                    docked: docked,
                    onToggleSidebar: { if docked { collapseSidebar() } else { dockSidebar() } }
                )
                .frame(height: 44)
                HunSettingsNavigation(
                    selection: Binding(get: { section }, set: { settingsSection = $0 }),
                    onBack: closeSettings
                )
                SidebarUpdateSlot()
                SidebarFooter(onSettings: closeSettings)
            }
        } else {
            projectSidebar(docked: docked)
        }
    }

    private func projectSidebar(docked: Bool) -> some View {
        SidebarColumnView(
            docked: docked,
            searchText: $sidebarSearch,
            searchFocused: $sidebarSearchFocused,
            workspaceGroups: workspaceGroups,
            activeID: store.selectedProjectID ?? "",
            collapsedSections: $collapsedSections,
            onSelectProject: openProject,
            onToggleSidebar: { if docked { collapseSidebar() } else { dockSidebar() } },
            onSettings: openSettings,
            unmanaged: store.model.unmanaged,
            onStopUnmanaged: { process in store.stop(process) },
            onAddUnmanaged: { process in store.addProject(from: process) },
            onRemoveProject: { project in store.remove(project) }
        )
    }

    private var sidebarRevealLayer: some View {
        ZStack(alignment: .topLeading) {
            if sidebarRevealed {
                sidebar(docked: false)
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background(AppTheme.sidebar)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(AppTheme.divider).frame(width: 1)
                    }
                    .onHover { setSidebarReveal($0) }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)
            }

            // Edge trigger stays on top so the panel never covers it. That keeps
            // hover tracking stable while the panel slides in/out and prevents the
            // reveal state from oscillating.
            Color.clear
                .frame(width: 12)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { setSidebarReveal($0) }
                .zIndex(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func setSidebarReveal(_ hovering: Bool) {
        if hovering {
            // Cancel any pending hide; the cursor is back over the edge/panel.
            sidebarRevealHideTask?.cancel()
            sidebarRevealHideTask = nil
            guard !sidebarRevealed, sidebarRevealShowTask == nil else { return }
            // Require a brief dwell before revealing so a quick pass across the
            // edge (or moving the cursor in/out of the window) doesn't flicker.
            sidebarRevealShowTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                sidebarRevealShowTask = nil
                sidebarRevealed = true
            }
        } else {
            // A pending reveal that never matured is cancelled outright.
            sidebarRevealShowTask?.cancel()
            sidebarRevealShowTask = nil
            guard sidebarRevealed else { return }
            sidebarRevealHideTask?.cancel()
            sidebarRevealHideTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                sidebarRevealHideTask = nil
                sidebarRevealed = false
            }
        }
    }

    private func cancelSidebarRevealTasks() {
        sidebarRevealShowTask?.cancel()
        sidebarRevealShowTask = nil
        sidebarRevealHideTask?.cancel()
        sidebarRevealHideTask = nil
    }

    private func openProject(_ id: String) {
        store.selectProject(id)
    }

    private func selectProjectTab(_ id: String) {
        store.selectProject(id)
    }

    private func closeTab(_ id: String) {
        store.closeTab(id)
    }

    private func dockSidebar() {
        cancelSidebarRevealTasks()
        sidebarRevealed = false
        sidebarDocked = true
    }

    private func collapseSidebar() {
        cancelSidebarRevealTasks()
        sidebarSearchFocused = false
        sidebarDocked = false
        sidebarRevealed = false
    }

    private func toggleSidebar() {
        if sidebarDocked {
            collapseSidebar()
        } else {
            dockSidebar()
        }
    }

    private func toggleTerminal() {
        guard let project = activeProject else { return }
        terminalController.toggle(
            project: HunTerminalProjectContext(
                id: project.id,
                name: project.name,
                rootPath: project.path
            )
        )
    }

    private func focusProjectSearch() {
        cancelSidebarRevealTasks()
        sidebarRevealed = false
        sidebarDocked = true
        DispatchQueue.main.async {
            sidebarSearchFocused = true
        }
    }

    private func clearProjectSearchFocus() {
        sidebarSearchFocused = false
    }

    private func humanize(_ s: String) -> String {
        s.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

// MARK: - Sidebar

private struct SidebarColumnView: View {
    let docked: Bool
    @Binding var searchText: String
    let searchFocused: FocusState<Bool>.Binding
    let workspaceGroups: [(name: String, projects: [HunProject])]
    let activeID: String
    @Binding var collapsedSections: Set<String>
    let onSelectProject: (String) -> Void
    let onToggleSidebar: () -> Void
    let onSettings: () -> Void
    let unmanaged: [HunUnmanagedProcess]
    let onStopUnmanaged: (HunUnmanagedProcess) -> Void
    let onAddUnmanaged: (HunUnmanagedProcess) -> Void
    let onRemoveProject: (HunProject) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SidebarTitlebarChrome(
                docked: docked,
                onToggleSidebar: onToggleSidebar
            )
            .frame(height: 44)

            SidebarView(
                searchText: $searchText,
                searchFocused: searchFocused,
                workspaceGroups: workspaceGroups,
                activeID: activeID,
                collapsedSections: $collapsedSections,
                onSelectProject: onSelectProject,
                onSettings: onSettings,
                unmanaged: unmanaged,
                onStopUnmanaged: onStopUnmanaged,
                onAddUnmanaged: onAddUnmanaged,
                onRemoveProject: onRemoveProject
            )
        }
    }
}

private struct SidebarTitlebarChrome: View {
    let docked: Bool
    let onToggleSidebar: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 72) // traffic light reservation
            Spacer(minLength: 0)
            ToolbarIconButton(
                systemImage: "sidebar.left",
                helpText: docked ? "Hide sidebar" : "Dock sidebar",
                action: onToggleSidebar
            )
            .padding(.trailing, 6)
        }
    }
}

/// One grid for the sidebar. Rows sit `inset` from the sidebar edges, the
/// same margin as the rounded card. Column A (inset + rowPadding) holds the
/// search icon, Add project, section icons and the footer; column B (+ the
/// nested indent) holds project icons, lining up under section titles.
enum SidebarMetrics {
    static let inset: CGFloat = 10
    static let rowPadding: CGFloat = 8
    static let nestedIndent: CGFloat = 22
    static let rowHeight: CGFloat = 30
    static let sectionHeaderHeight: CGFloat = 28
    static let radius: CGFloat = HunLayout.radius
    static let sectionSpacing: CGFloat = 14
}

private struct SidebarView: View {
    @Binding var searchText: String
    let searchFocused: FocusState<Bool>.Binding
    let workspaceGroups: [(name: String, projects: [HunProject])]
    let activeID: String
    @Binding var collapsedSections: Set<String>
    let onSelectProject: (String) -> Void
    let onSettings: () -> Void
    let unmanaged: [HunUnmanagedProcess]
    let onStopUnmanaged: (HunUnmanagedProcess) -> Void
    let onAddUnmanaged: (HunUnmanagedProcess) -> Void
    let onRemoveProject: (HunProject) -> Void

    private static let elsewhereSectionID = "__running_elsewhere__"

    private var allProjects: [HunProject] {
        workspaceGroups.flatMap { $0.projects }
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarSearchField(text: $searchText, isFocused: searchFocused)
                .padding(.horizontal, SidebarMetrics.inset)
                .padding(.top, SidebarMetrics.inset)
                .padding(.bottom, 6)

            AddProjectButton()
                .padding(.horizontal, SidebarMetrics.inset)
                .padding(.bottom, SidebarMetrics.inset)

            ScrollView {
                VStack(alignment: .leading, spacing: SidebarMetrics.sectionSpacing) {
                    ForEach(workspaceGroups, id: \.name) { group in
                        section(
                            id: group.name,
                            title: group.name,
                            projects: filtered(group.projects)
                        )
                    }
                    if !unmanaged.isEmpty {
                        runningElsewhereSection
                    }
                }
                .padding(.horizontal, SidebarMetrics.inset)
                .padding(.top, 2)
                .padding(.bottom, 16)
            }
            .hunScrollStyle()

            SidebarUpdateSlot()
            SidebarFooter(onSettings: onSettings)
        }
    }

    private func filtered(_ projects: [HunProject]) -> [HunProject] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return projects }
        return projects.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
                $0.path.localizedCaseInsensitiveContains(q)
        }
    }

    @ViewBuilder
    private func section(id: String, title: String, projects: [HunProject]) -> some View {
        let collapsed = collapsedSections.contains(id)
        VStack(alignment: .leading, spacing: 1) {
            SidebarSectionHeader(
                title: title,
                isCollapsed: collapsed,
                onToggle: { withAnimation(.easeOut(duration: 0.15)) { toggle(id) } }
            )
            if !collapsed {
                VStack(spacing: 2) {
                    ForEach(projects) { project in
                        SidebarProjectRow(
                            project: project,
                            selected: project.id == activeID,
                            onTap: { onSelectProject(project.id) },
                            onRemove: { onRemoveProject(project) }
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// Dev servers Hun can see but no registered service accounts for.
    @ViewBuilder
    private var runningElsewhereSection: some View {
        let id = Self.elsewhereSectionID
        let collapsed = collapsedSections.contains(id)
        VStack(alignment: .leading, spacing: 1) {
            SidebarSectionHeader(
                title: "Running elsewhere",
                isCollapsed: collapsed,
                onToggle: { withAnimation(.easeOut(duration: 0.15)) { toggle(id) } }
            )
            if !collapsed {
                VStack(spacing: 2) {
                    ForEach(unmanaged) { process in
                        UnmanagedProcessRow(
                            process: process,
                            onStop: { onStopUnmanaged(process) },
                            onAddProject: process.project == nil ? { onAddUnmanaged(process) } : nil
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func toggle(_ id: String) {
        if collapsedSections.contains(id) {
            collapsedSections.remove(id)
        } else {
            collapsedSections.insert(id)
        }
    }
}

/// Pinned to the sidebar's bottom: the Focus/Multitask switch, the DEV badge
/// on development builds, and Settings.
private struct SidebarFooter: View {
    let onSettings: () -> Void
    @Environment(HunStore.self) private var store
    @AppStorage(HunLayout.roundedPanelsKey) private var roundedPanels = HunLayout.roundedPanelsDefault

    var body: some View {
        HStack(spacing: 6) {
            ModeMenuButton()
            Spacer(minLength: 4)
            #if DEBUG
            DevBuildBadge()
            #endif
            ToolbarIconButton(
                systemImage: "gearshape",
                helpText: "Settings (⌘,)",
                action: onSettings
            )
            .accessibilityLabel("Open Settings")
        }
        .padding(.leading, SidebarMetrics.inset)
        .padding(.trailing, SidebarMetrics.inset + 2)
        .padding(.vertical, roundedPanels ? SidebarMetrics.inset : 6)
        .overlay(alignment: .top) {
            if !roundedPanels {
                Rectangle().fill(AppTheme.divider).frame(height: 1)
            }
        }
    }
}

/// The current run mode as a quiet sidebar row; its menu switches modes.
/// The icon sits on the sidebar's icon column.
private struct ModeMenuButton: View {
    @Environment(HunStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let mode = store.displayedMode
        Menu {
            Picker("Mode", selection: Binding(
                get: { store.displayedMode },
                set: { store.changeMode($0, preferredProject: store.selectedProjectID) }
            )) {
                ForEach(HunMode.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.icon).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14)
                Text(mode.title)
                    .font(.system(size: 12.5, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
            .padding(.horizontal, SidebarMetrics.rowPadding)
            .frame(height: 28)
            .background(HunRoundedShape().fill(hovering ? AppTheme.rowHover : Color.clear))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(store.isChangingMode)
        .onHover { hovering = $0 }
        .help(mode.helpText)
    }
}

private struct SidebarSearchField: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        HunSearchField(
            text: $text,
            placeholder: "Search",
            height: SidebarMetrics.rowHeight,
            fontSize: 12,
            isFocused: isFocused
        )
    }
}

/// The app's search field. The placeholder is drawn behind the text field
/// rather than being its own: a plain text field shifts its placeholder when
/// editing starts. A hairline ring shows while it has focus.
struct HunSearchField: View {
    @Binding var text: String
    let placeholder: String
    var height: CGFloat
    var fontSize: CGFloat
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: fontSize - 1, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: fontSize))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: fontSize))
                    .foregroundStyle(AppTheme.textPrimary)
                    .focused(isFocused)
                    .accessibilityLabel(placeholder)
            }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: fontSize - 1))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(
            HunRoundedShape()
                .fill(AppTheme.selectedFill)
        )
        .overlay(
            HunRoundedShape()
                .strokeBorder(isFocused.wrappedValue ? AppTheme.dividerStrong : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = true }
        .animation(.easeOut(duration: 0.12), value: isFocused.wrappedValue)
    }
}

private struct ErrorBanner: View {
    let message: String
    var actionTitle: String? = nil
    var onAction: () -> Void = {}
    let onDismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.warning)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let actionTitle {
                InlineActionButton(title: actionTitle, action: onAction)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textTertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(AppTheme.warning.opacity(0.08))
    }
}

/// A compact text button for actions inside banners and rows.
private struct InlineActionButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(
                HunRoundedShape()
                    .fill(hovering ? AppTheme.hover : AppTheme.selection)
            )
            .onHover { hovering = $0 }
    }
}

/// The update card at the bottom of the sidebar, shown only when an update
/// is ready.
private struct SidebarUpdateSlot: View {
    @Environment(HunUpdater.self) private var updater

    var body: some View {
        if let update = updater.availableUpdate {
            HunSidebarUpdateCard(
                version: update.version,
                onViewChanges: { updater.openChangelog(for: update) },
                onUpdate: updater.checkForUpdates
            )
            .padding(.horizontal, SidebarMetrics.inset)
            .padding(.bottom, 4)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

/// One compact line: the version (which opens the changelog) and Update.
struct HunSidebarUpdateCard: View {
    let version: String
    let onViewChanges: () -> Void
    let onUpdate: () -> Void
    @State private var hoveringChanges = false
    @State private var hoveringUpdate = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppTheme.success)
                .frame(width: 6, height: 6)
                .shadow(color: AppTheme.success.opacity(0.55), radius: 3)
                .accessibilityHidden(true)

            Button(action: onViewChanges) {
                // Drops "is ready" in a narrow sidebar rather than truncating.
                ViewThatFits(in: .horizontal) {
                    label("Hun \(version) is ready")
                    label("Hun \(version)")
                }
            }
            .buttonStyle(.plain)
            .onHover { hoveringChanges = $0 }
            .help("View what's new in Hun \(version)")

            Spacer(minLength: 6)

            // A download arrow in the app's rounded shell.
            Button(action: onUpdate) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.updateActionText)
                    .frame(width: 18, height: 18)
                    .background(
                        HunRoundedShape()
                            .fill(hoveringUpdate ? AppTheme.updateActionFillHover : AppTheme.updateActionFill)
                    )
                    // A larger hit area than the shell itself.
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringUpdate = $0 }
            .help("Update to Hun \(version)")
            .accessibilityLabel("Update to Hun \(version)")
            .accessibilityHint("Downloads and installs Hun \(version)")
        }
        .padding(.leading, 11)
        .padding(.trailing, 4)
        .frame(height: 32)
        // The original banner's quiet green tint, with a border as subtle.
        .background(HunRoundedShape().fill(AppTheme.success.opacity(0.055)))
        .overlay(HunRoundedShape().strokeBorder(AppTheme.success.opacity(0.16), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hun \(version) is available")
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
            .underline(hoveringChanges, color: AppTheme.textTertiary)
            .lineLimit(1)
            .fixedSize()
    }
}

private struct UnmanagedProcessRow: View {
    let process: HunUnmanagedProcess
    let onStop: () -> Void
    let onAddProject: (() -> Void)?
    @State private var hovering = false

    private var url: URL? {
        URL(string: "http://localhost:\(process.port)")
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppTheme.success.opacity(0.7))
                .frame(width: 6, height: 6)
                .frame(width: 17)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(process.command) :\(process.port)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(process.project.map { "\($0) · not in .hun.yml" } ?? HunPortHolder.abbreviate(process.cwd))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 4)
            if hovering {
                if let url {
                    ToolbarIconButton(systemImage: "arrow.up.right", helpText: "Open \(url.absoluteString)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                ToolbarIconButton(systemImage: "stop.fill", helpText: "Stop this process", action: onStop)
            }
        }
        .padding(.leading, SidebarMetrics.rowPadding + SidebarMetrics.nestedIndent)
        .padding(.trailing, SidebarMetrics.rowPadding)
        .padding(.vertical, 5)
        .background(
            HunRoundedShape()
                .fill(hovering ? AppTheme.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(Text(verbatim: "pid \(process.pid) · \(process.cwd)"))
        .contextMenu {
            if let url {
                Button("Open \(url.absoluteString)") { NSWorkspace.shared.open(url) }
            }
            if let onAddProject {
                Button("Add Project to Hun…", action: onAddProject)
            }
            Divider()
            Button("Stop Process", role: .destructive, action: onStop)
        }
    }
}

private struct SidebarSectionHeader: View {
    let title: String
    let isCollapsed: Bool
    let onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "folder" : "folder.fill")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer(minLength: 4)
                // The disclosure chevron sits at the trailing edge so it never
                // shifts the icon and title off their column.
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .opacity(hovering || isCollapsed ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: hovering)
            }
            .padding(.horizontal, SidebarMetrics.rowPadding)
            .frame(height: SidebarMetrics.sectionHeaderHeight)
            .background(
                HunRoundedShape()
                    .fill(hovering ? AppTheme.hover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SidebarProjectRow: View {
    let project: HunProject
    let selected: Bool
    let onTap: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false
    @State private var confirmingRemoval = false

    var body: some View {
        Button(action: onTap) {
            // Room for the running ring that sits just outside the icon.
            HStack(spacing: 10) {
                ProjectIconView(
                    name: project.name,
                    iconPath: project.iconPath,
                    size: 17,
                    cornerRadius: 4,
                    emphasized: selected,
                    status: project.status
                )

                Text(project.name)
                    .font(.system(size: 13))
                    .foregroundStyle(textColor)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, SidebarMetrics.rowPadding + SidebarMetrics.nestedIndent)
            .padding(.trailing, SidebarMetrics.rowPadding)
            .frame(height: SidebarMetrics.rowHeight)
            .background(
                HunRoundedShape()
                    .fill(rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(project.name)\n\(project.path)")
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)])
            }
            Divider()
            Button("Remove from Hun…", role: .destructive) { confirmingRemoval = true }
        }
        .confirmationDialog(
            "Remove \(project.name) from Hun?",
            isPresented: $confirmingRemoval
        ) {
            Button("Remove", role: .destructive, action: onRemove)
        } message: {
            Text("Hun stops its services and stops listing it. The folder and its .hun.yml are not touched; add it again any time.")
        }
    }

    private var textColor: Color {
        if selected { return AppTheme.textPrimary }
        if hovering { return AppTheme.textPrimary }
        return AppTheme.textSecondary
    }

    private var rowBackground: Color {
        if selected { return AppTheme.selectedFill }
        if hovering { return AppTheme.rowHover }
        return .clear
    }
}

// MARK: - Top Bar

private struct TopBarView: View {
    let openProjects: [HunProject]
    @Binding var activeID: String?
    @Binding var mode: HunMode
    let isModePending: Bool
    let showSidebarControl: Bool
    let onSelect: (String) -> Void
    let onClose: (String) -> Void
    let onToggleSidebar: () -> Void
    @AppStorage(HunLayout.roundedPanelsKey) private var roundedPanels = HunLayout.roundedPanelsDefault

    var body: some View {
        HStack(spacing: 10) {
            if showSidebarControl {
                HStack(spacing: 2) {
                    Spacer().frame(width: 72) // traffic light reservation
                    ToolbarIconButton(
                        systemImage: "sidebar.left",
                        helpText: "Show sidebar",
                        action: onToggleSidebar
                    )
                }
                .transition(.opacity)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(openProjects) { project in
                        ProjectTabView(
                            project: project,
                            active: project.id == activeID,
                            canClose: openProjects.count > 1,
                            onTap: { onSelect(project.id) },
                            onClose: { onClose(project.id) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.leading, showSidebarControl ? 4 : 20)

            Spacer(minLength: 0)

            #if DEBUG
            DevBuildBadge()
            #endif

            ModeSelector(mode: $mode, isPending: isModePending)
        }
        .padding(.trailing, roundedPanels ? 4 : 12)
        .frame(height: roundedPanels ? HunLayout.tabBarHeight : 44)
    }
}

/// Marks development builds, which use an isolated daemon and data.
private struct DevBuildBadge: View {
    var body: some View {
        Text("DEV")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(AppTheme.accent.opacity(0.24))
            .clipShape(HunRoundedShape())
            .overlay {
                HunRoundedShape()
                    .stroke(AppTheme.accent.opacity(0.42), lineWidth: 1)
            }
            .help("Development build · isolated daemon and data")
    }
}

private struct ModeSelector: View {
    @Binding var mode: HunMode
    let isPending: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HunMode.allCases, id: \.self) { option in
                modeButton(option)
            }
        }
        .padding(2)
        .background(
            HunRoundedShape()
                .fill(AppTheme.searchField)
        )
        .help(mode.helpText)
        .disabled(isPending)
    }

    private func modeButton(_ option: HunMode) -> some View {
        let active = mode == option
        return Button {
            withAnimation(.easeOut(duration: 0.14)) { mode = option }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.icon)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(option.title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(active ? AppTheme.textPrimary : AppTheme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                HunRoundedShape()
                    .fill(active ? AppTheme.modeSelectorActive : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: view.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
    }
}

private struct WindowInteractionMonitor: NSViewRepresentable {
    let onToggleSidebar: () -> Void
    let onFocusProjectSearch: () -> Void
    let onOpenSettings: () -> Void
    let onClearProjectSearchFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onToggleSidebar: onToggleSidebar,
            onFocusProjectSearch: onFocusProjectSearch,
            onOpenSettings: onOpenSettings,
            onClearProjectSearchFocus: onClearProjectSearchFocus
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onToggleSidebar = onToggleSidebar
        context.coordinator.onFocusProjectSearch = onFocusProjectSearch
        context.coordinator.onOpenSettings = onOpenSettings
        context.coordinator.onClearProjectSearchFocus = onClearProjectSearchFocus
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    final class Coordinator {
        var onToggleSidebar: () -> Void
        var onFocusProjectSearch: () -> Void
        var onOpenSettings: () -> Void
        var onClearProjectSearchFocus: () -> Void

        private weak var view: NSView?
        private var monitor: Any?

        init(
            onToggleSidebar: @escaping () -> Void,
            onFocusProjectSearch: @escaping () -> Void,
            onOpenSettings: @escaping () -> Void,
            onClearProjectSearchFocus: @escaping () -> Void
        ) {
            self.onToggleSidebar = onToggleSidebar
            self.onFocusProjectSearch = onFocusProjectSearch
            self.onOpenSettings = onOpenSettings
            self.onClearProjectSearchFocus = onClearProjectSearchFocus
        }

        deinit {
            invalidate()
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func invalidate() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let view, event.window === view.window else { return event }

            switch event.type {
            case .keyDown:
                return handleKeyDown(event)
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                onClearProjectSearchFocus()
                endTextEditingIfClickedOutside(event)
                return event
            default:
                return event
            }
        }

        /// Clicking outside the text field being edited ends editing, as in
        /// native apps; SwiftUI fields otherwise keep focus.
        private func endTextEditingIfClickedOutside(_ event: NSEvent) {
            guard let window = event.window,
                  let editor = window.firstResponder as? NSTextView,
                  editor.isFieldEditor,
                  let field = editor.delegate as? NSView
            else { return }
            let point = field.convert(event.locationInWindow, from: nil)
            if !field.bounds.contains(point) {
                window.makeFirstResponder(nil)
            }
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers == .command,
                  let key = event.charactersIgnoringModifiers?.lowercased()
            else {
                return event
            }

            switch key {
            case "b":
                onToggleSidebar()
                return nil
            case "p":
                onFocusProjectSearch()
                return nil
            case ",":
                onOpenSettings()
                return nil
            default:
                return event
            }
        }
    }
}

private struct ProjectTabView: View {
    let project: HunProject
    let active: Bool
    let canClose: Bool
    let onTap: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Text(project.name)
                .font(.system(size: 12, weight: active ? .medium : .regular))
                .foregroundStyle(active ? AppTheme.textPrimary : AppTheme.textSecondary)
                .lineLimit(1)

            if canClose && (hovering || active) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 14, height: 14)
                        .background(
                            HunRoundedShape().fill(hovering ? AppTheme.dividerStrong : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if canClose {
                Spacer().frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            HunRoundedShape()
                .fill(active ? AppTheme.tabActive : (hovering ? AppTheme.hover : Color.clear))
        )
        .overlay(
            HunRoundedShape()
                .stroke(active ? AppTheme.divider : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
    }
}

struct ToolbarIconButton: View {
    let systemImage: String
    var helpText: String? = nil
    var isActive = false
    var isDisabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 26, height: 26)
                .background(
                    HunRoundedShape()
                        .fill(buttonBackground)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering = $0 }
        .help(helpText ?? "")
    }

    private var iconColor: Color {
        if isDisabled { return AppTheme.textTertiary.opacity(0.45) }
        if isActive || hovering { return AppTheme.textPrimary }
        return AppTheme.textTertiary
    }

    private var buttonBackground: Color {
        if isActive { return AppTheme.tabActive }
        if hovering && !isDisabled { return AppTheme.hover }
        return .clear
    }
}

// MARK: - Project Detail

private struct ProjectDetailView: View {
    @AppStorage(HunWorkspacePanelPreference.servicesWidth)
    private var servicesPanelWidth = Double(HunWorkspacePanelMetrics.servicesDefaultWidth)
    @AppStorage(HunLayout.roundedPanelsKey) private var roundedPanels = HunLayout.roundedPanelsDefault

    let project: HunProject
    let onOpenBranchSwitcher: () -> Void
    let mode: HunMode
    let pendingAction: HunActionKind?
    @Binding var logSearch: String
    @Binding var selectedServiceID: String?
    @Binding var selectedLogScope: LogScope
    let logFeed: HunLogFeed
    let onFocus: () -> Void
    let onRun: () -> Void
    let onRunProfile: (String?) -> Void
    let onSaveProfile: (String) -> Void
    let onRestart: () -> Void
    let onStop: () -> Void
    let onOpenConfig: () -> Void
    let onChooseLogo: () -> Void
    let onClearLogo: () -> Void
    let onCopyAgentPrompt: () -> Void
    let onClearLogs: () -> Void
    let onRunService: (HunService) -> Void
    let onRestartService: (HunService) -> Void
    let onStopService: (HunService) -> Void
    let onRemoveService: (HunService) -> Void
    let onStopHolderAndRun: (HunService) -> Void
    let isServiceBusy: (HunService) -> Bool

    private var selectedService: HunService? {
        project.services.first { $0.id == selectedServiceID }
    }

    var body: some View {
        VStack(spacing: 0) {
            ProjectHeaderView(
                project: project,
                onOpenBranchSwitcher: onOpenBranchSwitcher,
                mode: mode,
                pendingAction: pendingAction,
                onFocus: onFocus,
                onRun: onRun,
                onRunProfile: onRunProfile,
                onSaveProfile: onSaveProfile,
                onRestart: onRestart,
                onStop: onStop,
                onOpenConfig: onOpenConfig,
                onChooseLogo: onChooseLogo,
                onClearLogo: onClearLogo,
                onCopyAgentPrompt: onCopyAgentPrompt
            )

            if !roundedPanels {
                Rectangle().fill(AppTheme.divider).frame(height: 1)
            }

            HunResizableWorkspaceSplit(
                preferredWidth: $servicesPanelWidth,
                accessibilityLabel: "Resize services panel"
            ) {
                ServicesPanelView(
                    services: project.services,
                    profileName: project.profile,
                    profileServices: project.profileServices,
                    selectedID: $selectedServiceID,
                    selectedScope: $selectedLogScope,
                    onOpenConfig: onOpenConfig,
                    onRun: onRunService,
                    onRestart: onRestartService,
                    onStop: onStopService,
                    onRemove: onRemoveService,
                    onStopHolderAndRun: onStopHolderAndRun,
                    isBusy: isServiceBusy
                )
                .background(AppTheme.appBackground)
            } detail: {
                LogsPanelView(
                    selectedService: selectedService,
                    scope: $selectedLogScope,
                    feed: logFeed,
                    searchText: $logSearch,
                    onRestartService: onRestartService,
                    onClearLogs: onClearLogs
                )
            }
            // Only services and logs form the rounded card; the header above
            // sits on the window body.
            .hunRoundedShell(roundedPanels, leadingInset: HunLayout.shellInset, topInset: 0)
        }
    }
}

private struct ProjectHeaderView: View {
    let project: HunProject
    let onOpenBranchSwitcher: () -> Void
    let mode: HunMode
    @AppStorage(HunLayout.roundedPanelsKey) private var roundedPanels = HunLayout.roundedPanelsDefault
    let pendingAction: HunActionKind?
    let onFocus: () -> Void
    let onRun: () -> Void
    let onRunProfile: (String?) -> Void
    let onSaveProfile: (String) -> Void
    let onRestart: () -> Void
    let onStop: () -> Void
    let onOpenConfig: () -> Void
    let onChooseLogo: () -> Void
    let onClearLogo: () -> Void
    let onCopyAgentPrompt: () -> Void
    @State private var isSavingProfile = false
    @State private var newProfileName = ""

    private var runningServices: [HunService] {
        project.services.filter { $0.status == .running || $0.status == .starting }
    }

    private var primaryAction: ProjectHeaderAction {
        if pendingAction == .startProject {
            return ProjectHeaderAction(
                title: mode.primaryActionTitle,
                systemImage: mode.primaryActionIcon,
                style: .primary,
                isLoading: true,
                action: mode == .focus ? onFocus : onRun
            )
        }

        if pendingAction == .stopProject {
            return ProjectHeaderAction(
                title: "Stop",
                systemImage: "stop.fill",
                style: .danger,
                isLoading: true,
                action: onStop
            )
        }

        // A crashed project offers Stop too, which clears it; Restart beside
        // it tries again.
        if project.status == .running || project.status == .starting || project.status == .crashed {
            return ProjectHeaderAction(
                title: "Stop",
                systemImage: "stop.fill",
                style: .danger,
                isLoading: pendingAction == .stopProject,
                action: onStop
            )
        }

        return ProjectHeaderAction(
            title: mode.primaryActionTitle,
            systemImage: mode.primaryActionIcon,
            style: .primary,
            isLoading: pendingAction == .startProject,
            action: mode == .focus ? onFocus : onRun
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: roundedPanels ? 8 : 6) {
                // The logo sits with the title, small, on the same left edge
                // as the line below and the card's content. No running ring:
                // the status is written just under it.
                HStack(spacing: 9) {
                    ProjectIconView(
                        name: project.name,
                        iconPath: project.iconPath,
                        size: 22,
                        cornerRadius: 6
                    )
                    // A long name truncates on one line rather than wrapping
                    // or pushing the actions; hovering shows it in full.
                    Text(project.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(project.name)
                }

                // When the line doesn't fit, the path is dropped and the
                // branch truncates; the status never shrinks.
                ViewThatFits(in: .horizontal) {
                    metaLine(showsPath: true)
                    metaLine(showsPath: false)
                }

                if let configError = project.configError {
                    Label(configError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.danger)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 6) {
                if !project.profiles.isEmpty {
                    ProfileMenu(
                        project: project,
                        isSwitching: pendingAction == .switchProfile,
                        isDisabled: pendingAction != nil,
                        canSave: !runningServices.isEmpty,
                        onRun: onRunProfile,
                        onSave: beginSavingProfile,
                        onEdit: onOpenConfig
                    )
                }
                ActionButton(
                    title: primaryAction.title,
                    systemImage: primaryAction.systemImage,
                    style: primaryAction.style,
                    isLoading: primaryAction.isLoading,
                    isDisabled: pendingAction != nil,
                    action: primaryAction.action
                )
                ActionButton(
                    title: "Restart",
                    systemImage: "arrow.clockwise",
                    style: .secondary,
                    isLoading: pendingAction == .restartProject,
                    isDisabled: pendingAction != nil,
                    action: onRestart
                )
                ProjectMoreMenu(
                    canResetLogo: project.iconIsCustom,
                    canSaveProfile: !runningServices.isEmpty,
                    onSaveProfile: beginSavingProfile,
                    onOpenConfig: onOpenConfig,
                    onChooseLogo: onChooseLogo,
                    onClearLogo: onClearLogo,
                    onCopyAgentPrompt: onCopyAgentPrompt
                )
            }
            // The actions keep their size; the title truncates instead.
            .fixedSize()
        }
        // In the rounded layout, line the title up with the card's content
        // (card inset + panel padding) and keep the actions on the card's edge.
        .padding(.leading, roundedPanels ? HunLayout.shellInset + 14 : 22)
        .padding(.trailing, roundedPanels ? HunLayout.shellInset : 22)
        // The rounded layout has no tab bar above the header, so give it room
        // to breathe below the window edge and above the card.
        .padding(.top, roundedPanels ? 20 : 14)
        .padding(.bottom, roundedPanels ? 16 : 14)
        .alert("Save as Profile", isPresented: $isSavingProfile) {
            TextField("Name", text: $newProfileName)
            Button("Save") {
                onSaveProfile(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .disabled(HunProfile.problem(with: newProfileName) != nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(saveProfileMessage)
        }
    }

    private var saveProfileMessage: String {
        let names = runningServices.map(\.name).joined(separator: ", ")
        return "Adds a profile with the running services (\(names)) to .hun.yml. Run it any time from the profile menu."
    }

    private func beginSavingProfile() {
        newProfileName = ""
        isSavingProfile = true
    }

    private func metaLine(showsPath: Bool) -> some View {
        HStack(spacing: 14) {
            StatusMetaItem(status: project.status)
                .fixedSize()
            if let branch = project.branch {
                HunRepositoryStatusCapsule(branch: branch, onOpen: onOpenBranchSwitcher)
            }
            if showsPath {
                MetaItem(icon: "folder", text: collapsePath(project.path))
                    .fixedSize()
            }
        }
    }

    private func collapsePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

private struct ProjectHeaderAction {
    let title: String
    let systemImage: String
    let style: ActionStyle
    let isLoading: Bool
    let action: () -> Void
}

private struct StatusMetaItem: View {
    let status: ProjectStatus

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(AppTheme.textTertiary)
    }

    private var text: String {
        switch status {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .crashed: return "Crashed"
        case .starting: return "Starting…"
        }
    }
}

private struct MetaItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(AppTheme.textTertiary)
    }
}

enum ActionStyle { case primary, secondary, danger }

/// Picks which of a project's profiles runs. Choosing one runs it: a stopped
/// project starts it, a running one switches, changing only what differs.
private struct ProfileMenu: View {
    let project: HunProject
    let isSwitching: Bool
    let isDisabled: Bool
    let canSave: Bool
    let onRun: (String?) -> Void
    let onSave: () -> Void
    let onEdit: () -> Void
    @State private var hovering = false

    var body: some View {
        Menu {
            Section("Profiles") {
                option("All services", profile: nil)
                ForEach(project.profiles, id: \.name) { profile in
                    option(profile.name, profile: profile.name)
                }
            }
            Divider()
            Button("Save Running Services as Profile…", action: onSave)
                .disabled(!canSave)
            Button("Edit Profiles in .hun.yml", action: onEdit)
        } label: {
            HStack(spacing: 6) {
                if isSwitching {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .scaleEffect(0.62)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 11, height: 11)
                }
                Text(Self.shortened(project.profile ?? "All services"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(HunRoundedShape().fill(hovering ? AppTheme.hover : AppTheme.buttonFill))
            .overlay(HunRoundedShape().stroke(AppTheme.divider, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(isDisabled)
        .opacity(isDisabled && !isSwitching ? 0.55 : 1)
        .onHover { hovering = $0 }
        .help(helpText)
        .accessibilityLabel("Profile: \(project.profile ?? "All services")")
    }

    /// The button sizes to its label, so a long profile name is cut short
    /// here; the menu itself shows names in full.
    static func shortened(_ name: String) -> String {
        name.count > 24 ? String(name.prefix(23)) + "…" : name
    }

    /// A checkmarked row; choosing it runs that profile, even when it is
    /// already the current one.
    private func option(_ title: String, profile: String?) -> some View {
        Toggle(title, isOn: Binding(
            get: { project.profile == profile },
            set: { _ in onRun(profile) }
        ))
    }

    private var helpText: String {
        guard let services = project.profileServices else {
            return "Runs every service. Choose a profile to run a subset."
        }
        let names = project.services.map(\.id).filter { services.contains($0) }
        return "Runs \(names.joined(separator: ", ")). Choosing a profile runs it."
    }
}

/// Less frequent project actions, behind one button so Stop and Restart
/// stand out.
private struct ProjectMoreMenu: View {
    let canResetLogo: Bool
    let canSaveProfile: Bool
    let onSaveProfile: () -> Void
    let onOpenConfig: () -> Void
    let onChooseLogo: () -> Void
    let onClearLogo: () -> Void
    let onCopyAgentPrompt: () -> Void
    @State private var copiedPrompt = false

    var body: some View {
        Menu {
            Button("Edit .hun.yml", action: onOpenConfig)
            Button("Save Running Services as Profile…", action: onSaveProfile)
                .disabled(!canSaveProfile)
            Divider()
            Button("Choose Logo…", action: onChooseLogo)
            if canResetLogo {
                Button("Reset Logo", action: onClearLogo)
            }
            Divider()
            Button("Copy Agent Prompt") {
                onCopyAgentPrompt()
                withAnimation(.easeOut(duration: 0.16)) { copiedPrompt = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation(.easeIn(duration: 0.18)) { copiedPrompt = false }
                }
            }
        } label: {
            Image(systemName: copiedPrompt ? "checkmark" : "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(copiedPrompt ? AppTheme.success : AppTheme.textPrimary)
                .frame(width: 14, height: 14)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(
                    HunRoundedShape()
                        .fill(AppTheme.buttonFill)
                )
                .overlay(
                    HunRoundedShape()
                        .stroke(copiedPrompt ? AppTheme.success.opacity(0.35) : AppTheme.divider, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help(copiedPrompt ? "Agent prompt copied" : "More actions")
    }
}

struct ActionButton: View {
    let title: String
    let systemImage: String
    let style: ActionStyle
    var isLoading = false
    var isDisabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .scaleEffect(0.62)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 11, height: 11)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                HunRoundedShape()
                    .fill(background)
            )
            .overlay(
                HunRoundedShape()
                    .stroke(border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isLoading ? 0.55 : 1)
        .onHover { hovering = $0 }
    }

    private var textColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return AppTheme.textPrimary
        case .danger: return hovering ? AppTheme.danger : AppTheme.textSecondary
        }
    }

    private var background: Color {
        switch style {
        case .primary: return AppTheme.accent.opacity(hovering ? 1.0 : 0.92)
        case .secondary: return hovering ? AppTheme.hover : AppTheme.buttonFill
        case .danger: return hovering ? AppTheme.danger.opacity(0.12) : AppTheme.buttonFill
        }
    }

    private var border: Color {
        switch style {
        case .primary: return Color.white.opacity(0.10)
        case .secondary: return AppTheme.divider
        case .danger: return hovering ? AppTheme.danger.opacity(0.4) : AppTheme.divider
        }
    }
}

// MARK: - Services Panel

private struct ServicesPanelView: View {
    let services: [HunService]
    /// The current profile and what it runs; nil when it runs every service.
    let profileName: String?
    let profileServices: Set<String>?
    @Binding var selectedID: String?
    @Binding var selectedScope: LogScope
    let onOpenConfig: () -> Void
    let onRun: (HunService) -> Void
    let onRestart: (HunService) -> Void
    let onStop: (HunService) -> Void
    let onRemove: (HunService) -> Void
    let onStopHolderAndRun: (HunService) -> Void
    let isBusy: (HunService) -> Bool
    @AppStorage(HunServicesDisplay.showOutsideProfileKey)
    private var showsOutsideProfile = HunServicesDisplay.showOutsideProfileDefault

    private func isHidden(_ service: HunService) -> Bool {
        !showsOutsideProfile && !ServicesList.isInProfile(service, profileServices: profileServices)
    }

    private var hiddenCount: Int {
        services.filter(isHidden).count
    }

    /// A hidden service is never shown just because it was selected (say,
    /// remembered from before the profile changed); the first visible one
    /// is selected instead.
    private func selectVisibleService() {
        guard let selected = services.first(where: { $0.id == selectedID }), isHidden(selected),
              let replacement = services.first(where: { !isHidden($0) })
        else { return }
        selectedID = replacement.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Same type, height and divider as the logs header beside it, so
            // the two read as one band across the panel.
            HStack(spacing: 6) {
                Text("Services")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Group {
                    if hiddenCount > 0 {
                        Text(verbatim: "\(services.count - hiddenCount) of \(services.count)")
                            .help("\(hiddenCount) not in \(profileName ?? "this profile") are hidden. Show them in Settings › Appearance.")
                    } else {
                        Text(verbatim: "\(services.count)")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .monospacedDigit()
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .frame(height: LogsToolbarMetrics.controlHeight + 20)

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            ScrollView {
                ServicesList(
                    services: services,
                    profileName: profileName,
                    profileServices: profileServices,
                    showsOutsideProfile: showsOutsideProfile,
                    selectedID: $selectedID,
                    selectedScope: $selectedScope,
                    onOpenConfig: onOpenConfig,
                    onRun: onRun,
                    onRestart: onRestart,
                    onStop: onStop,
                    onRemove: onRemove,
                    onStopHolderAndRun: onStopHolderAndRun,
                    isBusy: isBusy
                )
            }
            .hunScrollStyle()
        }
        .onAppear(perform: selectVisibleService)
        .onChange(of: selectedID) { _, _ in selectVisibleService() }
        .onChange(of: profileServices) { _, _ in selectVisibleService() }
        .onChange(of: showsOutsideProfile) { _, _ in selectVisibleService() }
    }
}

/// The service rows. Services the current profile leaves out are grouped
/// below the rest.
private struct ServicesList: View {
    let services: [HunService]
    let profileName: String?
    let profileServices: Set<String>?
    let showsOutsideProfile: Bool
    @Binding var selectedID: String?
    @Binding var selectedScope: LogScope
    let onOpenConfig: () -> Void
    let onRun: (HunService) -> Void
    let onRestart: (HunService) -> Void
    let onStop: (HunService) -> Void
    let onRemove: (HunService) -> Void
    let onStopHolderAndRun: (HunService) -> Void
    let isBusy: (HunService) -> Bool

    var body: some View {
        VStack(spacing: 4) {
            ForEach(profileServicesList) { service in
                row(service)
            }
            if !otherServices.isEmpty {
                // Services the profile leaves out stay one click away,
                // grouped below so they don't crowd the ones in use.
                Text(verbatim: "Not in \(profileName ?? "this profile")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                ForEach(otherServices) { service in
                    row(service)
                        .opacity(service.id == selectedID ? 1 : 0.6)
                }
            }
        }
        // Same gap above the first card as at its sides, so it never
        // sits on the header divider.
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// In the profile, or running anyway (started on its own or elsewhere).
    static func isInProfile(_ service: HunService, profileServices: Set<String>?) -> Bool {
        guard let profileServices else { return true }
        return profileServices.contains(service.id) || service.status != .stopped
    }

    private var profileServicesList: [HunService] {
        services.filter { Self.isInProfile($0, profileServices: profileServices) }
    }

    /// Shown only when the setting is on.
    private var otherServices: [HunService] {
        guard showsOutsideProfile else { return [] }
        return services.filter { !Self.isInProfile($0, profileServices: profileServices) }
    }

    private func row(_ service: HunService) -> some View {
        ServiceRowView(
            service: service,
            selected: service.id == selectedID,
            onTap: {
                withAnimation(.easeOut(duration: 0.12)) {
                    selectedID = service.id
                    selectedScope = .service
                }
            },
            onRun: { onRun(service) },
            onRestart: { onRestart(service) },
            onStop: { onStop(service) },
            onRemove: { onRemove(service) },
            onOpenConfig: onOpenConfig,
            onStopHolderAndRun: { onStopHolderAndRun(service) },
            busy: isBusy(service)
        )
    }
}

private struct ServiceRowView: View {
    let service: HunService
    let selected: Bool
    let onTap: () -> Void
    let onRun: () -> Void
    let onRestart: () -> Void
    let onStop: () -> Void
    let onRemove: () -> Void
    let onOpenConfig: () -> Void
    let onStopHolderAndRun: () -> Void
    let busy: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // The dot has its own gutter so the name and command share one edge.
            statusDot
                .frame(width: 8, height: 17)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(service.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    if let statusLabel {
                        Text(statusLabel)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(service.status.color)
                    }
                    if service.isExternal {
                        Text("outside Hun")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 5)
                            .frame(height: 15)
                            .background(HunRoundedShape().fill(AppTheme.selection))
                            .help(service.externalSourceText + ". Restart to run it in Hun with logs.")
                    }
                    Spacer(minLength: 8)
                    portView
                }
                .frame(height: 17)

                HStack(spacing: 8) {
                    Text(service.command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    if service.pid > 0 {
                        Text(verbatim: "\(service.pid)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(AppTheme.textTertiary)
                            .help("Process ID")
                    }
                }

                if let holder = service.conflict {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppTheme.warning)
                        Text(verbatim: "Port \(holder.port) held by \(holder.summary)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        InlineActionButton(title: "Stop it & run", action: onStopHolderAndRun)
                            .disabled(busy)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            HunRoundedShape()
                .fill(selected ? AppTheme.selectedFill : (hovering ? AppTheme.rowHover : Color.clear))
        )
        .contentShape(Rectangle())
        // A tap gesture rather than a Button, so the port link inside works.
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .onHover { hovering = $0 }
        .help(helpText)
        .contextMenu {
            if let url = service.browserURL {
                Button("Open \(url.absoluteString)") {
                    NSWorkspace.shared.open(url)
                }
                Divider()
            }
            Button("Run", action: onRun)
            Button("Restart", action: onRestart)
            Button("Stop", action: onStop)
            Divider()
            Button("Edit .hun.yml", action: onOpenConfig)
            Button("Remove from Hun", role: .destructive, action: onRemove)
        }
    }

    /// Color says running, stopped or crashed; a ring means still starting
    /// (not ready yet), a solid dot means ready.
    @ViewBuilder
    private var statusDot: some View {
        let isWarmingUp = service.status == .starting || (service.status == .running && !service.ready)
        if isWarmingUp {
            Circle()
                .strokeBorder(service.status.color, lineWidth: 1.5)
                .frame(width: 7, height: 7)
        } else {
            Circle()
                .fill(service.status.color)
                .frame(width: 6, height: 6)
        }
    }

    /// Only states that need attention are spelled out next to the name.
    private var statusLabel: String? {
        switch service.status {
        case .crashed: return "crashed"
        case .starting: return "starting"
        case .running, .stopped: return nil
        }
    }

    /// The port, a link while the service runs; a spinner while an action runs.
    @ViewBuilder
    private var portView: some View {
        if busy {
            ProgressView()
                .controlSize(.mini)
        } else if let url = service.browserURL {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Text(service.portText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .underline(hovering)
            }
            .buttonStyle(.plain)
            .help("Open \(url.absoluteString)")
        } else if service.port > 0 {
            Text(service.portText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var helpText: String {
        var parts = [service.status.title]
        if service.pid > 0 { parts.append("pid \(service.pid)") }
        if service.port > 0 { parts.append("port \(service.port)") }
        if service.status == .running { parts.append(service.ready ? "ready" : "not ready yet") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Logs Panel

private struct LogsPanelView: View {
    let selectedService: HunService?
    @Binding var scope: LogScope
    let feed: HunLogFeed
    @Binding var searchText: String
    var onRestartService: (HunService) -> Void = { _ in }
    var onClearLogs: () -> Void = {}

    private var title: String {
        scope == .combined ? "All logs" : (selectedService?.name ?? "Logs")
    }

    /// Identity for the tail view so it resets (and re-tails) when the user
    /// switches scope or service, instead of carrying over a stale paused state.
    private var tailIdentity: String {
        scope == .combined ? "combined" : "service|\(selectedService?.id ?? "")"
    }

    private var filter: HunLogFilter {
        HunLogFilter(
            service: scope == .service ? (selectedService?.id ?? "") : nil,
            query: searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Stops at the first match, so it stays cheap as lines stream in.
    private var hasLogs: Bool {
        let filter = self.filter
        return feed.lines.contains(where: filter.matches)
    }

    var body: some View {
        // Computed once per render; the toolbar and the content both use it.
        let hasLogs = self.hasLogs
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                LogSearchField(text: $searchText)
                    .frame(maxWidth: 220)

                LogsToolbarIconButton(
                    icon: .symbol("doc.on.doc"),
                    helpText: "Copy all visible logs (⌘C)",
                    confirms: true,
                    enabled: hasLogs,
                    action: copyAllLogs
                )

                LogsToolbarIconButton(
                    icon: .trashOutline,
                    helpText: scope == .combined
                        ? "Clear all logs for this project"
                        : "Clear logs for \(selectedService?.name ?? "this service")",
                    enabled: hasLogs,
                    action: onClearLogs
                )

                ScopeSegmented(scope: $scope)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            if !hasLogs, scope == .service, let service = selectedService, service.isExternal {
                ExternalLogsEmptyState(service: service, onRestart: { onRestartService(service) })
            } else if !hasLogs {
                LogsEmptyState()
            } else {
                LogsTailContainer(
                    feed: feed,
                    filter: filter,
                    showService: scope == .combined
                )
                .id(tailIdentity)
            }
        }
        .background(AppTheme.appBackground)
    }

    private func copyAllLogs() {
        let filter = self.filter
        let logs = feed.lines.filter(filter.matches)
        guard !logs.isEmpty else { return }
        let text = logs
            .map { "\($0.time)  \($0.service.padding(toLength: 10, withPad: " ", startingAt: 0))  \($0.message)" }
            .joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

private struct LogSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HunSearchField(
            text: $text,
            placeholder: "Search logs",
            height: LogsToolbarMetrics.controlHeight,
            fontSize: 11.5,
            isFocused: $focused
        )
    }
}

private enum LogsToolbarMetrics {
    static let controlHeight: CGFloat = 26
}

private struct ScopeSegmented: View {
    @Binding var scope: LogScope

    var body: some View {
        HStack(spacing: 0) {
            scopeButton("Service", .service)
            scopeButton("All", .combined)
        }
        .padding(2)
        .frame(height: LogsToolbarMetrics.controlHeight)
        .background(
            HunRoundedShape()
                .fill(AppTheme.searchField)
        )
    }

    private func scopeButton(_ title: String, _ s: LogScope) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { scope = s }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(scope == s ? AppTheme.textPrimary : AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    HunRoundedShape()
                        .fill(scope == s ? AppTheme.tabActive : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum LogsToolbarIcon {
    case symbol(String)
    case trashOutline
}

/// A trash can drawn as a plain outline; SF Symbols only offers one with
/// inner ribs or a filled one.
private struct TrashOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let lidY = h * 0.2
        let radius = w * 0.12
        var path = Path()
        // Handle
        path.move(to: CGPoint(x: w * 0.36, y: lidY))
        path.addLine(to: CGPoint(x: w * 0.36, y: 0))
        path.addLine(to: CGPoint(x: w * 0.64, y: 0))
        path.addLine(to: CGPoint(x: w * 0.64, y: lidY))
        // Lid
        path.move(to: CGPoint(x: 0, y: lidY))
        path.addLine(to: CGPoint(x: w, y: lidY))
        // Can
        path.move(to: CGPoint(x: w * 0.12, y: lidY))
        path.addLine(to: CGPoint(x: w * 0.19, y: h - radius))
        path.addQuadCurve(to: CGPoint(x: w * 0.19 + radius, y: h), control: CGPoint(x: w * 0.19, y: h))
        path.addLine(to: CGPoint(x: w * 0.81 - radius, y: h))
        path.addQuadCurve(to: CGPoint(x: w * 0.81, y: h - radius), control: CGPoint(x: w * 0.81, y: h))
        path.addLine(to: CGPoint(x: w * 0.88, y: lidY))
        return path
    }
}

/// A square icon button sized to the logs toolbar controls.
private struct LogsToolbarIconButton: View {
    let icon: LogsToolbarIcon
    let helpText: String
    var confirms = false
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false
    @State private var showingConfirm = false

    var body: some View {
        Button {
            action()
            guard confirms else { return }
            withAnimation(.easeOut(duration: 0.18)) { showingConfirm = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeIn(duration: 0.25)) { showingConfirm = false }
            }
        } label: {
            iconView
                .foregroundStyle(showingConfirm ? AppTheme.success : (hovering ? AppTheme.textPrimary : AppTheme.textSecondary))
                .frame(width: LogsToolbarMetrics.controlHeight, height: LogsToolbarMetrics.controlHeight)
                .background(
                    HunRoundedShape()
                        .fill(hovering ? AppTheme.hover : AppTheme.searchField)
                )
                .overlay(
                    HunRoundedShape()
                        .stroke(showingConfirm ? AppTheme.success.opacity(0.3) : AppTheme.divider, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .help(showingConfirm ? "Copied" : helpText)
    }

    @ViewBuilder
    private var iconView: some View {
        if showingConfirm {
            Image(systemName: "checkmark")
                .font(.system(size: 10.5, weight: .semibold))
        } else {
            switch icon {
            case let .symbol(name):
                Image(systemName: name)
                    .font(.system(size: 10.5, weight: .semibold))
            case .trashOutline:
                TrashOutline()
                    .stroke(style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                    .frame(width: 10, height: 11)
            }
        }
    }
}

private struct LogsEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(AppTheme.textTertiary)
            Text("No logs yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text("Output from this service will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown for a service started outside Hun: its output went to whatever
/// started it, so Hun can only show logs after it restarts the service.
private struct ExternalLogsEmptyState: View {
    let service: HunService
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(AppTheme.textTertiary)
            Text("Started outside Hun")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text(service.isDocker
                ? "Restart to attach Hun to this container and stream its logs here."
                : "Its output goes to the terminal or tool that started it. Restart to run it in Hun and capture logs here.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            InlineActionButton(title: "Restart in Hun", action: onRestart)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Native log text view

/// Which lines the log view shows: one service's (or all) that match the
/// search text.
struct HunLogFilter: Equatable {
    /// The service to show, or nil for all. An empty string shows nothing.
    var service: String?
    var query: String

    func matches(_ line: HunLogLine) -> Bool {
        if let service, line.service != service { return false }
        guard !query.isEmpty else { return true }
        return line.message.localizedCaseInsensitiveContains(query)
            || line.service.localizedCaseInsensitiveContains(query)
    }
}

struct LogsTailContainer: View {
    let feed: HunLogFeed
    let filter: HunLogFilter
    let showService: Bool

    @State private var isTailing = true
    @State private var newSincePause = 0
    @State private var countedGeneration = 0
    @State private var scrollTrigger = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            LogsTextView(
                feed: feed,
                // Read here so a new batch redraws only this view.
                generation: feed.generation,
                lastSeq: feed.lastSeq,
                filter: filter,
                showService: showService,
                isTailing: $isTailing,
                scrollTrigger: scrollTrigger
            )

            if !isTailing {
                LiveTailButton(newCount: newSincePause) {
                    isTailing = true
                    newSincePause = 0
                    scrollTrigger &+= 1
                }
                .padding(.bottom, 16)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.88, anchor: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .offset(y: 8)),
                        removal: .scale(scale: 0.94, anchor: .bottom)
                            .combined(with: .opacity)
                    )
                )
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isTailing)
        .onAppear { countedGeneration = feed.generation }
        .onChange(of: feed.lastSeq) { old, new in
            // A reload replaces the lines; only appended ones are "new".
            guard feed.generation == countedGeneration else {
                countedGeneration = feed.generation
                return
            }
            guard !isTailing, new > old else { return }
            newSincePause += feed.lines.reversed().prefix { $0.id > old }.filter(filter.matches).count
        }
        .onChange(of: isTailing) { _, tailing in
            if tailing { newSincePause = 0 }
        }
    }
}

private struct LiveTailButton: View {
    let newCount: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                Text("Live tail")
                    .font(.system(size: 12, weight: .medium))
                if newCount > 0 {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text("\(newCount) new")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: HunRoundedShape())
            .overlay(
                HunRoundedShape()
                    .stroke(
                        hovering ? AppTheme.floatingBorderHover : AppTheme.floatingBorder,
                        lineWidth: 1
                    )
            )
            .shadow(color: AppTheme.floatingShadow, radius: 10, y: 4)
            .scaleEffect(hovering ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Resume following the latest logs (jump to bottom)")
    }
}

private struct LogsTextView: NSViewRepresentable {
    let feed: HunLogFeed
    let generation: Int
    let lastSeq: Int
    let filter: HunLogFilter
    let showService: Bool
    @Binding var isTailing: Bool
    let scrollTrigger: Int
    @Environment(\.colorScheme) private var colorScheme

    /// What forces a full redraw when it changes; anything else is appended.
    struct RenderKey: Equatable {
        let generation: Int
        let filter: HunLogFilter
        let showService: Bool
        let dark: Bool
    }

    final class Coordinator: NSObject {
        var lastTrigger: Int = .min
        weak var scrollView: NSScrollView?
        weak var textView: LogsTextViewKit?
        var setTailing: ((Bool) -> Void)?
        var currentTailing: () -> Bool = { false }

        // What the text view holds: the feed lines up to `renderedSeq` that
        // match the filter, oldest first, joined by newlines.
        var renderedKey: RenderKey?
        var renderedSeq = 0
        var renderedIDs: [Int] = []
        var renderedLengths: [Int] = []
        var styles: LogStyles?

        @objc func userDidScroll(_ note: Notification) {
            guard let scroll = scrollView, let doc = scroll.documentView else { return }
            let visible = scroll.contentView.bounds
            let nearBottom = visible.maxY >= doc.bounds.height - 30
            let tailing = currentTailing()
            if nearBottom && !tailing { setTailing?(true) }
            else if !nearBottom && tailing { setTailing?(false) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var renderKey: RenderKey {
        RenderKey(generation: generation, filter: filter, showService: showService, dark: colorScheme == .dark)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = HunStyledScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(AppTheme.appBackground)
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let textView = LogsTextViewKit()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0,
                                                        height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView

        context.coordinator.scrollView = scroll
        context.coordinator.textView = textView
        context.coordinator.setTailing = { value in
            DispatchQueue.main.async {
                if isTailing != value { self.isTailing = value }
            }
        }
        context.coordinator.currentTailing = { isTailing }

        let nc = NotificationCenter.default
        nc.addObserver(context.coordinator,
                       selector: #selector(Coordinator.userDidScroll(_:)),
                       name: NSScrollView.didLiveScrollNotification,
                       object: scroll)
        nc.addObserver(context.coordinator,
                       selector: #selector(Coordinator.userDidScroll(_:)),
                       name: NSScrollView.didEndLiveScrollNotification,
                       object: scroll)

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(AppTheme.appBackground)
        // 22pt of left margin = the "gutter column". The triangle is drawn
        // inside this inset (only on the last line) so all timestamps stay
        // perfectly aligned with no inline attachment shifting them.
        textView.textContainerInset = NSSize(width: 22, height: 8)
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.linkTextAttributes = [:]
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true

        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(AppTheme.accent).withAlphaComponent(0.32),
            .foregroundColor: NSColor(AppTheme.selectedText)
        ]

        render(textView, coordinator: context.coordinator, scroll: scroll)
        context.coordinator.lastTrigger = scrollTrigger
        DispatchQueue.main.async { scrollToBottom(scroll: scroll) }

        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.currentTailing = { isTailing }
        coord.setTailing = { value in
            DispatchQueue.main.async {
                if isTailing != value { self.isTailing = value }
            }
        }

        if scrollTrigger != coord.lastTrigger {
            coord.lastTrigger = scrollTrigger
            DispatchQueue.main.async { scrollToBottom(scroll: scroll) }
        }

        guard let textView = scroll.documentView as? LogsTextViewKit else { return }
        scroll.backgroundColor = NSColor(AppTheme.appBackground)
        textView.backgroundColor = NSColor(AppTheme.appBackground)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(AppTheme.accent).withAlphaComponent(0.32),
            .foregroundColor: NSColor(AppTheme.selectedText)
        ]
        if render(textView, coordinator: coord, scroll: scroll), isTailing {
            DispatchQueue.main.async { scrollToBottom(scroll: scroll) }
        }
    }

    private func scrollToBottom(scroll: NSScrollView) {
        guard let textView = scroll.documentView as? NSTextView,
              let storage = textView.textStorage else { return }
        textView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
    }

    // MARK: - Rendering

    /// Brings the text view up to date with the feed. New lines are appended
    /// and lines the feed dropped are trimmed from the top, so the cost
    /// follows the batch, not the 5,000 lines on screen. Returns whether
    /// anything changed.
    @discardableResult
    func render(_ textView: LogsTextViewKit, coordinator coord: Coordinator, scroll: NSScrollView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let lines = feed.lines
        let key = renderKey
        if coord.renderedKey != key || coord.styles == nil {
            coord.renderedKey = key
            coord.styles = LogStyles(showService: showService)
            rebuild(textView, storage: storage, lines: lines, coord: coord)
            return true
        }
        guard let styles = coord.styles, let newest = lines.last?.id, newest > coord.renderedSeq else {
            return false
        }

        // Lines added since the last pass, found from the end.
        var start = lines.count
        while start > 0, lines[start - 1].id > coord.renderedSeq { start -= 1 }
        let fresh = lines[start...].filter(filter.matches)
        coord.renderedSeq = newest

        // Drawn lines the feed has since dropped.
        let oldestKept = lines.first?.id ?? .max
        var dropCount = 0
        while dropCount < coord.renderedIDs.count, coord.renderedIDs[dropCount] < oldestKept { dropCount += 1 }
        if dropCount > 0, dropCount == coord.renderedIDs.count {
            rebuild(textView, storage: storage, lines: lines, coord: coord)
            return true
        }
        guard !fresh.isEmpty || dropCount > 0 else { return false }

        let deleteLength = coord.renderedLengths.prefix(dropCount).reduce(0) { $0 + $1 + 1 }
        // While reading back in the history, keep the same lines in view when
        // the oldest ones are trimmed.
        let removedHeight = (dropCount > 0 && !isTailing) ? heightOfText(before: deleteLength, in: textView) : 0

        storage.beginEditing()
        if !fresh.isEmpty {
            let chunk = NSMutableAttributedString()
            for line in fresh {
                if storage.length > 0 || chunk.length > 0 {
                    chunk.append(NSAttributedString(string: "\n", attributes: styles.newline))
                }
                let length = append(line, to: chunk, styles: styles)
                coord.renderedIDs.append(line.id)
                coord.renderedLengths.append(length)
            }
            storage.append(chunk)
        }
        if dropCount > 0 {
            storage.deleteCharacters(in: NSRange(location: 0, length: deleteLength))
            coord.renderedIDs.removeFirst(dropCount)
            coord.renderedLengths.removeFirst(dropCount)
        }
        storage.endEditing()

        textView.lastLineRange = coord.renderedLengths.last.map {
            NSRange(location: storage.length - $0, length: $0)
        }
        if removedHeight > 0 {
            let clip = scroll.contentView
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: max(0, clip.bounds.origin.y - removedHeight)))
            scroll.reflectScrolledClipView(clip)
        }
        return true
    }

    private func rebuild(_ textView: LogsTextViewKit, storage: NSTextStorage, lines: [HunLogLine], coord: Coordinator) {
        guard let styles = coord.styles else { return }
        let result = NSMutableAttributedString()
        coord.renderedIDs = []
        coord.renderedLengths = []
        for line in lines where filter.matches(line) {
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n", attributes: styles.newline))
            }
            coord.renderedLengths.append(append(line, to: result, styles: styles))
            coord.renderedIDs.append(line.id)
        }
        coord.renderedSeq = lines.last?.id ?? 0
        storage.setAttributedString(result)
        textView.lastLineRange = coord.renderedLengths.last.map {
            NSRange(location: storage.length - $0, length: $0)
        }
    }

    /// Height of the text before `location`, which is where the line at
    /// `location` starts.
    private func heightOfText(before location: Int, in textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.layoutManager,
              let storage = textView.textStorage,
              location < storage.length else { return 0 }
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: location + 1))
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    }

    /// Appends one log line (time, service in the All view, message) and
    /// returns its length.
    private func append(_ line: HunLogLine, to result: NSMutableAttributedString, styles: LogStyles) -> Int {
        let lineStart = result.length
        let query = filter.query

        let timeText = (line.time as NSString).padding(toLength: 13, withPad: " ", startingAt: 0)
        result.append(NSAttributedString(string: timeText + "  ", attributes: styles.time))

        if showService {
            let serviceStart = result.length
            let svc = (line.service as NSString).padding(toLength: 10, withPad: " ", startingAt: 0)
            result.append(NSAttributedString(string: svc + "  ", attributes: styles.service(line.service)))
            highlightMatches(in: result, plain: line.service, startLocation: serviceStart, query: query, styles: styles)
        }

        let messageStart = result.length
        result.append(NSAttributedString(string: line.message, attributes: styles.message(line.level)))
        highlightMatches(in: result, plain: line.message, startLocation: messageStart, query: query, styles: styles)

        return result.length - lineStart
    }

    /// Applies a search highlight to every case-insensitive occurrence of
    /// `query` within `plain`, offset to its position in `result`.
    private func highlightMatches(in result: NSMutableAttributedString, plain: String, startLocation: Int, query: String, styles: LogStyles) {
        guard !query.isEmpty else { return }
        let haystack = plain as NSString
        var searchStart = 0
        while searchStart < haystack.length {
            let scope = NSRange(location: searchStart, length: haystack.length - searchStart)
            let found = haystack.range(of: query, options: [.caseInsensitive], range: scope)
            if found.location == NSNotFound { break }
            result.addAttributes(
                styles.highlight,
                range: NSRange(location: startLocation + found.location, length: found.length)
            )
            searchStart = found.location + max(found.length, 1)
        }
    }
}

/// Fonts and colors for log lines, resolved once per redraw rather than for
/// every line.
final class LogStyles {
    private static let timeFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let bodyFont: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let serviceFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .medium)

    let time: [NSAttributedString.Key: Any]
    let newline: [NSAttributedString.Key: Any]
    let highlight: [NSAttributedString.Key: Any]
    private let info: [NSAttributedString.Key: Any]
    private let warning: [NSAttributedString.Key: Any]
    private let error: [NSAttributedString.Key: Any]
    private let paragraph: NSParagraphStyle
    private let palette: [NSColor]
    private var services: [String: [NSAttributedString.Key: Any]] = [:]

    init(showService: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1.5
        paragraph.headIndent = (showService ? 100 : 0) + 110 + 4
        paragraph.firstLineHeadIndent = 0
        self.paragraph = paragraph

        func body(_ color: NSColor) -> [NSAttributedString.Key: Any] {
            [.font: Self.bodyFont, .foregroundColor: color, .paragraphStyle: paragraph]
        }
        time = [.font: Self.timeFont, .foregroundColor: NSColor(AppTheme.logTimestamp), .paragraphStyle: paragraph]
        newline = [.font: Self.bodyFont, .paragraphStyle: paragraph]
        info = body(NSColor(AppTheme.logText))
        warning = body(NSColor(AppTheme.warning))
        error = body(NSColor(AppTheme.danger))
        highlight = [
            .backgroundColor: NSColor(red: 0.99, green: 0.80, blue: 0.30, alpha: 0.32),
            .foregroundColor: AppTheme.nativeColor(light: 0x3A3020, dark: 0xFCFCFC)
        ]
        palette = [
            AppTheme.nativeColor(light: 0x445DB7, darkRed: 0.45, darkGreen: 0.55, darkBlue: 0.95),
            AppTheme.nativeColor(light: 0xB64C46, darkRed: 0.95, darkGreen: 0.55, darkBlue: 0.50),
            AppTheme.nativeColor(light: 0x327C65, darkRed: 0.45, darkGreen: 0.78, darkBlue: 0.65),
            AppTheme.nativeColor(light: 0x986327, darkRed: 0.85, darkGreen: 0.65, darkBlue: 0.45),
            AppTheme.nativeColor(light: 0x744DA7, darkRed: 0.72, darkGreen: 0.55, darkBlue: 0.92)
        ]
    }

    func message(_ level: LogLevel) -> [NSAttributedString.Key: Any] {
        switch level {
        case .error: return error
        case .warning: return warning
        case .info: return info
        }
    }

    /// A service keeps the same color across launches (`hashValue` is
    /// randomized per launch, so this uses a fixed FNV-1a hash).
    func service(_ name: String) -> [NSAttributedString.Key: Any] {
        if let cached = services[name] { return cached }
        var hash: UInt32 = 2_166_136_261
        for byte in name.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.serviceFont,
            .foregroundColor: palette[Int(hash % UInt32(palette.count))],
            .paragraphStyle: paragraph
        ]
        services[name] = attributes
        return attributes
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    let projectCount: Int
    let isRecovering: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if isRecovering {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)
            if projectCount == 0 && !isRecovering {
                ActionButton(
                    title: "Refresh",
                    systemImage: "arrow.clockwise",
                    style: .secondary,
                    action: onRefresh
                )
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.appBackground)
    }

    private var title: String {
        if isRecovering { return "Restoring projects…" }
        return projectCount == 0 ? "No projects found" : "No project selected"
    }

    private var message: String {
        if isRecovering {
            return "Hun is reconnecting to your running services."
        }
        if projectCount == 0 {
            return "Create or edit .hun.yml in a configured project root."
        }
        return "Pick a project from the sidebar to get started."
    }
}

// MARK: - Log text view (custom drawing for the live-edge marker)

/// `NSTextView` subclass that paints two extras BENEATH the text:
///   1. A subtle row-wide purple wash behind the most recent log line.
///   2. A small filled triangle in the leading inset margin pointing at it.
///
/// Both are drawn in textView coordinates outside the text flow, so every
/// log line keeps the same column alignment.
final class LogsTextViewKit: NSTextView {
    /// Character range of the most recent log line.
    var lastLineRange: NSRange? {
        didSet { needsDisplay = true }
    }

    var liveEdgeBackground: NSColor = NSColor(AppTheme.accent).withAlphaComponent(0.13)
    var liveEdgeArrowColor: NSColor = NSColor(AppTheme.accent)

    /// Called by `super.draw(_:)` BEFORE glyphs are drawn — wash goes here so
    /// text remains crisp on top.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawLastLineBackground(dirtyRect: rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawLastLineArrow(dirtyRect: dirtyRect)
    }

    private func drawLastLineBackground(dirtyRect: NSRect) {
        guard let lineRect = lastLineRect() else { return }
        let bgRect = NSRect(x: 0,
                            y: lineRect.minY,
                            width: bounds.width,
                            height: lineRect.height)
        guard bgRect.intersects(dirtyRect) else { return }
        liveEdgeBackground.setFill()
        bgRect.fill()
    }

    private func drawLastLineArrow(dirtyRect: NSRect) {
        guard let lineRect = lastLineRect() else { return }

        // Arrow lives inside the textContainerInset (the left margin) — it
        // doesn't overlap any text, so all timestamps stay aligned.
        let triHeight: CGFloat = 6.5
        let triWidth: CGFloat = 4.5
        let leftPad: CGFloat = 8
        let cy = lineRect.midY

        let arrowFrame = NSRect(x: leftPad,
                                y: cy - triHeight / 2,
                                width: triWidth,
                                height: triHeight)
        guard arrowFrame.intersects(dirtyRect) else { return }

        let path = NSBezierPath()
        path.move(to: NSPoint(x: leftPad, y: cy - triHeight / 2))
        path.line(to: NSPoint(x: leftPad + triWidth, y: cy))
        path.line(to: NSPoint(x: leftPad, y: cy + triHeight / 2))
        path.close()
        liveEdgeArrowColor.setFill()
        path.fill()
    }

    private func lastLineRect() -> NSRect? {
        guard let range = lastLineRange,
              range.location != NSNotFound,
              let layoutManager = self.layoutManager,
              let textContainer = self.textContainer,
              let storage = textStorage,
              range.location < storage.length
        else { return nil }

        layoutManager.ensureLayout(forCharacterRange: range)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return nil }

        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        return rect
    }
}

#Preview {
    ContentView()
        .environment(HunStore(startAutomatically: false))
        .frame(width: 1200, height: 760)
}
