import AppKit
import SwiftUI

nonisolated enum HunGitDiffPresentation: String, CaseIterable, Sendable {
    case unified
    case split

    var title: String {
        switch self {
        case .unified: "Unified"
        case .split: "Split"
        }
    }
}

struct HunGitDiffView: NSViewRepresentable {
    let document: HunGitDiffDocument
    let path: String
    let presentation: HunGitDiffPresentation
    let showWhitespace: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> HunGitDiffScrollView {
        let scrollView = HunGitDiffScrollView()
        let tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diff"))

        column.resizingMask = []
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = HunGitDiffMetrics.rowHeight
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnSelection = false
        tableView.allowsMultipleSelection = false
        tableView.backgroundColor = HunGitDiffPalette.canvas
        tableView.focusRingType = .none
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        scrollView.drawsBackground = true
        scrollView.backgroundColor = HunGitDiffPalette.canvas
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.enableHorizontalScroller()
        scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let coordinator, let scrollView else { return }
            coordinator.resizeTable(in: scrollView)
        }

        context.coordinator.tableView = tableView
        context.coordinator.update(
            document: document,
            path: path,
            presentation: presentation,
            showWhitespace: showWhitespace,
            in: scrollView
        )
        return scrollView
    }

    func updateNSView(_ scrollView: HunGitDiffScrollView, context: Context) {
        context.coordinator.update(
            document: document,
            path: path,
            presentation: presentation,
            showWhitespace: showWhitespace,
            in: scrollView
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var tableView: NSTableView?
        private var document: HunGitDiffDocument?
        private var presentation = HunGitDiffPresentation.unified
        private var showWhitespace = false
        private var documentID: UUID?
        private var syntaxPath = ""
        private var syntaxHighlighter = HunGitSyntaxHighlighter(path: "")

        func update(
            document: HunGitDiffDocument,
            path: String,
            presentation: HunGitDiffPresentation,
            showWhitespace: Bool,
            in scrollView: HunGitDiffScrollView
        ) {
            let contentChanged = documentID != document.id
            let modeChanged = self.presentation != presentation
            let whitespaceChanged = self.showWhitespace != showWhitespace
            let pathChanged = syntaxPath != path
            guard contentChanged || modeChanged || whitespaceChanged || pathChanged else {
                resizeTable(in: scrollView)
                return
            }

            let anchor = visibleAnchor()
            self.document = document
            self.documentID = document.id
            self.presentation = presentation
            self.showWhitespace = showWhitespace
            syntaxPath = path
            syntaxHighlighter = HunGitSyntaxHighlighter(path: path)
            tableView?.reloadData()
            resizeTable(in: scrollView)

            if contentChanged {
                tableView?.scrollRowToVisible(0)
            } else if modeChanged, let anchor {
                restore(anchor: anchor)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            guard let document else { return 0 }
            switch presentation {
            case .unified: return document.lines.count
            case .split: return document.splitRows.count
            }
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("HunGitDiffRow")
            let rowView = tableView.makeView(withIdentifier: identifier, owner: nil) as? HunGitDiffRowView
                ?? HunGitDiffRowView()
            rowView.identifier = identifier

            if presentation == .unified, let line = document?.lines[row] {
                rowView.configure(
                    unified: line,
                    blockPosition: document?.blockPosition(at: row) ?? .none,
                    syntaxState: document?.unifiedSyntaxState(at: row) ?? .normal,
                    syntaxHighlighter: syntaxHighlighter,
                    showWhitespace: showWhitespace
                )
            } else if let document {
                let splitRow = document.splitRows[row]
                rowView.configure(
                    split: splitRow,
                    lines: document.lines,
                    leftBlockPosition: document.splitBlockPosition(at: row, side: .left),
                    rightBlockPosition: document.splitBlockPosition(at: row, side: .right),
                    leftSyntaxState: splitRow.leftIndex.map {
                        document.syntaxState(at: $0, side: .left)
                    } ?? .normal,
                    rightSyntaxState: splitRow.rightIndex.map {
                        document.syntaxState(at: $0, side: .right)
                    } ?? .normal,
                    syntaxHighlighter: syntaxHighlighter,
                    showWhitespace: showWhitespace
                )
            }
            return rowView
        }

        func resizeTable(in scrollView: HunGitDiffScrollView) {
            guard let tableView, let column = tableView.tableColumns.first, let document else { return }

            let viewportWidth = max(1, scrollView.contentSize.width)
            let characterWidth = HunGitDiffMetrics.characterWidth
            let contentWidth: CGFloat
            switch presentation {
            case .unified:
                contentWidth =
                    HunGitDiffMetrics.unifiedCodeOffset +
                    CGFloat(min(document.longestUnifiedLine, HunGitDiffMetrics.maximumMeasuredColumns)) *
                        characterWidth +
                    HunGitDiffMetrics.trailingPadding
            case .split:
                let availableCodeWidth = max(
                    1,
                    viewportWidth / 2 - HunGitDiffMetrics.splitCodeOffset -
                        HunGitDiffMetrics.trailingPadding
                )
                let longestLineWidth =
                    CGFloat(min(document.longestSplitLine, HunGitDiffMetrics.maximumMeasuredColumns)) *
                    characterWidth
                contentWidth = viewportWidth + max(0, longestLineWidth - availableCodeWidth)
            }

            let width = max(viewportWidth, contentWidth)
            guard abs(column.width - width) > 0.5 else { return }
            column.width = width
            tableView.frame.size.width = width
        }

        private func visibleAnchor() -> Double? {
            guard let tableView else { return nil }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound, tableView.numberOfRows > 1 else { return nil }
            return Double(visibleRows.location) / Double(tableView.numberOfRows - 1)
        }

        private func restore(anchor: Double) {
            guard let tableView, tableView.numberOfRows > 0 else { return }
            let row = min(
                tableView.numberOfRows - 1,
                max(0, Int(anchor * Double(tableView.numberOfRows - 1)))
            )
            tableView.scrollRowToVisible(row)
        }
    }
}

final class HunGitDiffScrollView: HunStyledScrollView {
    var onLayout: (() -> Void)?
    private var lastHorizontalOrigin: CGFloat = 0

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        guard clipView === contentView else { return }
        let horizontalOrigin = clipView.bounds.minX
        guard abs(horizontalOrigin - lastHorizontalOrigin) > 0.5 else { return }
        lastHorizontalOrigin = horizontalOrigin
        guard let tableView = documentView as? NSTableView else { return }
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.location != NSNotFound else { return }
        for row in visibleRows.location..<NSMaxRange(visibleRows) {
            tableView.view(atColumn: 0, row: row, makeIfNecessary: false)?.needsDisplay = true
        }
    }
}

private enum HunGitDiffMetrics {
    static let rowHeight: CGFloat = 21
    static let numberWidth: CGFloat = 38
    static let markerWidth: CGFloat = 18
    static let unifiedCodeOffset: CGFloat = 92
    static let splitCodeOffset: CGFloat = 66
    static let trailingPadding: CGFloat = 22
    static let maximumMeasuredColumns = 20_000
    static let font = NSFont.monospacedSystemFont(ofSize: 11.25, weight: .regular)
    static let characterWidth = ceil(("M" as NSString).size(withAttributes: [.font: font]).width)
}

private enum HunGitDiffPalette {
    static let canvas = NSColor(srgbRed: 0.012, green: 0.012, blue: 0.012, alpha: 1)
    static let gutter = NSColor.white.withAlphaComponent(0.018)
    static let divider = NSColor.white.withAlphaComponent(0.065)
    static let code = NSColor.white.withAlphaComponent(0.68)
    static let lineNumber = NSColor.white.withAlphaComponent(0.28)
    static let addition = NSColor(srgbRed: 0.34, green: 0.78, blue: 0.45, alpha: 0.92)
    static let deletion = NSColor(srgbRed: 0.93, green: 0.45, blue: 0.45, alpha: 0.92)
    static let additionFill = NSColor(srgbRed: 0.20, green: 0.72, blue: 0.35, alpha: 0.075)
    static let deletionFill = NSColor(srgbRed: 0.88, green: 0.30, blue: 0.30, alpha: 0.075)
    static let keyword = NSColor(srgbRed: 0.78, green: 0.62, blue: 0.98, alpha: 0.96)
    static let string = NSColor(srgbRed: 0.91, green: 0.72, blue: 0.43, alpha: 0.96)
    static let number = NSColor(srgbRed: 0.48, green: 0.72, blue: 0.96, alpha: 0.96)
    static let comment = NSColor(srgbRed: 0.49, green: 0.58, blue: 0.51, alpha: 0.82)
    static let type = NSColor(srgbRed: 0.42, green: 0.80, blue: 0.82, alpha: 0.96)
    static let property = NSColor(srgbRed: 0.52, green: 0.70, blue: 0.94, alpha: 0.96)
    static let heading = NSColor(srgbRed: 0.84, green: 0.67, blue: 0.98, alpha: 0.96)
}

private struct HunGitRenderedLine {
    let line: HunGitDiffLine
    let blockPosition: HunGitDiffBlockPosition
    let attributedContent: NSAttributedString
}

private struct HunGitRenderedSplitRow {
    let left: HunGitRenderedLine?
    let right: HunGitRenderedLine?
    let isSeparator: Bool
}

private final class HunGitDiffRowView: NSView {
    private enum Content {
        case unified(HunGitRenderedLine)
        case split(HunGitRenderedSplitRow)
    }

    private var content = Content.unified(
        HunGitRenderedLine(
            line: HunGitDiffLine(
                kind: .context,
                content: "",
                oldLineNumber: nil,
                newLineNumber: nil
            ),
            blockPosition: .none,
            attributedContent: NSAttributedString(string: "")
        )
    )

    override var isFlipped: Bool {
        true
    }

    func configure(
        unified line: HunGitDiffLine,
        blockPosition: HunGitDiffBlockPosition,
        syntaxState: HunGitSyntaxState,
        syntaxHighlighter: HunGitSyntaxHighlighter,
        showWhitespace: Bool
    ) {
        content = .unified(
            renderedLine(
                line,
                blockPosition: blockPosition,
                syntaxState: syntaxState,
                syntaxHighlighter: syntaxHighlighter,
                showWhitespace: showWhitespace
            )
        )
        toolTip = line.content
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(accessibilityLabel(for: line))
        needsDisplay = true
    }

    func configure(
        split row: HunGitSplitDiffRow,
        lines: [HunGitDiffLine],
        leftBlockPosition: HunGitDiffBlockPosition,
        rightBlockPosition: HunGitDiffBlockPosition,
        leftSyntaxState: HunGitSyntaxState,
        rightSyntaxState: HunGitSyntaxState,
        syntaxHighlighter: HunGitSyntaxHighlighter,
        showWhitespace: Bool
    ) {
        let renderedRow = HunGitRenderedSplitRow(
            left: row.left(in: lines).map {
                renderedLine(
                    $0,
                    blockPosition: leftBlockPosition,
                    syntaxState: leftSyntaxState,
                    syntaxHighlighter: syntaxHighlighter,
                    showWhitespace: showWhitespace
                )
            },
            right: row.right(in: lines).map {
                renderedLine(
                    $0,
                    blockPosition: rightBlockPosition,
                    syntaxState: rightSyntaxState,
                    syntaxHighlighter: syntaxHighlighter,
                    showWhitespace: showWhitespace
                )
            },
            isSeparator: row.isSeparator
        )
        content = .split(renderedRow)
        switch (renderedRow.left?.line.content, renderedRow.right?.line.content) {
        case let (left?, right?) where left != right:
            toolTip = "Before: \(left)\nAfter: \(right)"
        case let (left?, _):
            toolTip = left
        case let (_, right?):
            toolTip = right
        default:
            toolTip = nil
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(accessibilityLabel(for: renderedRow))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        HunGitDiffPalette.canvas.setFill()
        bounds.fill()

        switch content {
        case let .unified(renderedLine):
            drawUnified(renderedLine)
        case let .split(row):
            drawSplit(row)
        }
    }

    private func drawUnified(_ renderedLine: HunGitRenderedLine) {
        let line = renderedLine.line
        let visibleRect = enclosingScrollView?.contentView.bounds ?? bounds
        if line.kind == .separator {
            drawSeparator(
                from: visibleRect.minX + HunGitDiffMetrics.unifiedCodeOffset,
                to: visibleRect.maxX - 8
            )
            return
        }

        NSColor.white.withAlphaComponent(0.018).setFill()
        NSRect(
            x: visibleRect.minX,
            y: 0,
            width: HunGitDiffMetrics.unifiedCodeOffset - 6,
            height: bounds.height
        ).fill()
        drawVerticalDivider(at: visibleRect.minX + HunGitDiffMetrics.unifiedCodeOffset - 6)
        drawChangeBackground(
            kind: line.kind,
            blockPosition: renderedLine.blockPosition,
            rect: NSRect(
                x: visibleRect.minX + 4,
                y: 0,
                width: max(0, visibleRect.width - 8),
                height: bounds.height
            )
        )

        drawText(
            line.oldLineNumber.map(String.init) ?? "",
            rect: NSRect(
                x: visibleRect.minX + 4,
                y: 0,
                width: HunGitDiffMetrics.numberWidth,
                height: bounds.height
            ),
            color: HunGitDiffPalette.lineNumber,
            alignment: .right
        )
        drawText(
            line.newLineNumber.map(String.init) ?? "",
            rect: NSRect(
                x: visibleRect.minX + 45,
                y: 0,
                width: HunGitDiffMetrics.numberWidth,
                height: bounds.height
            ),
            color: HunGitDiffPalette.lineNumber,
            alignment: .right
        )
        drawText(
            marker(for: line.kind),
            rect: NSRect(
                x: visibleRect.minX + 88,
                y: 0,
                width: HunGitDiffMetrics.markerWidth,
                height: bounds.height
            ),
            color: color(for: line.kind),
            alignment: .left
        )
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(
            rect: NSRect(
                x: visibleRect.minX + HunGitDiffMetrics.unifiedCodeOffset,
                y: 0,
                width: max(1, visibleRect.width - HunGitDiffMetrics.unifiedCodeOffset),
                height: bounds.height
            )
        ).addClip()
        drawAttributedText(
            renderedLine.attributedContent,
            rect: NSRect(
                x: HunGitDiffMetrics.unifiedCodeOffset + 14,
                y: 0,
                width: max(1, bounds.width - HunGitDiffMetrics.unifiedCodeOffset - 18),
                height: bounds.height
            )
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSplit(_ row: HunGitRenderedSplitRow) {
        let visibleRect = enclosingScrollView?.contentView.bounds ?? bounds
        let halfWidth = floor(visibleRect.width / 2)
        let midpoint = visibleRect.minX + halfWidth
        if row.isSeparator {
            drawSeparator(
                from: visibleRect.minX + HunGitDiffMetrics.splitCodeOffset,
                to: visibleRect.maxX - 8
            )
            return
        }

        drawHalf(
            row.left,
            chromeOriginX: visibleRect.minX,
            textOriginX: 0,
            width: halfWidth
        )
        drawHalf(
            row.right,
            chromeOriginX: midpoint,
            textOriginX: halfWidth,
            width: visibleRect.width - halfWidth
        )
        drawVerticalDivider(at: midpoint)
    }

    private func drawHalf(
        _ renderedLine: HunGitRenderedLine?,
        chromeOriginX: CGFloat,
        textOriginX: CGFloat,
        width: CGFloat
    ) {
        HunGitDiffPalette.gutter.setFill()
        NSRect(
            x: chromeOriginX,
            y: 0,
            width: HunGitDiffMetrics.splitCodeOffset - 5,
            height: bounds.height
        ).fill()
        drawVerticalDivider(at: chromeOriginX + HunGitDiffMetrics.splitCodeOffset - 5)
        guard let renderedLine else { return }
        let line = renderedLine.line

        drawChangeBackground(
            kind: line.kind,
            blockPosition: renderedLine.blockPosition,
            rect: NSRect(
                x: chromeOriginX + 4,
                y: 0,
                width: max(0, width - 8),
                height: bounds.height
            )
        )
        let number = line.oldLineNumber ?? line.newLineNumber
        drawText(
            number.map(String.init) ?? "",
            rect: NSRect(
                x: chromeOriginX + 4,
                y: 0,
                width: HunGitDiffMetrics.numberWidth,
                height: bounds.height
            ),
            color: HunGitDiffPalette.lineNumber,
            alignment: .right
        )
        drawText(
            marker(for: line.kind),
            rect: NSRect(x: chromeOriginX + 47, y: 0, width: 14, height: bounds.height),
            color: color(for: line.kind),
            alignment: .center
        )
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(
            rect: NSRect(
                x: chromeOriginX + HunGitDiffMetrics.splitCodeOffset,
                y: 0,
                width: max(1, width - HunGitDiffMetrics.splitCodeOffset),
                height: bounds.height
            )
        ).addClip()
        drawAttributedText(
            renderedLine.attributedContent,
            rect: NSRect(
                x: textOriginX + HunGitDiffMetrics.splitCodeOffset + 8,
                y: 0,
                width: max(
                    1,
                    bounds.width - textOriginX - HunGitDiffMetrics.splitCodeOffset - 12
                ),
                height: bounds.height
            )
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawChangeBackground(
        kind: HunGitDiffLineKind,
        blockPosition: HunGitDiffBlockPosition,
        rect: NSRect
    ) {
        let fill: NSColor
        switch kind {
        case .addition: fill = HunGitDiffPalette.additionFill
        case .deletion: fill = HunGitDiffPalette.deletionFill
        case .context, .separator: return
        }
        fill.setFill()
        let radius: CGFloat = 4
        switch blockPosition {
        case .none:
            return
        case .single:
            NSBezierPath(
                roundedRect: rect.insetBy(dx: 0, dy: 1),
                xRadius: radius,
                yRadius: radius
            ).fill()
        case .first:
            NSBezierPath(
                roundedRect: NSRect(
                    x: rect.minX,
                    y: rect.minY + 1,
                    width: rect.width,
                    height: rect.height + radius
                ),
                xRadius: radius,
                yRadius: radius
            ).fill()
        case .middle:
            rect.fill()
        case .last:
            NSBezierPath(
                roundedRect: NSRect(
                    x: rect.minX,
                    y: rect.minY - radius,
                    width: rect.width,
                    height: rect.height + radius - 1
                ),
                xRadius: radius,
                yRadius: radius
            ).fill()
        }
    }

    private func drawSeparator(from start: CGFloat, to end: CGFloat) {
        HunGitDiffPalette.divider.setFill()
        NSRect(
            x: start,
            y: floor(bounds.midY),
            width: max(0, end - start),
            height: 1
        ).fill()
    }

    private func drawVerticalDivider(at x: CGFloat) {
        HunGitDiffPalette.divider.setFill()
        NSRect(x: floor(x), y: 0, width: 1, height: bounds.height).fill()
    }

    private func marker(for kind: HunGitDiffLineKind) -> String {
        switch kind {
        case .addition: "+"
        case .deletion: "−"
        case .context, .separator: ""
        }
    }

    private func color(for kind: HunGitDiffLineKind) -> NSColor {
        switch kind {
        case .addition: HunGitDiffPalette.addition
        case .deletion: HunGitDiffPalette.deletion
        case .context, .separator: HunGitDiffPalette.code
        }
    }

    private func renderedLine(
        _ line: HunGitDiffLine,
        blockPosition: HunGitDiffBlockPosition,
        syntaxState: HunGitSyntaxState,
        syntaxHighlighter: HunGitSyntaxHighlighter,
        showWhitespace: Bool
    ) -> HunGitRenderedLine {
        let text = line.displayContent(showWhitespace: showWhitespace)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byClipping
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: HunGitDiffMetrics.font,
                .foregroundColor: color(for: line.kind),
                .paragraphStyle: paragraph
            ]
        )

        for token in syntaxHighlighter.tokenize(text, startingIn: syntaxState).tokens {
            attributedText.addAttribute(
                .foregroundColor,
                value: syntaxColor(for: token.kind),
                range: token.range
            )
        }

        return HunGitRenderedLine(
            line: line,
            blockPosition: blockPosition,
            attributedContent: attributedText
        )
    }

    private func syntaxColor(for kind: HunGitSyntaxTokenKind) -> NSColor {
        switch kind {
        case .keyword: HunGitDiffPalette.keyword
        case .string: HunGitDiffPalette.string
        case .number: HunGitDiffPalette.number
        case .comment: HunGitDiffPalette.comment
        case .type: HunGitDiffPalette.type
        case .property: HunGitDiffPalette.property
        case .heading: HunGitDiffPalette.heading
        }
    }

    private func accessibilityLabel(for line: HunGitDiffLine) -> String {
        let lineNumber = line.newLineNumber ?? line.oldLineNumber
        let prefix: String
        switch line.kind {
        case .addition: prefix = "Added"
        case .deletion: prefix = "Removed"
        case .context: prefix = "Unchanged"
        case .separator: return "Next change"
        }
        return "\(prefix), line \(lineNumber.map(String.init) ?? "unknown"): \(line.content)"
    }

    private func accessibilityLabel(for row: HunGitRenderedSplitRow) -> String {
        if row.isSeparator { return "Next change" }
        switch (row.left, row.right) {
        case let (left?, right?)
            where left.line.kind == .deletion && right.line.kind == .addition:
            return "Changed from \(left.line.content) to \(right.line.content)"
        case let (left?, _):
            return accessibilityLabel(for: left.line)
        case let (_, right?):
            return accessibilityLabel(for: right.line)
        default:
            return "Empty diff row"
        }
    }

    private func drawText(
        _ text: String,
        rect: NSRect,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        let textHeight = HunGitDiffMetrics.font.ascender - HunGitDiffMetrics.font.descender
        let y = floor((rect.height - textHeight) / 2)
        (text as NSString).draw(
            in: NSRect(x: rect.minX, y: rect.minY + y, width: rect.width, height: textHeight + 2),
            withAttributes: [
                .font: HunGitDiffMetrics.font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func drawAttributedText(_ text: NSAttributedString, rect: NSRect) {
        let textHeight = HunGitDiffMetrics.font.ascender - HunGitDiffMetrics.font.descender
        let y = floor((rect.height - textHeight) / 2)
        text.draw(
            in: NSRect(
                x: rect.minX,
                y: rect.minY + y,
                width: rect.width,
                height: textHeight + 2
            )
        )
    }
}
