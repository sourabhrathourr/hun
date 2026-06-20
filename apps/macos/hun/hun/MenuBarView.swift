import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(HunStore.self) private var store
    @AppStorage("hun.menu.collapsedWorkspaceGroups") private var collapsedWorkspaceGroupsData = ""

    private var workspaceGroups: [(name: String, projects: [HunProject])] {
        let grouped = Dictionary(grouping: store.model.projects) { project -> String in
            let parts = project.path.split(separator: "/")
            guard parts.count >= 2 else { return "Projects" }
            return String(parts[parts.count - 2])
        }
        return grouped
            .map { (humanize($0.key), $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.name < $1.name }
    }

    private func humanize(_ s: String) -> String {
        s.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            MenuBarHeader(mode: $store.globalMode)

            divider

            FocusBanner(
                focused: store.focusedProject,
                mode: store.globalMode,
                pendingAction: store.focusedProject.flatMap { store.projectAction(for: $0) },
                onStop: {
                    if let project = store.focusedProject {
                        store.stop(project)
                    }
                }
            )

            divider

            SleekMenuScrollView(maxHeight: 292) {
                VStack(spacing: 14) {
                    ForEach(workspaceGroups, id: \.name) { group in
                        WorkspaceSection(
                            title: group.name,
                            projects: group.projects,
                            mode: store.globalMode,
                            isCollapsed: isWorkspaceGroupCollapsed(group.name),
                            pendingAction: { store.projectAction(for: $0) },
                            onToggleCollapse: { toggleWorkspaceGroup(group.name) },
                            onSwitch: { store.focus($0) },
                            onRun: { store.run($0) },
                            onStop: { store.stop($0) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }

            divider

            MenuBarFooter()
        }
        .frame(width: 320)
        .background(Color(hex: 0x060606))
        .preferredColorScheme(.dark)
        .task {
            await store.refresh(force: true)
        }
    }

    private var divider: some View {
        Rectangle().fill(AppTheme.divider).frame(height: 1)
    }

    private var collapsedWorkspaceGroups: Set<String> {
        Set(collapsedWorkspaceGroupsData.split(separator: "\n").map(String.init))
    }

    private func isWorkspaceGroupCollapsed(_ title: String) -> Bool {
        collapsedWorkspaceGroups.contains(title)
    }

    private func toggleWorkspaceGroup(_ title: String) {
        var groups = collapsedWorkspaceGroups
        if groups.contains(title) {
            groups.remove(title)
        } else {
            groups.insert(title)
        }

        withAnimation(.easeOut(duration: 0.14)) {
            collapsedWorkspaceGroupsData = groups.sorted().joined(separator: "\n")
        }
    }
}

private struct SleekMenuScrollView<Content: View>: View {
    let maxHeight: CGFloat
    let content: Content

    @State private var contentHeight: CGFloat
    @State private var viewportHeight: CGFloat
    @State private var contentOffset: CGFloat = 0
    @State private var hovering = false

    init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
        self._contentHeight = State(initialValue: maxHeight)
        self._viewportHeight = State(initialValue: maxHeight)
    }

    var body: some View {
        AppKitMenuScrollView(
            contentHeight: $contentHeight,
            viewportHeight: $viewportHeight,
            contentOffset: $contentOffset
        ) {
            content
        }
        .frame(height: scrollHeight)
        .overlay(alignment: .trailing) {
            if canScroll && hovering {
                MenuScrollIndicator(
                    viewportHeight: viewportHeight,
                    contentHeight: contentHeight,
                    contentOffset: contentOffset,
                    emphasized: hovering
                )
                .padding(.trailing, 3)
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
    }

    private var canScroll: Bool {
        contentHeight > viewportHeight + 1
    }

    private var scrollHeight: CGFloat {
        min(maxHeight, max(1, contentHeight))
    }
}

private struct AppKitMenuScrollView<Content: View>: NSViewRepresentable {
    @Binding var contentHeight: CGFloat
    @Binding var viewportHeight: CGFloat
    @Binding var contentOffset: CGFloat
    let content: Content

    init(
        contentHeight: Binding<CGFloat>,
        viewportHeight: Binding<CGFloat>,
        contentOffset: Binding<CGFloat>,
        @ViewBuilder content: () -> Content
    ) {
        self._contentHeight = contentHeight
        self._viewportHeight = viewportHeight
        self._contentOffset = contentOffset
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            contentHeight: $contentHeight,
            viewportHeight: $viewportHeight,
            contentOffset: $contentOffset
        )
    }

    func makeNSView(context: Context) -> NoScrollerScrollView {
        let scrollView = NoScrollerScrollView()
        let documentView = FlippedDocumentView(frame: .zero)
        let hostingView = NSHostingView(rootView: content)

        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        documentView.addSubview(hostingView)
        scrollView.documentView = documentView

        context.coordinator.install(
            scrollView: scrollView,
            documentView: documentView,
            hostingView: hostingView
        )

        DispatchQueue.main.async {
            context.coordinator.updateLayout()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NoScrollerScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = content
        scrollView.disableNativeScrollers()

        DispatchQueue.main.async {
            context.coordinator.updateLayout()
        }
    }

    final class Coordinator: NSObject {
        var hostingView: NSHostingView<Content>?

        private weak var scrollView: NoScrollerScrollView?
        private weak var documentView: FlippedDocumentView?
        private var boundsObserver: NSObjectProtocol?
        private var layoutScheduled = false
        private var contentHeight: Binding<CGFloat>
        private var viewportHeight: Binding<CGFloat>
        private var contentOffset: Binding<CGFloat>

        init(
            contentHeight: Binding<CGFloat>,
            viewportHeight: Binding<CGFloat>,
            contentOffset: Binding<CGFloat>
        ) {
            self.contentHeight = contentHeight
            self.viewportHeight = viewportHeight
            self.contentOffset = contentOffset
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func install(
            scrollView: NoScrollerScrollView,
            documentView: FlippedDocumentView,
            hostingView: NSHostingView<Content>
        ) {
            self.scrollView = scrollView
            self.documentView = documentView
            self.hostingView = hostingView
            scrollView.onLayout = { [weak self] in
                self?.scheduleLayout()
            }

            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleLayout()
            }
        }

        func scheduleLayout() {
            guard !layoutScheduled else { return }
            layoutScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.layoutScheduled = false
                self?.updateLayout()
            }
        }

        func updateLayout() {
            guard let scrollView, let documentView, let hostingView else { return }

            scrollView.disableNativeScrollers()

            let viewportSize = scrollView.contentView.bounds.size
            let width = max(1, viewportSize.width)
            hostingView.frame.size.width = width
            let measuredHeight = max(1, hostingView.fittingSize.height)
            let documentHeight = max(measuredHeight, viewportSize.height)

            documentView.frame = NSRect(x: 0, y: 0, width: width, height: documentHeight)
            hostingView.frame = documentView.bounds

            setMetrics(
                contentHeight: measuredHeight,
                viewportHeight: max(1, viewportSize.height),
                contentOffset: -scrollView.contentView.bounds.origin.y
            )
        }

        private func setMetrics(contentHeight: CGFloat, viewportHeight: CGFloat, contentOffset: CGFloat) {
            DispatchQueue.main.async {
                if abs(self.contentHeight.wrappedValue - contentHeight) > 0.5 {
                    self.contentHeight.wrappedValue = contentHeight
                }
                if abs(self.viewportHeight.wrappedValue - viewportHeight) > 0.5 {
                    self.viewportHeight.wrappedValue = viewportHeight
                }
                if abs(self.contentOffset.wrappedValue - contentOffset) > 0.5 {
                    self.contentOffset.wrappedValue = contentOffset
                }
            }
        }
    }
}

private final class NoScrollerScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layout() {
        super.layout()
        disableNativeScrollers()
        onLayout?()
    }

    override func tile() {
        disableNativeScrollers()
        super.tile()
        disableNativeScrollers()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        disableNativeScrollers()
        onLayout?()
    }

    override func flashScrollers() {}

    func disableNativeScrollers() {
        hasVerticalScroller = false
        hasHorizontalScroller = false
        verticalScroller = nil
        horizontalScroller = nil
    }

    private func configure() {
        drawsBackground = false
        borderType = .noBorder
        autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollerStyle = .overlay
        verticalScrollElasticity = .automatic
        horizontalScrollElasticity = .none
        usesPredominantAxisScrolling = true
        contentView.postsBoundsChangedNotifications = true
        disableNativeScrollers()
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private struct MenuScrollIndicator: View {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let contentOffset: CGFloat
    let emphasized: Bool

    private var trackHeight: CGFloat {
        max(1, viewportHeight - 12)
    }

    private var thumbHeight: CGFloat {
        let proportional = trackHeight * min(1, viewportHeight / max(contentHeight, 1))
        return min(trackHeight, max(44, proportional))
    }

    private var thumbOffset: CGFloat {
        let maxScroll = max(contentHeight - viewportHeight, 1)
        let travel = max(trackHeight - thumbHeight, 0)
        let scrolled = min(max(-contentOffset, 0), maxScroll)
        return (scrolled / maxScroll) * travel
    }

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(0.10))
                .frame(width: 3, height: trackHeight)

            Capsule()
                .fill(Color.white.opacity(emphasized ? 0.52 : 0.42))
                .frame(width: 3, height: thumbHeight)
                .offset(y: thumbOffset)
        }
        .frame(width: 8, height: viewportHeight)
        .animation(.easeOut(duration: 0.16), value: emphasized)
        .animation(.easeOut(duration: 0.10), value: thumbOffset)
    }
}

private struct MenuBarHeader: View {
    @Binding var mode: HunMode

    var body: some View {
        HStack(spacing: 10) {
            Text("hun")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            ModeSegmented(mode: $mode)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct ModeSegmented: View {
    @Binding var mode: HunMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HunMode.allCases, id: \.self) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { mode = option }
                } label: {
                    Text(option.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(mode == option ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(mode == option ? AppTheme.tabActive : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppTheme.searchField)
        )
    }
}

private struct FocusBanner: View {
    let focused: HunProject?
    let mode: HunMode
    let pendingAction: HunActionKind?
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let focused {
                ProjectAvatar(project: focused)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(focused.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(mode == .focus ? "focused" : "active")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                    Text(metaLine(focused))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 0)
                if focused.status == .running || pendingAction == .stopProject {
                    BannerStopButton(
                        isLoading: pendingAction == .stopProject,
                        action: onStop
                    )
                }
            } else {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(AppTheme.searchField)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("No active project")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(mode.helpText)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func metaLine(_ project: HunProject) -> String {
        switch project.status {
        case _ where pendingAction == .stopProject:
            return "Stopping..."
        case .running:
            return "Running"
        case .crashed: return "Crashed · needs restart"
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        }
    }
}

private struct BannerStopButton: View {
    let isLoading: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .scaleEffect(0.58)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(hovering ? AppTheme.danger : AppTheme.textSecondary)
                }
            }
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? AppTheme.danger.opacity(0.12) : AppTheme.buttonFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(hovering ? AppTheme.danger.opacity(0.35) : AppTheme.divider, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering = $0 }
        .help(isLoading ? "Stopping" : "Stop project")
    }
}

private struct WorkspaceSection: View {
    let title: String
    let projects: [HunProject]
    let mode: HunMode
    let isCollapsed: Bool
    let pendingAction: (HunProject) -> HunActionKind?
    let onToggleCollapse: () -> Void
    let onSwitch: (HunProject) -> Void
    let onRun: (HunProject) -> Void
    let onStop: (HunProject) -> Void
    @State private var hoveringHeader = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onToggleCollapse) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 10)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hoveringHeader ? AppTheme.hover : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringHeader = $0 }
            .help(isCollapsed ? "Expand \(title)" : "Collapse \(title)")

            if !isCollapsed {
                ForEach(projects) { project in
                    MenuBarProjectRow(
                        project: project,
                        mode: mode,
                        pendingAction: pendingAction(project),
                        onSwitch: { onSwitch(project) },
                        onRun: { onRun(project) },
                        onStop: { onStop(project) }
                    )
                }
            }
        }
    }
}

private struct MenuBarProjectRow: View {
    let project: HunProject
    let mode: HunMode
    let pendingAction: HunActionKind?
    let onSwitch: () -> Void
    let onRun: () -> Void
    let onStop: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ProjectAvatar(project: project)

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13, weight: project.isActive ? .medium : .regular))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(secondary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let pendingAction {
                QuickActionButton(
                    title: pendingButtonTitle(for: pendingAction),
                    systemImage: pendingButtonIcon(for: pendingAction),
                    style: pendingAction == .stopProject ? .danger : .primary,
                    isLoading: true,
                    isDisabled: true,
                    action: {}
                )
            } else if hovering {
                primaryAction
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? AppTheme.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if project.status == .running {
            QuickActionButton(title: "Stop", systemImage: "stop.fill", style: .danger, action: onStop)
        } else if mode == .focus {
            QuickActionButton(title: "Switch", systemImage: "bolt.fill", style: .primary, action: onSwitch)
        } else {
            QuickActionButton(title: "Run", systemImage: "play.fill", style: .primary, action: onRun)
        }
    }

    private var secondary: String {
        switch project.status {
        case _ where pendingAction != nil:
            return pendingAction?.statusText ?? "Working..."
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .crashed: return "Crashed"
        case .starting: return "Starting…"
        }
    }

    private func pendingButtonTitle(for action: HunActionKind) -> String {
        switch action {
        case .startProject:
            return mode == .focus ? "Switch" : "Run"
        case .stopProject:
            return "Stop"
        case .restartProject:
            return "Restart"
        default:
            return "Run"
        }
    }

    private func pendingButtonIcon(for action: HunActionKind) -> String {
        switch action {
        case .startProject:
            return mode == .focus ? "bolt.fill" : "play.fill"
        case .stopProject:
            return "stop.fill"
        case .restartProject:
            return "arrow.clockwise"
        default:
            return "play.fill"
        }
    }
}

private enum QuickActionStyle { case primary, danger }

private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let style: QuickActionStyle
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
                        .scaleEffect(0.55)
                        .frame(width: 9, height: 9)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 9, height: 9)
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isLoading ? 0.55 : 1)
        .onHover { hovering = $0 }
    }

    private var textColor: Color {
        switch style {
        case .primary: return .white
        case .danger: return hovering ? AppTheme.danger : AppTheme.textSecondary
        }
    }

    private var background: Color {
        switch style {
        case .primary: return AppTheme.accent.opacity(hovering ? 1 : 0.92)
        case .danger: return hovering ? AppTheme.danger.opacity(0.12) : AppTheme.buttonFill
        }
    }

    private var border: Color {
        switch style {
        case .primary: return Color.white.opacity(0.10)
        case .danger: return hovering ? AppTheme.danger.opacity(0.4) : AppTheme.divider
        }
    }
}

private struct ProjectAvatar: View {
    let project: HunProject

    var body: some View {
        ProjectIconView(
            name: project.name,
            iconPath: project.iconPath,
            size: 22,
            cornerRadius: 5,
            emphasized: project.isActive,
            status: project.status
        )
    }
}

private struct MenuBarFooter: View {
    var body: some View {
        VStack(spacing: 0) {
            FooterRow(
                title: "Open Dashboard",
                systemImage: "macwindow",
                shortcut: "⌘D",
                action: { hunApp.openDashboard() }
            )
            FooterRow(
                title: "Quit hun",
                systemImage: "power",
                shortcut: "⌘Q",
                action: { NSApp.terminate(nil) }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

private struct FooterRow: View {
    let title: String
    let systemImage: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(shortcut)
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? AppTheme.hover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

#Preview {
    MenuBarView()
        .environment(HunStore(startAutomatically: false))
}
