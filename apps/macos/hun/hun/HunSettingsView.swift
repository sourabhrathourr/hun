import AppKit
import SwiftUI

/// Settings live in the main window: the sidebar lists these sections and the
/// card shows the selected one.
enum HunSettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case daemon
    case license
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .daemon: return "Daemon"
        case .license: return "License"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: return "How Hun looks: its theme and layout."
        case .daemon: return "The background process that runs your services."
        case .license: return "Your plan and this Mac's activation."
        case .about: return "Versions, diagnostics and the files Hun keeps."
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "circle.lefthalf.filled"
        case .daemon: return "server.rack"
        case .license: return "key"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Theme

/// Hun's light or dark appearance, or macOS's. It's set on the whole app, so
/// the window, the menu bar panel and the terminal all follow it.
enum HunTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let key = "hun.appearance.theme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    static var saved: HunTheme {
        UserDefaults.standard.string(forKey: key).flatMap(HunTheme.init) ?? .system
    }

    func apply() {
        switch self {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// Whether services the current profile doesn't run are listed (dimmed,
/// below the rest). Off by default, so a profile shows just its services.
enum HunServicesDisplay {
    static let showOutsideProfileKey = "hun.services.showOutsideProfile"
    static let showOutsideProfileDefault = false
}

// MARK: - Sidebar

/// The sidebar while Settings is open: a way back, then the sections, on the
/// same grid as the project list.
struct HunSettingsNavigation: View {
    @Binding var selection: HunSettingsSection
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsNavigationRow(title: "Projects", icon: "chevron.left", selected: false, action: onBack)
                .help("Back to projects (Esc)")
                .padding(.top, SidebarMetrics.inset)

            Text("Settings")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.leading, SidebarMetrics.rowPadding)
                .frame(height: SidebarMetrics.sectionHeaderHeight)
                .padding(.top, SidebarMetrics.sectionSpacing)

            VStack(spacing: 2) {
                ForEach(HunSettingsSection.allCases) { section in
                    SettingsNavigationRow(
                        title: section.title,
                        icon: section.icon,
                        selected: selection == section
                    ) {
                        selection = section
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SidebarMetrics.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(selected || hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(selected || hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SidebarMetrics.rowPadding)
            .frame(height: SidebarMetrics.rowHeight)
            .background(
                HunRoundedShape()
                    .fill(selected ? AppTheme.selectedFill : (hovering ? AppTheme.rowHover : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Page

struct HunSettingsPage: View {
    let section: HunSettingsSection
    let onClose: () -> Void

    private static let columnWidth: CGFloat = 680
    @AppStorage(HunLayout.roundedPanelsKey) private var roundedPanels = HunLayout.roundedPanelsDefault

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(section.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Group {
                    switch section {
                    case .appearance: HunAppearanceSettings()
                    case .daemon: HunDaemonSettings()
                    case .license: HunLicenseSettings(onDeactivated: onClose)
                    case .about: HunAboutSettings()
                    }
                }
            }
            // Left-aligned, with generous room from the card's edges.
            .frame(maxWidth: Self.columnWidth, alignment: .leading)
            .padding(.leading, 48)
            .padding(.trailing, 40)
            .padding(.top, 48)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .hunScrollStyle()
        .overlay(alignment: .topTrailing) {
            ToolbarIconButton(systemImage: "xmark", helpText: "Close settings (Esc)", action: onClose)
                .accessibilityLabel("Close settings")
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.appBackground)
        // The whole page is one card, inset evenly from the window.
        .hunRoundedShell(roundedPanels, leadingInset: HunLayout.shellInset)
        .background {
            // Esc goes back to the projects.
            Button("", action: onClose)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Sections

private struct HunAppearanceSettings: View {
    @AppStorage(HunLayout.roundedPanelsKey) private var roundedPanels = HunLayout.roundedPanelsDefault
    @AppStorage(HunTheme.key) private var theme = HunTheme.system.rawValue
    @AppStorage(HunServicesDisplay.showOutsideProfileKey)
    private var showsOutsideProfile = HunServicesDisplay.showOutsideProfileDefault

    var body: some View {
        SettingsGroup {
            SettingsRow(title: "Theme", detail: "Follow macOS, or keep Hun light or dark.", isFirst: true) {
                SettingsSegmented(
                    options: HunTheme.allCases.map { ($0.rawValue, $0.title, $0.icon) },
                    selection: Binding(
                        get: { theme },
                        set: { newValue in
                            theme = newValue
                            (HunTheme(rawValue: newValue) ?? .system).apply()
                        }
                    )
                )
            }
            SettingsRow(
                title: "Services outside the profile",
                detail: "List the services the current profile doesn't run, dimmed below the rest. When off, the services count shows how many are hidden."
            ) {
                Toggle("Services outside the profile", isOn: $showsOutsideProfile)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(AppTheme.textSecondary)
            }
            SettingsRow(
                title: "Refined layout",
                detail: "Services, logs and the terminal sit in rounded cards with even margins. Turn off for the classic edge-to-edge layout."
            ) {
                Toggle("Refined layout", isOn: $roundedPanels)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    // Neutral rather than the system accent.
                    .tint(AppTheme.textSecondary)
            }
        }
    }
}

private struct HunDaemonSettings: View {
    @Environment(HunStore.self) private var store
    @State private var confirmingRestart = false

    private var isHealthy: Bool { store.daemonInfo?.status == "pong" }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup {
                SettingsRow(title: "Status", isFirst: true) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(isHealthy ? AppTheme.success : AppTheme.danger)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(statusTitle)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textPrimary)
                        if let uptime = uptime {
                            Text(verbatim: "· up \(uptime)")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }

                if let info = store.daemonInfo {
                    SettingsRow(title: "Version") { SettingsValue(normalizedVersion(info.version)) }
                    SettingsRow(title: "Protocol") { SettingsValue("\(info.protocolVersion)", monospaced: true) }
                    SettingsRow(title: "Process") { SettingsValue("PID \(info.pid)", monospaced: true, copy: "\(info.pid)") }
                }
                SettingsRow(title: "Socket") {
                    SettingsValue(collapseHome(HunPaths.socketPath), monospaced: true, copy: HunPaths.socketPath)
                }
                SettingsRow(title: "Restart daemon", detail: "Running services restart with it. Try this if Hun stops responding.") {
                    ActionButton(
                        title: store.isRestartingDaemon ? "Restarting…" : "Restart",
                        systemImage: "arrow.clockwise",
                        style: .secondary,
                        isLoading: store.isRestartingDaemon,
                        isDisabled: store.isRestartingDaemon,
                        action: { confirmingRestart = true }
                    )
                }
            }

            if let error = store.daemonSettingsError, store.daemonInfo == nil {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.warning)
                    .padding(.leading, 16)
            }
        }
        .confirmationDialog("Restart the daemon?", isPresented: $confirmingRestart) {
            Button("Restart Daemon") { Task { await store.restartDaemon() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Running services restart with it, and Hun reconnects in a moment.")
        }
        // Keep the status live while this page is open.
        .task {
            while !Task.isCancelled {
                await store.refreshDaemonInfo()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var statusTitle: String {
        if store.isRestartingDaemon { return "Restarting" }
        if isHealthy { return "Healthy" }
        return store.isLoadingDaemonInfo ? "Checking…" : "Not responding"
    }

    private var uptime: String? {
        guard isHealthy, let info = store.daemonInfo else { return nil }
        return uptimeText(info.startedAt)
    }
}

private struct HunLicenseSettings: View {
    @Environment(HunLicenseManager.self) private var license
    let onDeactivated: () -> Void
    @State private var confirmingDeactivation = false
    @State private var isDeactivating = false

    var body: some View {
        SettingsGroup {
            SettingsRow(title: "Plan", isFirst: true) {
                SettingsValue(license.activeSession?.productName ?? "Hun")
            }
            SettingsRow(title: "Status") {
                SettingsValue(license.activeSession?.isOffline == true ? "Offline grace period" : "Active")
            }
            if let session = license.activeSession {
                SettingsRow(title: "Last verified") {
                    SettingsValue(session.lastValidatedAt.formatted(.relative(presentation: .named)))
                }
            }
            SettingsRow(title: "This Mac", detail: "Deactivating frees one of your two activations.") {
                ActionButton(
                    title: "Deactivate…",
                    systemImage: "minus.circle",
                    style: .danger,
                    isLoading: isDeactivating,
                    isDisabled: isDeactivating,
                    action: { confirmingDeactivation = true }
                )
            }
        }
        .confirmationDialog("Deactivate this Mac?", isPresented: $confirmingDeactivation) {
            Button("Deactivate", role: .destructive) {
                isDeactivating = true
                Task {
                    let done = await license.deactivate()
                    isDeactivating = false
                    if done { onDeactivated() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Hun will ask for your license key again before it can be used on this Mac.")
        }
    }
}

private struct HunAboutSettings: View {
    @Environment(HunStore.self) private var store
    @State private var copiedDiagnostics = false
    private let appVersion = HunAppVersion.current

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup {
                SettingsRow(title: "Version", isFirst: true) { SettingsValue(appVersion.version) }
                SettingsRow(title: "Build") { SettingsValue(appVersion.build, monospaced: true) }
                SettingsRow(title: "Environment") { SettingsValue(HunPaths.environmentName) }
                SettingsRow(title: "Daemon commit") {
                    SettingsValue(store.daemonInfo.map { shortCommit($0.commit) } ?? "—", monospaced: true)
                }
                SettingsRow(title: "Diagnostics", detail: "Versions, process and socket, for a bug report.") {
                    ActionButton(
                        title: copiedDiagnostics ? "Copied" : "Copy",
                        systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc",
                        style: .secondary,
                        action: copyDiagnostics
                    )
                }
            }

            SettingsGroup(title: "Files") {
                SettingsRow(title: "Hun folder", detail: collapseHome(HunPaths.homeURL.path), isFirst: true) {
                    ActionButton(title: "Open", systemImage: "folder", style: .secondary) {
                        open(HunPaths.homeURL)
                    }
                }
                SettingsRow(title: "Global config", detail: collapseHome(HunPaths.configURL.path)) {
                    ActionButton(title: "Reveal", systemImage: "magnifyingglass", style: .secondary) {
                        reveal(HunPaths.configURL)
                    }
                }
                SettingsRow(title: "State", detail: collapseHome(HunPaths.stateURL.path)) {
                    ActionButton(title: "Reveal", systemImage: "magnifyingglass", style: .secondary) {
                        reveal(HunPaths.stateURL)
                    }
                }
                SettingsRow(title: "Logs", detail: collapseHome(HunPaths.logsURL.path)) {
                    ActionButton(title: "Open", systemImage: "folder", style: .secondary) {
                        open(HunPaths.logsURL)
                    }
                }
            }
        }
        .task { await store.refreshDaemonInfo() }
    }

    private func copyDiagnostics() {
        let info = store.daemonInfo
        let lines = [
            "Hun app: \(appVersion.version) (\(appVersion.build))",
            "Environment: \(HunPaths.environmentName)",
            "Daemon: \(info.map { normalizedVersion($0.version) } ?? "unavailable")",
            "Protocol: \(info.map { String($0.protocolVersion) } ?? "unavailable")",
            "Commit: \(info.map { shortCommit($0.commit) } ?? "unavailable")",
            "PID: \(info.map { String($0.pid) } ?? "unavailable")",
            "Socket: \(HunPaths.socketPath)"
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        withAnimation(.easeOut(duration: 0.16)) { copiedDiagnostics = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeIn(duration: 0.18)) { copiedDiagnostics = false }
        }
    }

    private func open(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            open(HunPaths.homeURL)
        }
    }
}

// MARK: - Building blocks

/// A rounded group of rows, styled like the services and logs card.
private struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            VStack(spacing: 0) {
                content
            }
            .background(HunRoundedShape().fill(AppTheme.hover))
            .overlay(HunRoundedShape().strokeBorder(AppTheme.divider, lineWidth: 1))
        }
    }
}

/// A label (with an optional line of detail) on the left and a value or
/// control on the right; rows after the first get a divider above.
private struct SettingsRow<Leading: View, Trailing: View>: View {
    let title: String
    var detail: String?
    var isFirst = false
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    init(
        title: String,
        detail: String? = nil,
        isFirst: Bool = false,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.isFirst = isFirst
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isFirst {
                Rectangle().fill(AppTheme.divider).frame(height: 1).padding(.leading, 16)
            }
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 16)
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 52)
        }
    }
}

/// A small segmented control, styled like the logs' Service | All switch.
private struct SettingsSegmented: View {
    let options: [(id: String, title: String, icon: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.id) { option in
                let active = selection == option.id
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { selection = option.id }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.icon)
                            .font(.system(size: 10.5, weight: .medium))
                        Text(option.title)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(active ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                        .frame(maxHeight: .infinity)
                        .background(HunRoundedShape().fill(active ? AppTheme.tabActive : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(height: 28)
        .background(HunRoundedShape().fill(AppTheme.searchField))
    }
}

/// A read-only value; `copy` adds a copy button that shows a check after use.
private struct SettingsValue: View {
    let text: String
    var monospaced = false
    var copy: String?
    @State private var copied = false

    init(_ text: String, monospaced: Bool = false, copy: String? = nil) {
        self.text = text
        self.monospaced = monospaced
        self.copy = copy
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: text)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if let copy {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copy, forType: .string)
                    withAnimation(.easeOut(duration: 0.16)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation(.easeIn(duration: 0.18)) { copied = false }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(copied ? AppTheme.success : AppTheme.textTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(copied ? "Copied" : "Copy")
            }
        }
    }
}

private struct HunAppVersion {
    let version: String
    let build: String

    static var current: HunAppVersion {
        let info = Bundle.main.infoDictionary
        return HunAppVersion(
            version: info?["CFBundleShortVersionString"] as? String ?? "Development",
            build: info?["CFBundleVersion"] as? String ?? "Development"
        )
    }
}

private func normalizedVersion(_ value: String) -> String {
    value == "dev" ? "Development build" : value
}

private func shortCommit(_ value: String) -> String {
    value == "none" ? "—" : String(value.prefix(10))
}

private func uptimeText(_ raw: String) -> String {
    guard let startedAt = HunDateParser.date(from: raw) else { return "—" }
    let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
}

private func collapseHome(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
