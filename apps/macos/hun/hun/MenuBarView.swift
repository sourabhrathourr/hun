import SwiftUI
import AppKit

/// The menu bar panel: what's running, a quick way to run or stop anything,
/// and the way into the dashboard.
struct MenuBarView: View {
    @Environment(HunStore.self) private var store
    @State private var query = ""

    private var projects: [HunProject] {
        store.model.projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var running: [HunProject] {
        projects.filter { $0.status != .stopped || store.projectAction(for: $0) == .stopProject }
    }

    private var others: [HunProject] {
        let rest = projects.filter { project in !running.contains { $0.id == project.id } }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return rest }
        return rest.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    /// Search appears once the list is long enough to need it.
    private var showsSearch: Bool { projects.count - running.count > 6 }

    var body: some View {
        VStack(spacing: 0) {
            MenuHeader(
                runningCount: running.filter { $0.status != .crashed }.count,
                crashedCount: running.filter { $0.status == .crashed }.count,
                mode: Binding(
                    get: { store.displayedMode },
                    set: { store.changeMode($0, preferredProject: nil) }
                ),
                isModePending: store.isChangingMode
            )

            if projects.isEmpty {
                MenuEmptyState()
            } else {
                SleekMenuScrollView(maxHeight: 380) {
                    VStack(alignment: .leading, spacing: 0) {
                        if !running.isEmpty {
                            MenuSectionLabel(title: "Running")
                            ForEach(running) { project in
                                row(project)
                            }
                        }
                        if !running.isEmpty && !(others.isEmpty && query.isEmpty) {
                            Spacer().frame(height: 10)
                        }
                        if showsSearch {
                            MenuSearchField(text: $query)
                                .padding(.horizontal, 4)
                                .padding(.bottom, 6)
                        }
                        if !others.isEmpty {
                            if !running.isEmpty || showsSearch {
                                MenuSectionLabel(title: "Projects")
                            }
                            ForEach(others) { project in
                                row(project)
                            }
                        } else if !query.isEmpty {
                            Text("No projects match")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textTertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
                }
            }

            MenuDivider()
            MenuFooter()
        }
        .frame(width: 340)
        .background(AppTheme.menuBackground)
    }

    private func row(_ project: HunProject) -> some View {
        MenuProjectRow(
            project: project,
            mode: store.globalMode,
            pendingAction: store.projectAction(for: project),
            onOpen: {
                store.selectProject(project.id)
                hunApp.openDashboard()
            },
            onRun: { store.globalMode == .focus ? store.focus(project) : store.run(project) },
            onStop: { store.stop(project) },
            onRestart: { store.restart(project) }
        )
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
                    contentOffset: contentOffset
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
                .fill(
                    Color(nsColor: .labelColor)
                        .opacity(HunScrollStyleMetrics.thumbOpacity)
                )
                .frame(width: HunScrollStyleMetrics.thumbWidth, height: thumbHeight)
                .offset(y: thumbOffset)
        }
        .frame(width: 8, height: viewportHeight)
        .animation(.easeOut(duration: 0.10), value: thumbOffset)
    }
}

// MARK: - Header

private struct MenuHeader: View {
    let runningCount: Int
    let crashedCount: Int
    @Binding var mode: HunMode
    let isModePending: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Hun")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textTertiary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            MenuModeSwitch(mode: $mode, isPending: isModePending)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var summary: String {
        let running: String
        switch runningCount {
        case 0: running = crashedCount == 0 ? "Nothing running" : "Nothing else running"
        case 1: running = "1 project running"
        default: running = "\(runningCount) projects running"
        }
        guard crashedCount > 0 else { return running }
        return "\(running) · \(crashedCount) crashed"
    }
}

private struct MenuModeSwitch: View {
    @Binding var mode: HunMode
    let isPending: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HunMode.allCases, id: \.self) { option in
                let active = mode == option
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { mode = option }
                } label: {
                    Text(option.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(active ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(maxHeight: .infinity)
                        .background(HunRoundedShape().fill(active ? AppTheme.tabActive : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.helpText)
            }
        }
        .padding(2)
        .frame(height: 24)
        .background(HunRoundedShape().fill(AppTheme.searchField))
        .disabled(isPending)
        .opacity(isPending ? 0.6 : 1)
    }
}

// MARK: - Rows

private struct MenuSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.textTertiary)
            // Lines up with the project icons below.
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }
}

/// One project. The row opens it in the dashboard; its action (run, switch,
/// stop, restart) appears on hover, and stays while it's in progress.
private struct MenuProjectRow: View {
    let project: HunProject
    let mode: HunMode
    let pendingAction: HunActionKind?
    let onOpen: () -> Void
    let onRun: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    @State private var hovering = false

    private var isRunning: Bool { project.status == .running || project.status == .starting }

    var body: some View {
        HStack(spacing: 10) {
            ProjectIconView(
                name: project.name,
                iconPath: project.iconPath,
                size: 20,
                cornerRadius: 5,
                emphasized: false,
                status: project.status
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13, weight: isRunning ? .medium : .regular))
                    .foregroundStyle(isRunning || hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 6)

            trailing
        }
        .padding(.horizontal, 8)
        .frame(minHeight: detail == nil ? 32 : 42)
        .background(HunRoundedShape().fill(hovering ? AppTheme.rowHover : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .help("Open \(project.name) in Hun")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open in Hun", onOpen)
    }

    /// Running projects say what's running; stopped ones stay one line.
    private var detail: String? {
        if let pendingAction { return pendingAction.statusText }
        switch project.status {
        case .running:
            let count = project.services.filter { $0.status == .running || $0.status == .starting }.count
            let services = count == 1 ? "1 service" : "\(count) services"
            return [project.profile, services].compactMap { $0 }.joined(separator: " · ")
        case .starting: return "Starting…"
        case .crashed: return "Crashed"
        case .stopped: return nil
        }
    }

    private var detailColor: Color {
        project.status == .crashed && pendingAction == nil ? AppTheme.danger : AppTheme.textTertiary
    }

    /// The first running service that serves a page.
    private var webService: HunService? {
        project.services.first { $0.status == .running && $0.browserURL != nil }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 4) {
            if let service = webService, let url = service.browserURL, pendingAction == nil {
                MenuPortChip(port: service.port, url: url, serviceName: service.name)
            }
            if let pendingAction {
                MenuIconButton(systemImage: icon(for: pendingAction), help: pendingAction.progressTitle, isLoading: true) {}
            } else if project.status == .crashed {
                // Restart stays in view; Stop clears the crash.
                if hovering {
                    MenuIconButton(systemImage: "stop.fill", help: "Stop \(project.name)", tone: .danger, action: onStop)
                }
                MenuIconButton(systemImage: "arrow.clockwise", help: "Restart \(project.name)", action: onRestart)
            } else if hovering {
                action
            }
        }
    }

    @ViewBuilder
    private var action: some View {
        switch project.status {
        case .running, .starting:
            MenuIconButton(systemImage: "stop.fill", help: "Stop \(project.name)", tone: .danger, action: onStop)
        case .crashed:
            MenuIconButton(systemImage: "arrow.clockwise", help: "Restart \(project.name)", action: onRestart)
        case .stopped:
            MenuIconButton(
                systemImage: mode == .focus ? "bolt.fill" : "play.fill",
                help: mode == .focus ? "Switch to \(project.name)" : "Run \(project.name)",
                action: onRun
            )
        }
    }

    private func icon(for action: HunActionKind) -> String {
        switch action {
        case .stopProject, .stopService: return "stop.fill"
        case .restartProject, .restartService: return "arrow.clockwise"
        default: return "play.fill"
        }
    }
}

/// The port a running project serves, opening it in the browser.
private struct MenuPortChip: View {
    let port: Int
    let url: URL
    let serviceName: String
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 3) {
                Text(verbatim: ":\(port)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(hovering ? 1 : 0.6)
            }
            .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(HunRoundedShape().fill(hovering ? AppTheme.hover : AppTheme.searchField))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(serviceName) at \(url.absoluteString)")
    }
}

private struct MenuIconButton: View {
    enum Tone { case neutral, danger }

    let systemImage: String
    let help: String
    var tone: Tone = .neutral
    var isLoading = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .scaleEffect(0.55)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(foreground)
                }
            }
            .frame(width: 24, height: 22)
            .background(HunRoundedShape().fill(background))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }

    private var foreground: Color {
        guard hovering else { return AppTheme.textSecondary }
        return tone == .danger ? AppTheme.danger : AppTheme.textPrimary
    }

    private var background: Color {
        guard hovering else { return AppTheme.searchField }
        return tone == .danger ? AppTheme.danger.opacity(0.14) : AppTheme.hover
    }
}

private struct MenuSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            TextField("Find a project", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(HunRoundedShape().fill(AppTheme.selectedFill))
    }
}

private struct MenuEmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("No projects yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text("Add one from the dashboard to run it from here.")
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Footer

private struct MenuDivider: View {
    var body: some View {
        Rectangle().fill(AppTheme.divider).frame(height: 1)
    }
}

private struct MenuFooter: View {
    @State private var hoveringOpen = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                hunApp.openDashboard()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Open Hun")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer(minLength: 8)
                    Text("⌘D")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(HunRoundedShape().fill(hoveringOpen ? AppTheme.rowHover : Color.clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringOpen = $0 }

            MenuIconButton(systemImage: "power", help: "Quit Hun (⌘Q)") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }
}

#Preview {
    MenuBarView()
        .environment(HunStore(startAutomatically: false))
}
