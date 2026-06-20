import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddProjectButton: View {
    @Environment(HunStore.self) private var store
    @State private var showImporter = false
    @State private var hovering = false

    var body: some View {
        @Bindable var store = store
        Button {
            if store.pendingProjectReview == nil {
                showImporter = true
            }
        } label: {
            HStack(spacing: 8) {
                if store.isAddingProject {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 14)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 14)
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
                Spacer(minLength: 4)
                Text("⌘N")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
                    .opacity(hovering && !store.isAddingProject ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? AppTheme.hover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isAddingProject)
        .opacity(store.isAddingProject ? 0.75 : 1)
        .onHover { hovering = $0 }
        .help("Run hun init in a project folder")
        .keyboardShortcut("n", modifiers: .command)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await store.addProject(at: url) }
        }
        .sheet(item: $store.pendingProjectReview) { review in
            AddProjectReviewSheet(
                review: review,
                isWorking: store.isAddingProject,
                onAccept: { Task { await store.acceptPendingProject() } },
                onImproveWithAI: { store.copyAgentPrompt(for: review) },
                onOpenConfig: { store.openConfig(for: review) },
                onDiscard: { store.discardPendingProject() }
            )
        }
    }

    private var title: String {
        if store.isAddingProject {
            return "Scanning project"
        }
        if store.pendingProjectReview != nil {
            return "Review project"
        }
        return "Add project"
    }
}

private struct AddProjectReviewSheet: View {
    let review: HunProjectInitReview
    let isWorking: Bool
    let onAccept: () -> Void
    let onImproveWithAI: () -> Void
    let onOpenConfig: () -> Void
    let onDiscard: () -> Void

    @State private var copiedPrompt = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(AppTheme.divider).frame(height: 1)
            yamlPreview
            Rectangle().fill(AppTheme.divider).frame(height: 1)
            footer
        }
        .frame(width: 680, height: 520)
        .background(AppTheme.appBackground)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    iconBadge
                    VStack(alignment: .leading, spacing: 3) {
                        Text(review.createdConfig ? "Review generated .hun.yml" : "Review existing .hun.yml")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(collapsePath(review.path))
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                HStack(spacing: 6) {
                    ReviewChip(text: review.name, systemImage: "app")
                    ReviewChip(text: serviceSummary, systemImage: "rectangle.stack")
                    if review.createdConfig {
                        ReviewChip(text: "Generated", systemImage: "sparkles", accent: true)
                    } else {
                        ReviewChip(text: "Existing", systemImage: "checkmark.circle")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            CloseButton(action: onDiscard)
                .padding(.top, 12)
                .padding(.trailing, 12)
        }
    }

    private var iconBadge: some View {
        Image(systemName: review.createdConfig ? "doc.badge.plus" : "doc.text.magnifyingglass")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.accent.opacity(0.20), lineWidth: 1)
            )
    }

    // MARK: - YAML preview

    private var yamlPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(".hun.yml")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)

            YamlScrollView(text: review.configContents)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.searchField)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.divider, lineWidth: 1)
                )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            ReviewActionButton(
                title: review.createdConfig ? "Discard" : "Cancel",
                style: .quiet,
                enabled: !isWorking,
                action: onDiscard
            )

            Spacer()

            ReviewActionButton(
                title: "Open in editor",
                systemImage: "arrow.up.right.square",
                style: .secondary,
                enabled: !isWorking,
                action: onOpenConfig
            )

            ReviewActionButton(
                title: copiedPrompt ? "Prompt copied" : "Improve with AI",
                systemImage: copiedPrompt ? "checkmark" : "sparkles",
                style: .secondary,
                enabled: !isWorking,
                success: copiedPrompt,
                action: improveWithAI
            )

            ReviewActionButton(
                title: "Accept",
                systemImage: "checkmark",
                style: .primary,
                enabled: !isWorking,
                isLoading: isWorking,
                action: onAccept
            )
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func improveWithAI() {
        onImproveWithAI()
        withAnimation(.easeOut(duration: 0.16)) { copiedPrompt = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.2)) { copiedPrompt = false }
        }
    }

    // MARK: - Helpers

    private var serviceSummary: String {
        let count = review.serviceNames.count
        if count == 0 { return "No services" }
        if count == 1 { return review.serviceNames[0] }
        return "\(count) services"
    }

    private func collapsePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Building blocks

private struct ReviewChip: View {
    let text: String
    let systemImage: String
    var accent: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 9.5, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(accent ? AppTheme.accent : AppTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(accent ? AppTheme.accent.opacity(0.13) : AppTheme.searchField)
        )
        .overlay(
            Capsule().stroke(accent ? AppTheme.accent.opacity(0.25) : AppTheme.divider, lineWidth: 0.5)
        )
    }
}

private struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textTertiary)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(hovering ? AppTheme.hover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .onHover { hovering = $0 }
        .help("Close (esc)")
    }
}

private enum ReviewButtonStyle { case primary, secondary, quiet }

private struct ReviewActionButton: View {
    let title: String
    var systemImage: String? = nil
    let style: ReviewButtonStyle
    var enabled: Bool = true
    var success: Bool = false
    var isLoading: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(textColor)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 11)
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
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 && enabled }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: success)
    }

    private var textColor: Color {
        if success { return AppTheme.success }
        switch style {
        case .primary: return .white
        case .secondary: return AppTheme.textPrimary
        case .quiet: return hovering ? AppTheme.textPrimary : AppTheme.textSecondary
        }
    }

    private var background: Color {
        if success { return AppTheme.success.opacity(0.12) }
        switch style {
        case .primary: return AppTheme.accent.opacity(hovering ? 1 : 0.92)
        case .secondary: return hovering ? AppTheme.hover : AppTheme.buttonFill
        case .quiet: return hovering ? AppTheme.hover : Color.clear
        }
    }

    private var border: Color {
        if success { return AppTheme.success.opacity(0.35) }
        switch style {
        case .primary: return Color.white.opacity(0.10)
        case .secondary: return AppTheme.divider
        case .quiet: return Color.clear
        }
    }
}

// MARK: - YAML preview (NSScrollView so we get the same slim scroller as the log pane)

private struct YamlScrollView: NSViewRepresentable {
    let text: String

    final class Coordinator {
        var lastText: String = ""
        weak var scroller: ThinLogScroller?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let scroller = ThinLogScroller()
        scroll.verticalScroller = scroller
        scroller.alphaValue = 0
        scroller.setVisible(true, animated: false)
        context.coordinator.scroller = scroller

        let textView = NSTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0,
                                                        height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 12)
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
        textView.linkTextAttributes = [:]
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(AppTheme.accent).withAlphaComponent(0.32),
            .foregroundColor: NSColor(white: 0.96, alpha: 1)
        ]

        scroll.documentView = textView
        applyText(to: textView, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if context.coordinator.lastText != text {
            applyText(to: textView, context: context)
        }
    }

    private func applyText(to textView: NSTextView, context: Context) {
        let attr = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(AppTheme.textSecondary)
        ])
        textView.textStorage?.setAttributedString(attr)
        context.coordinator.lastText = text
    }
}

