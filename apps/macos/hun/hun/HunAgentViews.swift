import SwiftUI

// The setup conversation with the coding agent: the first setup of a new
// project, then a chat in the logs pane for asking for changes.

/// What the right-hand pane shows.
enum HunPaneTab: Hashable {
    case logs
    case setup
}

// MARK: - First setup

/// Fills the services-and-logs card while the agent writes a new project's
/// .hun.yml: what it's doing, live, and a way to use Hun's own setup instead.
struct HunAgentSetupView: View {
    let projectName: String
    let agent: HunAgentKind
    let message: HunAgentMessage
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HunAgentMark(kind: agent, isWorking: true, size: 34)

            Text("\(agent.shortName) is setting up \(projectName)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.top, 18)

            Text("It's reading the project to work out what runs in development, and how. This takes about 20 seconds.")
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            HunAgentLiveSteps(steps: message.steps, isThinking: message.isThinking == true, limit: 5)
                .padding(.top, 22)
            HunFileChips(files: message.files ?? [])
                .padding(.top, 14)
                .frame(minHeight: 70, alignment: .top)

            Button(action: onCancel) {
                Text("Use Hun's own setup instead")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityHint("Stop \(agent.displayName) and keep the setup Hun worked out on its own")
        }
        .frame(maxWidth: 400, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.appBackground)
    }
}

/// The agent's latest steps, the current one with a spinner.
struct HunAgentLiveSteps: View {
    let steps: [String]
    var isThinking = false
    var limit = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The steps so far, with "Thinking" as the current one between steps.
    private var visible: [String] {
        let all = isThinking && steps.last != "Writing .hun.yml" ? steps + ["Thinking"] : steps
        return Array(all.suffix(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if visible.isEmpty {
                HunAgentStepRow(text: "Reading the project", isCurrent: true)
            } else {
                ForEach(Array(visible.enumerated()), id: \.element) { index, step in
                    HunAgentStepRow(text: step, isCurrent: index == visible.count - 1)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: visible)
    }
}

/// The project files the agent read, as small chips that arrive one by one.
struct HunFileChips: View {
    let files: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HunFlowLayout(spacing: 5) {
            ForEach(files, id: \.self) { file in
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(file)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(HunRoundedShape().fill(AppTheme.searchField))
                .overlay(HunRoundedShape().strokeBorder(AppTheme.divider, lineWidth: 0.5))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: files)
    }
}

/// Lays chips out in rows, wrapping to the width it's given.
struct HunFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: subviews.isEmpty ? 0 : y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct HunAgentStepRow: View {
    let text: String
    let isCurrent: Bool
    var dimmed = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if isCurrent {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(dimmed ? AppTheme.textTertiary : AppTheme.success)
                }
            }
            .frame(width: 14, height: 14)

            Text(text)
                .font(.system(size: 12.5, weight: isCurrent ? .medium : .regular))
                .foregroundStyle(isCurrent ? AppTheme.textPrimary : AppTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Who's talking: the agent's own mark on a quiet disc. A soft ring breathes
/// around it while it works.
struct HunAgentMark: View {
    /// Nil shows the two agents Hun works with, side by side.
    let kind: HunAgentKind?
    let isWorking: Bool
    var size: CGFloat = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Group {
            if let kind {
                disc(kind)
            } else {
                HStack(spacing: -size * 0.3) {
                    disc(.claude)
                    disc(.codex)
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear { startBreathing() }
        .onChange(of: isWorking) { _, _ in startBreathing() }
    }

    private func disc(_ kind: HunAgentKind) -> some View {
        ZStack {
            HunRoundedShape()
                .fill(AppTheme.elevated)
            HunRoundedShape()
                .strokeBorder(AppTheme.divider, lineWidth: 1)
            HunRoundedShape()
                .stroke(AppTheme.textTertiary.opacity(0.35), lineWidth: 1)
                .scaleEffect(breathing ? 1.35 : 1)
                .opacity(breathing ? 0 : 1)
                .opacity(isWorking ? 1 : 0)
            Image(kind.markAsset)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size * 0.56, height: size * 0.56)
        }
        .frame(width: size, height: size)
    }

    private func startBreathing() {
        guard isWorking, !reduceMotion else {
            breathing = false
            return
        }
        breathing = false
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            breathing = true
        }
    }
}

extension HunAgentKind {
    /// The agent's mark in the asset catalog.
    var markAsset: String {
        switch self {
        case .claude: return "AgentClaude"
        case .codex: return "AgentCodex"
        }
    }
}

// MARK: - Pane tabs

/// Opens the setup chat from the project header: the agent's mark, filled
/// while the chat is open, with a pulsing dot while the agent works.
struct HunSetupButton: View {
    let agent: HunAgentKind
    let isWorking: Bool
    let isOpen: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            Image(agent.markAsset)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 14, height: 14)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(HunRoundedShape().fill(isOpen ? AppTheme.selectedFill : AppTheme.buttonFill))
                .overlay(HunRoundedShape().stroke(isOpen ? AppTheme.dividerStrong : AppTheme.divider, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if isWorking {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 6, height: 6)
                            .opacity(pulse ? 0.35 : 1)
                            .offset(x: 2, y: -2)
                            .onAppear {
                                guard !reduceMotion else { return }
                                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
                            }
                            .onDisappear { pulse = false }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isOpen ? "Back to logs" : "Ask \(agent.shortName) to change this setup")
        .accessibilityLabel(isOpen ? "Close setup chat" : "Ask \(agent.shortName) to change this setup")
    }
}

struct HunAgentChatView: View {
    let projectName: String
    /// The agent to talk to; nil when none is installed.
    let agent: HunAgentKind?
    let chat: HunAgentChat?
    /// Messages waiting for the agent to finish its turn.
    let queued: [HunQueuedMessage]
    @Binding var tab: HunPaneTab
    /// Sends, or queues while the agent works.
    let onSend: (String) -> Void
    /// Stops the turn in progress and sends this instead.
    let onSteer: (String) -> Void
    let onRemoveQueued: (UUID) -> Void
    let onSendQueuedNow: (UUID) -> Void
    let onStop: () -> Void
    let onUndo: (UUID) -> Void
    let onNewConversation: () -> Void
    let onCheckForAgent: () -> Void
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var messages: [HunAgentMessage] { chat?.messages ?? [] }
    private var isWorking: Bool { chat?.isWorking == true }

    private static let suggestions = [
        "Explain how this project runs",
        "Add a profile for just the frontend",
        "Run the database in Docker",
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Setup")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if !messages.isEmpty {
                    HunNewConversationButton(isEnabled: !isWorking, action: onNewConversation)
                }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { tab = .logs }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Back to logs")
                .accessibilityLabel("Close setup chat")
            }
            .padding(.horizontal, 14)
            .frame(height: LogsToolbarMetrics.controlHeight + 20)

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            if let agent {
                if messages.isEmpty {
                    emptyState(agent)
                } else {
                    conversation(agent)
                }
                composer(agent)
            } else {
                HunNoAgentView(projectName: projectName, onCheckAgain: onCheckForAgent)
            }
        }
        .background(AppTheme.appBackground)
    }

    private func conversation(_ agent: HunAgentKind) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(messages) { message in
                        Group {
                            if message.role == .user {
                                HunUserBubble(text: message.text)
                            } else {
                                HunAgentTurn(
                                    message: message,
                                    agent: agent,
                                    projectName: projectName,
                                    canUndo: !isWorking,
                                    onUndo: { onUndo(message.id) },
                                    onStop: onStop
                                )
                            }
                        }
                        .id(message.id)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                    }
                    ForEach(queued) { item in
                        HunQueuedBubble(
                            text: item.text,
                            onSendNow: { onSendQueuedNow(item.id) },
                            onRemove: { onRemoveQueued(item.id) }
                        )
                        .transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .animation(.easeOut(duration: 0.22), value: messages)
            }
            .hunScrollStyle()
            // Stays at the newest message as replies stream in, unless the
            // person has scrolled up to read.
            // A short conversation sits at the top; a long one opens at the
            // latest message and follows new replies down.
            .defaultScrollAnchor(.top, for: .alignment)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: messages) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: queued) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    private func emptyState(_ agent: HunAgentKind) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HunAgentMark(kind: agent, isWorking: false, size: 30)
            Text("Ask \(agent.shortName) about \(projectName)'s setup")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.top, 14)
            Text("It reads the project and updates .hun.yml for you. Hun checks each change before using it, and you can undo any of them.")
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    HunSuggestionButton(text: suggestion) { onSend(suggestion) }
                }
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: 400, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func composer(_ agent: HunAgentKind) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                isWorking ? "Queue a message, or ⌘↩ to send it now" : "Ask \(agent.shortName) to change this setup",
                text: $draft,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(1...6)
            .focused($composerFocused)
            .onSubmit(send)
            .onKeyPress(keys: [.return], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                steer()
                return .handled
            }
            .padding(.vertical, 3)

            // Working with nothing typed: stop. Otherwise send (or queue).
            let stopping = isWorking && !hasDraft
            Button(action: stopping ? onStop : send) {
                Image(systemName: stopping ? "stop.fill" : "arrow.up")
                    .font(.system(size: stopping ? 8.5 : 10.5, weight: .bold))
                    .foregroundStyle(hasDraft || stopping ? AppTheme.primaryText : AppTheme.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(HunRoundedShape().fill(hasDraft || stopping ? AppTheme.primaryFill : AppTheme.hover))
            }
            .buttonStyle(.plain)
            .disabled(!hasDraft && !stopping)
            .accessibilityHint(stopping ? "Stop" : isWorking ? "Queue (Return) · Send now (⌘Return)" : "Send (Return)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(HunRoundedShape().fill(AppTheme.searchField))
        .overlay(
            HunRoundedShape()
                .strokeBorder(composerFocused ? AppTheme.dividerStrong : AppTheme.divider, lineWidth: 1)
        )
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .contentShape(Rectangle())
        .onTapGesture { composerFocused = true }
        .onAppear { composerFocused = true }
    }

    private var hasDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Sends, or queues while the agent is working.
    private func send() {
        guard hasDraft else { return }
        onSend(draft)
        draft = ""
    }

    /// Sends now, stopping the turn in progress.
    private func steer() {
        guard hasDraft else { return }
        onSteer(draft)
        draft = ""
    }
}

private struct HunSuggestionButton: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(HunRoundedShape().fill(hovering ? AppTheme.hover : AppTheme.searchField))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A message waiting for the agent to finish, with a way to send it now.
private struct HunQueuedBubble: View {
    let text: String
    let onSendNow: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack {
                Spacer(minLength: 60)
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        HunRoundedShape()
                            .strokeBorder(AppTheme.dividerStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    )
            }
            HStack(spacing: 10) {
                Text("Queued")
                    .foregroundStyle(AppTheme.textTertiary)
                Button("Send now", action: onSendNow)
                    .buttonStyle(.plain)
                    .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .onHover { hovering = $0 }
                    .accessibilityHint("Stop the current reply and send this (⌘Return)")
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textTertiary)
                .accessibilityHint("Remove from the queue")
            }
            .font(.system(size: 11))
        }
    }
}

private struct HunUserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(HunRoundedShape().fill(AppTheme.selectedFill))
        }
    }
}

private struct HunAgentTurn: View {
    let message: HunAgentMessage
    let agent: HunAgentKind
    let projectName: String
    let canUndo: Bool
    let onUndo: () -> Void
    let onStop: () -> Void
    @State private var showsFiles = false

    private var files: [String] { message.files ?? [] }
    private var isWorking: Bool { message.status == .working }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HunAgentMark(kind: agent, isWorking: isWorking, size: 24)
            VStack(alignment: .leading, spacing: 8) {
                if message.isSetup && !isWorking {
                    Text("Set up \(projectName)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                if isWorking {
                    // Until the reply starts, what it's doing now and what it has read.
                    if message.text.isEmpty {
                        HunAgentActivity(
                            text: message.isThinking == true ? "Thinking" : (message.steps.last ?? "Reading the project")
                        )
                        if !files.isEmpty {
                            HunFileChips(files: files)
                        }
                    } else {
                        HunMarkdownText(text: message.text, showsCursor: true)
                    }
                } else {
                    if !files.isEmpty {
                        filesDisclosure
                    }
                    if !message.text.isEmpty {
                        HunMarkdownText(
                            text: message.text,
                            color: message.status == .failed ? AppTheme.textSecondary : AppTheme.textPrimary
                        )
                    }
                    if let change = message.change, !change.lines.isEmpty {
                        HunChangeCard(change: change, canUndo: canUndo, onUndo: onUndo)
                            .padding(.top, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filesDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { showsFiles.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(files.count == 1 ? "Read 1 file" : "Read \(files.count) files")
                        .font(.system(size: 11.5))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(showsFiles ? 90 : 0))
                }
                .foregroundStyle(AppTheme.textTertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsFiles {
                HunFileChips(files: files)
                    .transition(.opacity)
            }
        }
    }

    /// `code` and **bold** as the agent wrote them, without block markdown.
    static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// What the agent is doing right now: a spinner and a short line.
private struct HunAgentActivity: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .scaleEffect(0.7)
                .frame(width: 12, height: 12)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.18), value: text)
        }
        .padding(.top, 3)
    }
}

private struct HunNewConversationButton: View {
    let isEnabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textTertiary)
                .frame(width: 26, height: 26)
                .background(HunRoundedShape().fill(hovering ? AppTheme.hover : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .accessibilityHint("New conversation. The setup stays as it is.")
    }
}

/// The Setup tab when no coding agent is installed.
private struct HunNoAgentView: View {
    let projectName: String
    let onCheckAgain: () -> Void
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HunAgentMark(kind: nil, isWorking: false, size: 30)
            Text("Set up projects by asking")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.top, 14)
            Text("With Claude Code or Codex on this Mac, Hun asks it to read \(projectName) and write its setup, and you can change it by asking here. Without one, Hun works the setup out from the project's files.")
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 8) {
                HunInstallCommand(name: "Claude Code", command: "curl -fsSL https://claude.ai/install.sh | bash")
                HunInstallCommand(name: "Codex", command: "npm install -g @openai/codex")
            }
            .padding(.top, 18)

            Button {
                checking = true
                onCheckAgain()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { checking = false }
            } label: {
                HStack(spacing: 6) {
                    if checking {
                        ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 11, height: 11)
                    }
                    Text(checking ? "Checking…" : "I've installed one, check again")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(HunRoundedShape().fill(AppTheme.buttonFill))
                .overlay(HunRoundedShape().stroke(AppTheme.divider, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HunInstallCommand: View {
    let name: String
    let command: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            HStack(spacing: 8) {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 6)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    withAnimation(.easeOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = false } }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(copied ? AppTheme.success : AppTheme.textTertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Copy")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(HunRoundedShape().fill(AppTheme.searchField))
        }
    }
}

/// What a reply changed, line by line, with Undo.
private struct HunChangeCard: View {
    let change: HunAgentChange
    let canUndo: Bool
    let onUndo: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(change.lines, id: \.self) { line in
                    HStack(spacing: 8) {
                        Text(symbol(line.kind))
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(color(line.kind))
                            .frame(width: 10)
                        Text(line.text)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(change.undone ? AppTheme.textTertiary : AppTheme.textPrimary)
                            .strikethrough(change.undone)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(12)

            Rectangle().fill(AppTheme.divider).frame(height: 1)

            HStack {
                Text(change.undone ? "Undone" : "Saved to .hun.yml")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textTertiary)
                Spacer()
                if !change.undone {
                    Button(action: onUndo) {
                        Text("Undo")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canUndo)
                    .onHover { hovering = $0 }
                    .accessibilityHint("Put back the setup from before this change")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(HunRoundedShape().fill(AppTheme.elevated))
        .overlay(HunRoundedShape().strokeBorder(AppTheme.divider, lineWidth: 1))
        .frame(maxWidth: 420, alignment: .leading)
    }

    private func symbol(_ kind: HunAgentChange.Line.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "−"
        case .changed: return "~"
        }
    }

    private func color(_ kind: HunAgentChange.Line.Kind) -> Color {
        switch kind {
        case .added: return AppTheme.success
        case .removed: return AppTheme.danger
        case .changed: return AppTheme.accent
        }
    }
}

// MARK: - Markdown

/// The markdown agents write in replies: paragraphs, bulleted and numbered
/// lists, headings and fenced code, with inline `code` and **bold** inside.
struct HunMarkdownText: View {
    let text: String
    var color: Color = AppTheme.textPrimary
    /// Puts a soft cursor at the end, for a reply still being written.
    var showsCursor = false
    @State private var cursorOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Block: Equatable {
        case paragraph(String)
        case bullet(String)
        case numbered(String, String)
        case heading(String)
        case code(String)
    }

    var body: some View {
        let blocks = Self.blocks(in: text)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block, isLast: index == blocks.count - 1)
            }
        }
        .onAppear {
            guard showsCursor, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { cursorOn = false }
        }
    }

    @ViewBuilder
    private func view(for block: Block, isLast: Bool) -> some View {
        switch block {
        case let .paragraph(text):
            inline(text, cursor: isLast)
        case let .heading(text):
            inline(text, cursor: isLast).fontWeight(.semibold)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•").foregroundStyle(AppTheme.textTertiary)
                inline(text, cursor: isLast)
            }
            .padding(.leading, 2)
        case let .numbered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number)
                    .foregroundStyle(AppTheme.textTertiary)
                    .monospacedDigit()
                inline(text, cursor: isLast)
            }
            .padding(.leading, 2)
        case let .code(code):
            Text(code + (showsCursor && isLast ? " ▍" : ""))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HunRoundedShape().fill(AppTheme.searchField))
        }
    }

    private func inline(_ text: String, cursor: Bool) -> some View {
        var line = Text(Self.inlineMarkdown(text))
        if showsCursor && cursor {
            line = line + Text(" ▍").foregroundColor(AppTheme.accent.opacity(cursorOn ? 0.9 : 0.2))
        }
        return line
            .font(.system(size: 12.5))
            .foregroundStyle(color)
            .lineSpacing(2.5)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// `code` and **bold** as the agent wrote them.
    static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// Splits the reply into blocks. Lines in a paragraph are joined, as in markdown.
    static func blocks(in text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(rawLine)
                continue
            }
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let match = line.range(of: #"^\d+[.)] "#, options: .regularExpression) {
                flushParagraph()
                let number = String(line[match]).trimmingCharacters(in: .whitespaces)
                blocks.append(.numbered(number, String(line[match.upperBound...])))
            } else if line.hasPrefix("#") {
                flushParagraph()
                blocks.append(.heading(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        // A code block still being streamed.
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }
}
