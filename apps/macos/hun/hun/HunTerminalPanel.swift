import AppKit
import SwiftUI

struct HunTerminalCommandAction {
    let canToggle: Bool
    let canClear: Bool
    let toggle: () -> Void
    let clear: () -> Void
}

private struct HunTerminalCommandKey: FocusedValueKey {
    typealias Value = HunTerminalCommandAction
}

extension FocusedValues {
    var hunTerminalCommand: HunTerminalCommandAction? {
        get { self[HunTerminalCommandKey.self] }
        set { self[HunTerminalCommandKey.self] = newValue }
    }
}

struct HunTerminalCommands: Commands {
    @FocusedValue(\.hunTerminalCommand) private var terminalCommand

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Toggle Terminal") {
                terminalCommand?.toggle()
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(terminalCommand?.canToggle != true)

            Button("Clear Terminal") {
                terminalCommand?.clear()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(terminalCommand?.canClear != true)
        }
    }
}

struct HunTerminalPanel: View {
    let session: HunTerminalSession
    @Binding var preferredHeight: CGFloat
    let availableHeight: CGFloat
    let onClose: () -> Void

    @State private var dragOrigin: CGFloat?
    @State private var resizeHovering = false

    var body: some View {
        @Bindable var session = session

        VStack(spacing: 0) {
            resizeHandle
            header(session: session)
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 1)
            HunTerminalHostView(session: session)
                .background(AppTheme.appBackground)
                .accessibilityLabel("Terminal for \(session.projectName)")
        }
        .background(AppTheme.appBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.dividerStrong)
                .frame(height: 1)
        }
        .onAppear {
            session.startIfNeeded()
            focusTerminal(after: .milliseconds(90))
        }
        .onDisappear {
            if resizeHovering {
                NSCursor.pop()
                resizeHovering = false
            }
        }
    }

    private var resizeHandle: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(resizeHovering ? AppTheme.textTertiary : AppTheme.dividerStrong)
                .frame(width: 34, height: 2)
        }
        .frame(height: 7)
        .contentShape(Rectangle())
        .onHover { hovering in
            guard hovering != resizeHovering else { return }
            resizeHovering = hovering
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragOrigin == nil {
                        dragOrigin = preferredHeight
                    }
                    guard let dragOrigin else { return }
                    preferredHeight = HunTerminalPanelMetrics.clamp(
                        dragOrigin - value.translation.height,
                        availableHeight: availableHeight
                    )
                }
                .onEnded { _ in
                    dragOrigin = nil
                }
        )
        .accessibilityLabel("Resize terminal")
    }

    private func header(session: HunTerminalSession) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(for: session.state))
                .frame(width: 5, height: 5)
                .help(session.state.statusText)
                .accessibilityLabel(session.state.statusText)

            Image(systemName: "terminal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

            Text("Terminal")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)

            Text(session.projectName)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)

            Text(collapsedPath(session.currentDirectory))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(session.currentDirectory)

            Spacer(minLength: 12)

            if session.state == .starting {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                    .frame(width: 18, height: 18)
                    .accessibilityLabel("Starting shell")
            } else if !session.state.isRunning {
                HunTerminalHeaderButton(
                    systemImage: "arrow.clockwise",
                    helpText: "Start a new shell",
                    action: session.restartAfterExit
                )
            }

            Text(session.shellName)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AppTheme.searchField)
                )

            HunTerminalHeaderButton(
                systemImage: "xmark",
                helpText: "Hide terminal (⌘J)",
                action: onClose
            )
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .frame(height: 31)
    }

    private func statusColor(for state: HunTerminalSessionState) -> Color {
        switch state {
        case .running:
            return AppTheme.success
        case .failed:
            return AppTheme.danger
        case .starting:
            return AppTheme.accent
        case .idle, .exited:
            return AppTheme.textTertiary
        }
    }

    private func collapsedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private func focusTerminal(after delay: Duration) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            session.focus()
        }
    }
}

private struct HunTerminalHeaderButton: View {
    let systemImage: String
    let helpText: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textTertiary)
                .frame(width: 23, height: 23)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? AppTheme.hover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
    }
}

private struct HunTerminalHostView: NSViewRepresentable {
    let session: HunTerminalSession

    func makeNSView(context: Context) -> HunTerminalContainerView {
        let container = HunTerminalContainerView()
        container.embed(session.view)
        return container
    }

    func updateNSView(_ container: HunTerminalContainerView, context: Context) {
        container.embed(session.view)
    }

    static func dismantleNSView(_ container: HunTerminalContainerView, coordinator: Void) {
        container.detachTerminal()
    }
}

private final class HunTerminalContainerView: NSView {
    private weak var terminalView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(AppTheme.appBackground).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    func embed(_ view: NSView) {
        guard terminalView !== view else { return }
        detachTerminal()

        terminalView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func detachTerminal() {
        if terminalView?.superview === self {
            terminalView?.removeFromSuperview()
        }
        terminalView = nil
    }
}
