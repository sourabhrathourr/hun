import AppKit
import SwiftUI

struct HunSettingsSheet: View {
    @Environment(HunStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let appVersion = HunAppVersion.current

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(AppTheme.divider).frame(height: 1)

            ScrollView {
                VStack(spacing: 18) {
                    daemonSection
                    applicationSection
                    filesSection
                }
                .padding(20)
            }
        }
        .frame(width: 540, height: 580)
        .background(AppTheme.appBackground)
        .preferredColorScheme(.dark)
        .task {
            await store.refreshDaemonInfo()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Runtime health, versions, and recovery tools")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
    }

    private var daemonSection: some View {
        SettingsSection(title: "Daemon", eyebrow: "RUNTIME") {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    DaemonPulse(isHealthy: store.daemonInfo?.status == "pong")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(daemonStatusTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(daemonStatusDetail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        Task { await store.refreshDaemonInfo() }
                    } label: {
                        if store.isLoadingDaemonInfo {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)
                    .controlSize(.small)
                    .disabled(store.isLoadingDaemonInfo || store.isRestartingDaemon)
                    .accessibilityLabel("Refresh daemon health")
                }
                .padding(14)

                SettingsDivider()

                if let info = store.daemonInfo {
                    SettingsValueGrid(rows: [
                        ("Daemon version", normalizedVersion(info.version)),
                        ("Protocol", "\(info.protocolVersion)"),
                        ("Process", "PID \(info.pid)"),
                        ("Uptime", uptimeText(info.startedAt))
                    ])
                    .padding(14)
                } else if let error = store.daemonSettingsError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }

                SettingsDivider()

                HStack {
                    Text("Restarts the background daemon and reconnects this app.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                    Spacer()
                    Button {
                        Task { await store.restartDaemon() }
                    } label: {
                        if store.isRestartingDaemon {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Restarting…")
                            }
                        } else {
                            Label("Restart Daemon", systemImage: "arrow.clockwise.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .controlSize(.small)
                    .disabled(store.isRestartingDaemon)
                    .accessibilityLabel("Restart Hun daemon")
                }
                .padding(14)
            }
        }
    }

    private var applicationSection: some View {
        SettingsSection(title: "Application", eyebrow: "BUILD") {
            VStack(spacing: 0) {
                SettingsValueGrid(rows: [
                    ("Environment", HunPaths.environmentName),
                    ("App version", appVersion.version),
                    ("Build", appVersion.build),
                    ("Running daemon", store.daemonInfo.map { normalizedVersion($0.version) } ?? "Unavailable"),
                    ("Daemon commit", store.daemonInfo.map { shortCommit($0.commit) } ?? "—")
                ])
                .padding(14)

                SettingsDivider()

                HStack {
                    SettingsPathLabel(title: "Daemon socket", path: HunPaths.socketPath)
                    Spacer()
                    Button("Copy diagnostics") { copyDiagnostics() }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.accent)
                        .controlSize(.small)
                        .accessibilityLabel("Copy Hun diagnostics")
                }
                .padding(14)
            }
        }
    }

    private var filesSection: some View {
        SettingsSection(title: "Hun Files", eyebrow: "WORKSPACE") {
            HStack(spacing: 8) {
                SettingsFileButton(title: "Hun Folder", icon: "folder", action: openHunFolder)
                SettingsFileButton(title: "Config", icon: "slider.horizontal.3", action: revealConfig)
                SettingsFileButton(title: "State", icon: "doc.text", action: revealState)
                SettingsFileButton(title: "Logs", icon: "text.alignleft", action: openLogs)
            }
            .padding(14)
        }
    }

    private var daemonStatusTitle: String {
        store.daemonInfo?.status == "pong" ? "Daemon healthy" : "Daemon unavailable"
    }

    private var daemonStatusDetail: String {
        guard let info = store.daemonInfo else {
            return store.isLoadingDaemonInfo ? "Checking socket…" : "No healthy response from the daemon socket"
        }
        return "Protocol \(info.protocolVersion) · PID \(info.pid) · \(collapseHome(HunPaths.socketPath))"
    }

    private func normalizedVersion(_ value: String) -> String {
        value == "dev" ? "Development build" : value
    }

    private func shortCommit(_ value: String) -> String {
        value == "none" ? "—" : String(value.prefix(10))
    }

    private func uptimeText(_ raw: String) -> String {
        guard let startedAt = HunDateParser.date(from: raw) else { return "Unknown" }
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
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
    }

    private func openHunFolder() {
        ensureDirectory(HunPaths.homeURL)
        NSWorkspace.shared.open(HunPaths.homeURL)
    }

    private func openLogs() {
        ensureDirectory(HunPaths.logsURL)
        NSWorkspace.shared.open(HunPaths.logsURL)
    }

    private func revealConfig() {
        reveal(HunPaths.configURL)
    }

    private func revealState() {
        reveal(HunPaths.stateURL)
    }

    private func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(HunPaths.homeURL)
        }
    }

    private func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func collapseHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let eyebrow: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(eyebrow)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            content
                .background(AppTheme.elevated.opacity(0.54))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AppTheme.dividerStrong, lineWidth: 1)
                }
        }
    }
}

private struct DaemonPulse: View {
    let isHealthy: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill((isHealthy ? AppTheme.success : AppTheme.danger).opacity(0.12))
                .frame(width: 34, height: 34)
            Circle()
                .fill(isHealthy ? AppTheme.success : AppTheme.danger)
                .frame(width: 8, height: 8)
        }
        .accessibilityLabel(isHealthy ? "Daemon healthy" : "Daemon unavailable")
    }
}

private struct SettingsValueGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 9) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(row.1)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsPathLabel: View {
    let title: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textTertiary)
            Text(path)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct SettingsFileButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11.5, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.textPrimary)
        .background(AppTheme.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(AppTheme.divider).frame(height: 1)
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
