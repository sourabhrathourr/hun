import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(HunStore.self) private var store
    @State private var sidebarSearch = ""
    @State private var logSearch = ""
    @State private var sidebarDocked = true
    @State private var sidebarRevealed = false
    @State private var sidebarRevealShowTask: Task<Void, Never>?
    @State private var sidebarRevealHideTask: Task<Void, Never>?
    @State private var collapsedSections: Set<String> = []
    @State private var presentedSheet: DashboardSheet?
    @FocusState private var sidebarSearchFocused: Bool
    private let sidebarWidth: CGFloat = 250

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

    private var visibleLogs: [HunLogLine] {
        guard let project = activeProject else { return [] }
        let scoped: [HunLogLine]
        switch store.selectedLogScope {
        case .service:
            scoped = project.logs.filter { $0.serviceID == store.selectedServiceID }
        case .combined:
            scoped = project.logs
        }
        let q = logSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return scoped }
        return scoped.filter {
            $0.message.localizedCaseInsensitiveContains(q) ||
                $0.service.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if sidebarDocked {
                    sidebar(docked: true)
                        .frame(width: sidebarWidth)
                        .background(AppTheme.sidebar)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(AppTheme.divider).frame(width: 1)
                        }
                        .clipped()
                        .zIndex(1)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if !sidebarDocked {
                sidebarRevealLayer
            }
        }
        .preferredColorScheme(.dark)
        .background(AppTheme.appBackground)
        .background(WindowChromeConfigurator())
        .background(
            WindowInteractionMonitor(
                onToggleSidebar: toggleSidebar,
                onFocusProjectSearch: focusProjectSearch,
                onOpenSettings: { presentedSheet = .settings },
                onClearProjectSearchFocus: clearProjectSearchFocus
            )
        )
        .ignoresSafeArea(.container, edges: .top)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: sidebarDocked)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: sidebarRevealed)
        .task {
            await store.refresh(force: true)
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .settings:
                HunSettingsSheet()
            }
        }
    }

    private var mainContent: some View {
        @Bindable var store = store
        return VStack(spacing: 0) {
            TopBarView(
                openProjects: openProjects,
                activeID: $store.selectedProjectID,
                mode: $store.globalMode,
                showSidebarControl: !sidebarDocked,
                onSelect: selectProjectTab,
                onClose: closeTab,
                onToggleSidebar: dockSidebar
            )
            .background(AppTheme.appBackground)

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            if let lastError = store.lastError {
                ErrorBanner(message: lastError, onDismiss: { store.clearLastError() })
                Rectangle().fill(AppTheme.divider).frame(height: 1)
            }

            Group {
                if let project = activeProject {
                    ProjectDetailView(
                        project: project,
                        mode: store.globalMode,
                        pendingAction: store.projectAction(for: project),
                        logSearch: $logSearch,
                        selectedServiceID: $store.selectedServiceID,
                        selectedLogScope: $store.selectedLogScope,
                        visibleLogs: visibleLogs,
                        onFocus: { store.focus(project) },
                        onRun: { store.run(project) },
                        onRestart: { store.restart(project) },
                        onStop: { store.stop(project) },
                        onOpenConfig: { store.openConfig(for: project) },
                        onChooseLogo: { store.chooseLogo(for: project) },
                        onClearLogo: { store.clearLogo(for: project) },
                        onCopyAgentPrompt: { store.copyAgentPrompt(for: project) },
                        onRunService: { service in store.run(service, in: project) },
                        onRestartService: { service in store.restart(service, in: project) },
                        onStopService: { service in store.stop(service, in: project) },
                        onRemoveService: { service in store.remove(service, from: project) }
                    )
                } else {
                    EmptyStateView(projectCount: model.projects.count, onRefresh: { store.refreshNow() })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.appBackground)
        }
        .padding(.leading, sidebarDocked ? 0 : 8)
    }

    private func sidebar(docked: Bool) -> some View {
        SidebarColumnView(
            docked: docked,
            searchText: $sidebarSearch,
            searchFocused: $sidebarSearchFocused,
            workspaceGroups: workspaceGroups,
            activeID: store.selectedProjectID ?? "",
            collapsedSections: $collapsedSections,
            onSelectProject: openProject,
            onToggleSidebar: { if docked { collapseSidebar() } else { dockSidebar() } },
            onSettings: { presentedSheet = .settings }
        )
    }

    private var sidebarRevealLayer: some View {
        ZStack(alignment: .topLeading) {
            if sidebarRevealed {
                sidebar(docked: false)
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background(AppTheme.appBackground)
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

private enum DashboardSheet: String, Identifiable {
    case settings

    var id: String { rawValue }
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
                onSettings: onSettings
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

private struct SidebarView: View {
    @Binding var searchText: String
    let searchFocused: FocusState<Bool>.Binding
    let workspaceGroups: [(name: String, projects: [HunProject])]
    let activeID: String
    @Binding var collapsedSections: Set<String>
    let onSelectProject: (String) -> Void
    let onSettings: () -> Void

    private var allProjects: [HunProject] {
        workspaceGroups.flatMap { $0.projects }
    }

    private var runningCount: Int {
        allProjects.filter { $0.status == .running }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarSearchField(text: $searchText, isFocused: searchFocused)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            AddProjectButton()
                .padding(.horizontal, 6)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(workspaceGroups, id: \.name) { group in
                        section(
                            id: group.name,
                            title: group.name,
                            projects: filtered(group.projects)
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }

            SidebarFooter(
                runningCount: runningCount,
                totalCount: allProjects.count,
                onSettings: onSettings
            )
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
                VStack(spacing: 1) {
                    ForEach(projects) { project in
                        SidebarProjectRow(
                            project: project,
                            selected: project.id == activeID,
                            onTap: { onSelectProject(project.id) }
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

private struct SidebarFooter: View {
    let runningCount: Int
    let totalCount: Int
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("\(totalCount) projects")
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textTertiary)
                .monospacedDigit()
            Spacer()
            ToolbarIconButton(
                systemImage: "gearshape",
                helpText: "Settings (⌘,)",
                action: onSettings
            )
            .accessibilityLabel("Open Settings")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(AppTheme.divider).frame(height: 1)
        }
    }
}

private struct SidebarSearchField: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textPrimary)
                .focused(isFocused)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.searchField)
        )
    }
}

private struct ErrorBanner: View {
    let message: String
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

private struct SidebarSectionHeader: View {
    let title: String
    let isCollapsed: Bool
    let onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? AppTheme.textSecondary : AppTheme.textTertiary.opacity(hovering ? 1 : 0))
                    .frame(width: 10)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .animation(.easeOut(duration: 0.12), value: hovering)
                Image(systemName: isCollapsed ? "folder" : "folder.fill")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
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
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ProjectIconView(
                    name: project.name,
                    iconPath: project.iconPath,
                    size: 17,
                    cornerRadius: 4,
                    emphasized: selected
                )

                Text(project.name)
                    .font(.system(size: 13))
                    .foregroundStyle(textColor)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, 32)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var textColor: Color {
        if selected { return AppTheme.textPrimary }
        if hovering { return AppTheme.textPrimary }
        return AppTheme.textSecondary
    }

    private var rowBackground: Color {
        if selected { return AppTheme.selection }
        if hovering { return AppTheme.hover }
        return .clear
    }
}

// MARK: - Top Bar

private struct TopBarView: View {
    let openProjects: [HunProject]
    @Binding var activeID: String?
    @Binding var mode: HunMode
    let showSidebarControl: Bool
    let onSelect: (String) -> Void
    let onClose: (String) -> Void
    let onToggleSidebar: () -> Void

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
            Text("DEV")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(AppTheme.accent.opacity(0.24))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.42), lineWidth: 1)
                }
                .help("Development build · isolated daemon and data")
            #endif

            ModeSelector(mode: $mode)
        }
        .padding(.trailing, 12)
        .frame(height: 44)
    }
}

private struct ModeSelector: View {
    @Binding var mode: HunMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HunMode.allCases, id: \.self) { option in
                modeButton(option)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.searchField)
        )
        .help(mode.helpText)
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
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(active ? AppTheme.tabActive : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
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
                return event
            default:
                return event
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
                            Circle().fill(hovering ? AppTheme.dividerStrong : Color.clear)
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
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(active ? AppTheme.tabActive : (hovering ? AppTheme.hover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(active ? AppTheme.divider : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
    }
}

private struct ToolbarIconButton: View {
    let systemImage: String
    var helpText: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textTertiary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? AppTheme.hover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText ?? "")
    }
}

// MARK: - Project Detail

private struct ProjectDetailView: View {
    let project: HunProject
    let mode: HunMode
    let pendingAction: HunActionKind?
    @Binding var logSearch: String
    @Binding var selectedServiceID: String?
    @Binding var selectedLogScope: LogScope
    let visibleLogs: [HunLogLine]
    let onFocus: () -> Void
    let onRun: () -> Void
    let onRestart: () -> Void
    let onStop: () -> Void
    let onOpenConfig: () -> Void
    let onChooseLogo: () -> Void
    let onClearLogo: () -> Void
    let onCopyAgentPrompt: () -> Void
    let onRunService: (HunService) -> Void
    let onRestartService: (HunService) -> Void
    let onStopService: (HunService) -> Void
    let onRemoveService: (HunService) -> Void

    private var selectedService: HunService? {
        project.services.first { $0.id == selectedServiceID }
    }

    var body: some View {
        VStack(spacing: 0) {
            ProjectHeaderView(
                project: project,
                mode: mode,
                pendingAction: pendingAction,
                onFocus: onFocus,
                onRun: onRun,
                onRestart: onRestart,
                onStop: onStop,
                onOpenConfig: onOpenConfig,
                onChooseLogo: onChooseLogo,
                onClearLogo: onClearLogo,
                onCopyAgentPrompt: onCopyAgentPrompt
            )

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            HStack(spacing: 0) {
                ServicesPanelView(
                    services: project.services,
                    selectedID: $selectedServiceID,
                    selectedScope: $selectedLogScope,
                    onOpenConfig: onOpenConfig,
                    onRun: onRunService,
                    onRestart: onRestartService,
                    onStop: onStopService,
                    onRemove: onRemoveService
                )
                .frame(width: 320)
                .background(AppTheme.appBackground)

                Rectangle().fill(AppTheme.divider).frame(width: 1)

                LogsPanelView(
                    selectedService: selectedService,
                    scope: $selectedLogScope,
                    logs: visibleLogs,
                    searchText: $logSearch
                )
            }
        }
    }
}

private struct ProjectHeaderView: View {
    let project: HunProject
    let mode: HunMode
    let pendingAction: HunActionKind?
    let onFocus: () -> Void
    let onRun: () -> Void
    let onRestart: () -> Void
    let onStop: () -> Void
    let onOpenConfig: () -> Void
    let onChooseLogo: () -> Void
    let onClearLogo: () -> Void
    let onCopyAgentPrompt: () -> Void

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

        if project.status == .running || project.status == .starting {
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
            VStack(alignment: .leading, spacing: 6) {
                Text(project.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                HStack(spacing: 14) {
                    StatusMetaItem(status: project.status)
                    MetaItem(icon: "arrow.triangle.branch", text: project.branch)
                    MetaItem(icon: "folder", text: collapsePath(project.path))
                }

                if let configError = project.configError {
                    Label(configError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.danger)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
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
                ActionButton(title: "Config", systemImage: "square.and.pencil", style: .secondary, action: onOpenConfig)
                LogoMenuButton(
                    canReset: project.iconIsCustom,
                    onChoose: onChooseLogo,
                    onClear: onClearLogo
                )
                AgentPromptButton(action: onCopyAgentPrompt)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
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

private enum ActionStyle { case primary, secondary, danger }

private struct ActionButton: View {
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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
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

private struct LogoMenuButton: View {
    let canReset: Bool
    let onChoose: () -> Void
    let onClear: () -> Void

    var body: some View {
        Menu {
            Button("Choose Logo…", action: onChoose)
            if canReset {
                Divider()
                Button("Reset Logo", action: onClear)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "photo")
                    .font(.system(size: 10, weight: .semibold))
                Text("Logo")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.buttonFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

private struct AgentPromptButton: View {
    let action: () -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button {
            action()
            withAnimation(.easeOut(duration: 0.16)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeIn(duration: 0.18)) { copied = false }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: copied ? "checkmark" : "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 11)
                Text(copied ? "Copied" : "Agent")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(copied ? AppTheme.success : (hovering ? AppTheme.textPrimary : AppTheme.textSecondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? AppTheme.hover : AppTheme.buttonFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(copied ? AppTheme.success.opacity(0.35) : AppTheme.divider, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy agent prompt for .hun.yml")
    }
}

// MARK: - Services Panel

private struct ServicesPanelView: View {
    let services: [HunService]
    @Binding var selectedID: String?
    @Binding var selectedScope: LogScope
    let onOpenConfig: () -> Void
    let onRun: (HunService) -> Void
    let onRestart: (HunService) -> Void
    let onStop: (HunService) -> Void
    let onRemove: (HunService) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Services")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Text("\(services.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                ToolbarIconButton(
                    systemImage: "square.and.pencil",
                    helpText: "Open .hun.yml",
                    action: onOpenConfig
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(services) { service in
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
                            onOpenConfig: onOpenConfig
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
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
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(service.status.color).frame(width: 6, height: 6)
                        Text(service.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text(service.status.title.lowercased())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    Text(service.command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 12) {
                        MetaItem(icon: "number", text: service.pidText)
                        MetaItem(icon: "network", text: service.portText)
                        MetaItem(
                            icon: service.ready ? "checkmark.circle" : "circle.dashed",
                            text: service.ready ? "ready" : "waiting"
                        )
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? AppTheme.selection : (hovering ? AppTheme.hover : Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? AppTheme.divider : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let url = service.browserURL {
                ServiceBrowserButton(url: url, isVisible: hovering)
                    .padding(.bottom, 4)
                    .padding(.trailing, 4)
            }
        }
        .onHover { hovering = $0 }
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
}

private struct ServiceBrowserButton: View {
    let url: URL
    let isVisible: Bool
    @Environment(\.openURL) private var openURL
    @State private var hovering = false
    @FocusState private var keyboardFocused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool

    private var revealed: Bool {
        isVisible || keyboardFocused || accessibilityFocused
    }

    var body: some View {
        Button {
            openURL(url)
        } label: {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textTertiary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? AppTheme.hover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($keyboardFocused)
        .accessibilityFocused($accessibilityFocused)
        .onHover { hovering = $0 }
        .opacity(revealed ? 1 : 0)
        .allowsHitTesting(revealed)
        .accessibilityHidden(false)
        .animation(.easeOut(duration: 0.12), value: revealed)
        .help("Open \(url.absoluteString) in the default browser")
        .accessibilityLabel("Open \(url.absoluteString) in browser")
    }
}

// MARK: - Logs Panel

private struct LogsPanelView: View {
    let selectedService: HunService?
    @Binding var scope: LogScope
    let logs: [HunLogLine]
    @Binding var searchText: String

    @State private var copyConfirmCount: Int = 0
    @State private var copyConfirmStamp: Date?

    private var title: String {
        scope == .combined ? "All logs" : (selectedService?.name ?? "Logs")
    }

    /// Identity for the tail view so it resets (and re-tails) when the user
    /// switches scope or service, instead of carrying over a stale paused state.
    private var tailIdentity: String {
        scope == .combined ? "combined" : "service|\(selectedService?.id ?? "")"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                LogSearchField(text: $searchText)
                    .frame(maxWidth: 200)

                CopyLogsButton(
                    label: "Copy all",
                    confirmCount: copyConfirmCount,
                    confirmStamp: copyConfirmStamp,
                    enabled: !logs.isEmpty,
                    action: copyAllLogs
                )

                ScopeSegmented(scope: $scope)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            if logs.isEmpty {
                LogsEmptyState()
            } else {
                LogsTailContainer(
                    logs: logs,
                    showService: scope == .combined,
                    highlight: searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                .id(tailIdentity)
            }
        }
        .background(AppTheme.appBackground)
    }

    private func copyAllLogs() {
        guard !logs.isEmpty else { return }
        let text = logs
            .map { "\($0.time)  \($0.service.padding(toLength: 10, withPad: " ", startingAt: 0))  \($0.message)" }
            .joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copyConfirmCount = logs.count
        copyConfirmStamp = Date()
    }
}

private struct LogSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textPrimary)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: LogsToolbarMetrics.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppTheme.searchField)
        )
    }
}

private enum LogsToolbarMetrics {
    static let controlHeight: CGFloat = 24
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
            RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(scope == s ? AppTheme.tabActive : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CopyLogsButton: View {
    let label: String
    let confirmCount: Int
    let confirmStamp: Date?
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false
    @State private var showingConfirm = false

    var body: some View {
        Button(action: {
            action()
            withAnimation(.easeOut(duration: 0.18)) { showingConfirm = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeIn(duration: 0.25)) { showingConfirm = false }
            }
        }) {
            HStack(spacing: 5) {
                ZStack {
                    Image(systemName: "doc.on.doc")
                        .opacity(showingConfirm ? 0 : 1)
                        .scaleEffect(showingConfirm ? 0.6 : 1)
                    Image(systemName: "checkmark")
                        .opacity(showingConfirm ? 1 : 0)
                        .scaleEffect(showingConfirm ? 1 : 0.6)
                        .foregroundStyle(AppTheme.success)
                }
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 12, height: 12)

                Text(showingConfirm ? confirmText : label)
                    .font(.system(size: 11, weight: .medium))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(showingConfirm ? AppTheme.success : (hovering ? AppTheme.textPrimary : AppTheme.textSecondary))
            .padding(.horizontal, 9)
            .frame(height: LogsToolbarMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? AppTheme.hover : AppTheme.searchField)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(showingConfirm ? AppTheme.success.opacity(0.3) : AppTheme.divider, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .help(label.hasPrefix("Copy ") && !label.contains("all") ? "Copy selected lines" : "Copy all visible logs (⌘C)")
    }

    private var confirmText: String {
        confirmCount == 1 ? "Copied" : "Copied \(confirmCount)"
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

// MARK: - Native log text view

private struct LogsTailContainer: View {
    let logs: [HunLogLine]
    let showService: Bool
    let highlight: String

    @State private var isTailing = true
    @State private var newSincePause = 0
    @State private var lastSeenCount = 0
    @State private var scrollTrigger = 0
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LogsTextView(
                logs: logs,
                showService: showService,
                highlight: highlight,
                hovering: hovering,
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
        .onHover { hovering = $0 }
        .onAppear { lastSeenCount = logs.count }
        .onChange(of: logs.count) { old, new in
            guard new != old else { return }
            if !isTailing && new > old {
                newSincePause += (new - old)
            }
            lastSeenCount = new
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
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(hovering ? 0.22 : 0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .scaleEffect(hovering ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Resume following the latest logs (jump to bottom)")
    }
}

private struct LogsTextView: NSViewRepresentable {
    let logs: [HunLogLine]
    let showService: Bool
    let highlight: String
    let hovering: Bool
    @Binding var isTailing: Bool
    let scrollTrigger: Int

    final class Coordinator: NSObject {
        var lastSignature: String = ""
        var lastTrigger: Int = .min
        weak var scrollView: NSScrollView?
        weak var scroller: ThinLogScroller?
        weak var textView: LogsTextViewKit?
        var setTailing: ((Bool) -> Void)?
        var currentTailing: () -> Bool = { false }

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

    private var signature: String {
        let lastID = logs.last.map { String(describing: $0.id) } ?? ""
        return "\(logs.count)|\(lastID)|\(showService)|\(highlight)"
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(AppTheme.appBackground)
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let scroller = ThinLogScroller()
        scroll.verticalScroller = scroller
        scroller.alphaValue = 0

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
        context.coordinator.scroller = scroller
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
            .foregroundColor: NSColor(white: 0.96, alpha: 1)
        ]

        let (attr, ranges) = buildAttributedString()
        textView.textStorage?.setAttributedString(attr)
        textView.lastLineRange = ranges.last
        context.coordinator.lastSignature = signature
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

        if let scroller = scroll.verticalScroller as? ThinLogScroller {
            scroller.setVisible(hovering, animated: true)
        }

        if scrollTrigger != coord.lastTrigger {
            coord.lastTrigger = scrollTrigger
            DispatchQueue.main.async { scrollToBottom(scroll: scroll) }
        }

        guard coord.lastSignature != signature else { return }
        guard let textView = scroll.documentView as? LogsTextViewKit else { return }
        let (attr, ranges) = buildAttributedString()
        textView.textStorage?.setAttributedString(attr)
        textView.lastLineRange = ranges.last
        coord.lastSignature = signature
        if isTailing {
            DispatchQueue.main.async { scrollToBottom(scroll: scroll) }
        }
    }

    private func scrollToBottom(scroll: NSScrollView) {
        guard let textView = scroll.documentView as? NSTextView,
              let storage = textView.textStorage else { return }
        textView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
    }

    // MARK: - Attributed string

    private static let timeFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let bodyFont: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let serviceFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .medium)

    private static let highlightBackground = NSColor(red: 0.99, green: 0.80, blue: 0.30, alpha: 0.32)
    private static let highlightForeground = NSColor(white: 0.99, alpha: 1)

    private func buildAttributedString() -> (NSAttributedString, [NSRange]) {
        let result = NSMutableAttributedString()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1.5
        paragraph.headIndent = serviceColumnWidth + timeColumnWidth + 4
        paragraph.firstLineHeadIndent = 0

        let query = highlight.trimmingCharacters(in: .whitespacesAndNewlines)

        var ranges: [NSRange] = []
        ranges.reserveCapacity(logs.count)

        for (idx, line) in logs.enumerated() {
            let isLast = idx == logs.count - 1
            let lineStart = result.length

            // Time
            let timeText = (line.time as NSString).padding(toLength: 13, withPad: " ", startingAt: 0)
            result.append(NSAttributedString(string: timeText + "  ", attributes: [
                .font: Self.timeFont,
                .foregroundColor: NSColor(AppTheme.logTimestamp),
                .paragraphStyle: paragraph
            ]))

            // Service (combined view)
            if showService {
                let serviceStart = result.length
                let svc = (line.service as NSString).padding(toLength: 10, withPad: " ", startingAt: 0)
                result.append(NSAttributedString(string: svc + "  ", attributes: [
                    .font: Self.serviceFont,
                    .foregroundColor: serviceAccent(for: line.service),
                    .paragraphStyle: paragraph
                ]))
                highlightMatches(in: result, plain: line.service, startLocation: serviceStart, query: query)
            }

            // Message
            let messageStart = result.length
            let trailing = isLast ? "" : "\n"
            result.append(NSAttributedString(string: line.message + trailing, attributes: [
                .font: Self.bodyFont,
                .foregroundColor: messageColor(for: line.level),
                .paragraphStyle: paragraph
            ]))
            highlightMatches(in: result, plain: line.message, startLocation: messageStart, query: query)

            let lineEnd = result.length - (trailing.isEmpty ? 0 : 1)
            ranges.append(NSRange(location: lineStart, length: lineEnd - lineStart))
        }

        return (result, ranges)
    }

    /// Applies a search highlight to every case-insensitive occurrence of
    /// `query` within `plain`, offset to its position in `result`.
    private func highlightMatches(in result: NSMutableAttributedString, plain: String, startLocation: Int, query: String) {
        guard !query.isEmpty else { return }
        let haystack = plain as NSString
        var searchStart = 0
        while searchStart < haystack.length {
            let scope = NSRange(location: searchStart, length: haystack.length - searchStart)
            let found = haystack.range(of: query, options: [.caseInsensitive], range: scope)
            if found.location == NSNotFound { break }
            result.addAttributes(
                [
                    .backgroundColor: Self.highlightBackground,
                    .foregroundColor: Self.highlightForeground
                ],
                range: NSRange(location: startLocation + found.location, length: found.length)
            )
            searchStart = found.location + max(found.length, 1)
        }
    }

    private var timeColumnWidth: CGFloat { 110 }
    private var serviceColumnWidth: CGFloat { showService ? 100 : 0 }

    private func messageColor(for level: LogLevel) -> NSColor {
        switch level {
        case .error: return NSColor(AppTheme.danger)
        case .warning: return NSColor(AppTheme.warning)
        case .info: return NSColor(AppTheme.logText)
        }
    }

    private func serviceAccent(for service: String) -> NSColor {
        let palette: [NSColor] = [
            NSColor(red: 0.45, green: 0.55, blue: 0.95, alpha: 1),
            NSColor(red: 0.95, green: 0.55, blue: 0.50, alpha: 1),
            NSColor(red: 0.45, green: 0.78, blue: 0.65, alpha: 1),
            NSColor(red: 0.85, green: 0.65, blue: 0.45, alpha: 1),
            NSColor(red: 0.72, green: 0.55, blue: 0.92, alpha: 1)
        ]
        let idx = abs(service.hashValue) % palette.count
        return palette[idx]
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    let projectCount: Int
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AppTheme.textTertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)
            if projectCount == 0 {
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
        projectCount == 0 ? "No projects found" : "No project selected"
    }

    private var message: String {
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

// MARK: - Custom slim scroller for the log view

final class ThinLogScroller: NSScroller {
    private var currentVisible = false

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        return 11
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        guard currentVisible != visible else { return }
        currentVisible = visible
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.allowsImplicitAnimation = true
                self.animator().alphaValue = visible ? 1 : 0
            }
        } else {
            self.alphaValue = visible ? 1 : 0
        }
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // intentionally no track
    }

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        let pillWidth: CGFloat = 3.5
        let pill = NSRect(
            x: knobRect.midX - pillWidth / 2,
            y: knobRect.minY + 3,
            width: pillWidth,
            height: max(24, knobRect.height - 6)
        )
        let path = NSBezierPath(roundedRect: pill, xRadius: pillWidth / 2, yRadius: pillWidth / 2)
        let pressed = (NSEvent.pressedMouseButtons & 0x1) != 0
        NSColor.white.withAlphaComponent(pressed ? 0.34 : 0.20).setFill()
        path.fill()
    }
}

#Preview {
    ContentView()
        .environment(HunStore(startAutomatically: false))
        .frame(width: 1200, height: 760)
}
