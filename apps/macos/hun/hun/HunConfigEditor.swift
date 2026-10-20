import AppKit
import SwiftUI

/// A project's .hun.yml, opened for editing inside Hun.
struct HunConfigEditorTarget: Identifiable, Hashable {
    let name: String
    /// The project folder that holds the .hun.yml.
    let directory: String

    var id: String { directory }
    var fileURL: URL { URL(fileURLWithPath: directory).appendingPathComponent(".hun.yml") }
}

/// Edits .hun.yml in place. The text is checked as you type with the same
/// rules the daemon runs on, and only a config Hun can run is saved.
struct HunConfigEditorSheet: View {
    let target: HunConfigEditorTarget
    let validate: (String) async -> String?
    let save: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var savedText = ""
    @State private var loadError: String?
    @State private var problem: String?
    @State private var isChecking = false
    @State private var isSaving = false
    @State private var confirmingDiscard = false

    private var hasChanges: Bool { text != savedText }
    private var canSave: Bool { hasChanges && problem == nil && !isChecking && !isSaving && loadError == nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(AppTheme.divider).frame(height: 1)
            if let loadError {
                Text(loadError)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.danger)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HunCodeEditor(
                    text: $text,
                    errorLine: problem.flatMap(Self.lineNumber),
                    onEscape: close
                )
                .clipped()
            }
            Rectangle().fill(AppTheme.divider).frame(height: 1)
            footer
        }
        .frame(width: 820, height: 640)
        .background(AppTheme.appBackground)
        .task { load() }
        .task(id: text) { await check() }
        .confirmationDialog(
            "Discard your changes to .hun.yml?",
            isPresented: $confirmingDiscard
        ) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(".hun.yml")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
            Text(target.name)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if hasChanges {
                Circle()
                    .fill(AppTheme.textTertiary)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }
            Spacer(minLength: 12)
            Text(collapsedPath(target.fileURL.path))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            status
            Spacer(minLength: 12)
            ActionButton(title: "Cancel", systemImage: "xmark", style: .secondary, action: close)
                .keyboardShortcut(.cancelAction)
            ActionButton(
                title: "Save",
                systemImage: "checkmark",
                style: .primary,
                isLoading: isSaving,
                isDisabled: !canSave,
                action: { Task { await commit() } }
            )
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    @ViewBuilder
    private var status: some View {
        if let problem {
            Label {
                Text(problem)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(AppTheme.danger)
        } else if isChecking || loadError != nil {
            EmptyView()
        } else {
            Label(hasChanges ? "Valid · ⌘S to save" : "Valid", systemImage: "checkmark.circle")
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private func load() {
        do {
            let contents = try String(contentsOf: target.fileURL, encoding: .utf8)
            text = contents
            savedText = contents
        } catch {
            loadError = "Could not read \(target.fileURL.path): \(error.localizedDescription)"
        }
    }

    private func check() async {
        guard loadError == nil else { return }
        isChecking = true
        // Wait for a pause in typing before asking the daemon.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let result = await validate(text)
        guard !Task.isCancelled else { return }
        problem = result
        isChecking = false
    }

    private func commit() async {
        guard canSave else { return }
        isSaving = true
        let snapshot = text
        if let error = await save(snapshot) {
            problem = error
            isSaving = false
            return
        }
        savedText = snapshot
        isSaving = false
        dismiss()
    }

    private func close() {
        if hasChanges {
            confirmingDiscard = true
        } else {
            dismiss()
        }
    }

    /// The line a YAML error points at, as in "yaml: line 12: …".
    static func lineNumber(in message: String) -> Int? {
        guard let range = message.range(of: #"line (\d+)"#, options: .regularExpression) else { return nil }
        return Int(message[range].dropFirst(5))
    }

    private func collapsedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: - Code editor

/// A plain-text YAML editor: monospaced, highlighted, with line numbers,
/// two-space tabs and indentation carried to the next line.
struct HunCodeEditor: NSViewRepresentable {
    @Binding var text: String
    var errorLine: Int?
    var onEscape: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.font = HunYAMLHighlighter.font
        textView.string = text

        let ruler = HunLineNumberRuler(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        applyAppearance(to: scrollView, textView: textView)
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.ruler?.errorLine = errorLine
        applyAppearance(to: scrollView, textView: textView)
    }

    private func applyAppearance(to scrollView: NSScrollView, textView: NSTextView) {
        _ = colorScheme // Re-highlight when the appearance changes.
        let background = NSColor(AppTheme.appBackground)
        scrollView.backgroundColor = background
        textView.backgroundColor = background
        textView.insertionPointColor = NSColor(AppTheme.textPrimary)
        textView.selectedTextAttributes = [.backgroundColor: NSColor(AppTheme.accent).withAlphaComponent(0.32)]
        HunYAMLHighlighter.highlight(textView)
        scrollView.verticalRulerView?.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HunCodeEditor
        weak var textView: NSTextView?
        weak var ruler: HunLineNumberRuler?

        init(_ parent: HunCodeEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            HunYAMLHighlighter.highlight(textView)
            ruler?.needsDisplay = true
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                textView.insertText("  ", replacementRange: textView.selectedRange())
                return true
            case #selector(NSResponder.insertNewline(_:)):
                textView.insertText("\n" + indentation(after: textView), replacementRange: textView.selectedRange())
                return true
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }

        /// The current line's indentation, one level deeper after a key that
        /// opens a block ("services:") or a list item.
        private func indentation(after textView: NSTextView) -> String {
            let string = textView.string as NSString
            let cursor = textView.selectedRange().location
            let lineRange = string.lineRange(for: NSRange(location: cursor, length: 0))
            let line = string.substring(with: NSRange(location: lineRange.location, length: cursor - lineRange.location))
            let indent = String(line.prefix { $0 == " " })
            let content = line.trimmingCharacters(in: .whitespaces)
            if content.hasSuffix(":") {
                return indent + "  "
            }
            if content.hasPrefix("- ") && content.hasSuffix(":") == false && content.contains(": ") {
                return indent + "  "
            }
            return indent
        }
    }
}

// MARK: - Highlighting

private enum HunYAMLHighlighter {
    static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    private static let key = dynamic(light: 0x2F5F9E, dark: 0x8DB6E6)
    private static let string = dynamic(light: 0x3D7A33, dark: 0xA9CC8E)
    private static let scalar = dynamic(light: 0x9A5712, dark: 0xE2A86C)

    private static let keyPattern = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:-[ \t]+)?([A-Za-z0-9_.\-/]+)(?=[ \t]*:(?:[ \t]|$))"#,
        options: .anchorsMatchLines
    )
    private static let dashPattern = try! NSRegularExpression(
        pattern: #"^[ \t]*(-)(?=[ \t]|$)"#,
        options: .anchorsMatchLines
    )
    private static let stringPattern = try! NSRegularExpression(pattern: #""(?:[^"\\\n]|\\.)*"|'[^'\n]*'"#)
    private static let scalarPattern = try! NSRegularExpression(
        pattern: #"(?<=[:\-\[,][ \t])(-?\d+(?:\.\d+)?|true|false|null|yes|no|on|off|~)(?=[ \t]*(?:[,\]#]|$))"#,
        options: .anchorsMatchLines
    )
    private static let commentPattern = try! NSRegularExpression(
        pattern: #"(?:^|[ \t])(#.*)$"#,
        options: .anchorsMatchLines
    )

    static func highlight(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let text = storage.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        storage.beginEditing()
        storage.setAttributes([
            .font: font,
            .foregroundColor: NSColor(AppTheme.textPrimary).withAlphaComponent(0.86),
        ], range: full)
        apply(dashPattern, group: 1, color: NSColor(AppTheme.textTertiary), in: storage, text: text, range: full)
        apply(keyPattern, group: 1, color: key, in: storage, text: text, range: full)
        apply(scalarPattern, group: 1, color: scalar, in: storage, text: text, range: full)
        apply(stringPattern, group: 0, color: string, in: storage, text: text, range: full)
        apply(commentPattern, group: 1, color: NSColor(AppTheme.textTertiary), in: storage, text: text, range: full)
        storage.endEditing()
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor(AppTheme.textPrimary).withAlphaComponent(0.86),
        ]
    }

    private static func apply(
        _ pattern: NSRegularExpression,
        group: Int,
        color: NSColor,
        in storage: NSTextStorage,
        text: String,
        range: NSRange
    ) {
        pattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, match.range(at: group).location != NSNotFound else { return }
            storage.addAttribute(.foregroundColor, value: color, range: match.range(at: group))
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        func make(_ hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? make(dark) : make(light)
        }
    }
}

// MARK: - Line numbers

final class HunLineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    /// A line the current error points at; its number is drawn in red.
    var errorLine: Int? {
        didSet { if oldValue != errorLine { needsDisplay = true } }
    }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(redraw),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func redraw() {
        needsDisplay = true
    }

    override var isOpaque: Bool { true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Keep numbers for partly visible lines inside the ruler.
        bounds.clip()
        NSColor(AppTheme.appBackground).setFill()
        bounds.fill()
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }

        let string = textView.string as NSString
        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // Start from the beginning of the first visible line, even when only
        // its wrapped tail is on screen.
        let start = string.lineRange(for: NSRange(location: characters.location, length: 0)).location

        var line = 1
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: start),
            options: [.byLines, .substringNotRequired]
        ) { _, _, _, _ in line += 1 }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(AppTheme.textTertiary).withAlphaComponent(0.7)]
        let error: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(AppTheme.danger)]
        let inset = textView.textContainerInset.height

        func draw(_ number: Int, atY y: CGFloat, height: CGFloat) {
            let label = NSAttributedString(string: "\(number)", attributes: number == errorLine ? error : normal)
            let size = label.size()
            let origin = convert(NSPoint(x: 0, y: y + inset), from: textView)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 10, y: origin.y + (height - size.height) / 2))
        }

        var index = start
        let end = NSMaxRange(characters)
        while index < end {
            let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            draw(line, atY: fragment.minY, height: fragment.height)
            line += 1
            index = NSMaxRange(lineRange)
        }
        // The empty line after a trailing newline.
        let extra = layoutManager.extraLineFragmentRect
        if !extra.isEmpty, end == string.length {
            draw(line, atY: extra.minY, height: extra.height)
        }
    }
}
