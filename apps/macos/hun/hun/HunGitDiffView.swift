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
            presentation: presentation,
            showWhitespace: showWhitespace,
            in: scrollView
        )
        return scrollView
    }

    func updateNSView(_ scrollView: HunGitDiffScrollView, context: Context) {
        context.coordinator.update(
            document: document,
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

        func update(
            document: HunGitDiffDocument,
            presentation: HunGitDiffPresentation,
            showWhitespace: Bool,
            in scrollView: HunGitDiffScrollView
        ) {
            let contentChanged = documentID != document.id
            let modeChanged = self.presentation != presentation
            let whitespaceChanged = self.showWhitespace != showWhitespace
            guard contentChanged || modeChanged || whitespaceChanged else {
                resizeTable(in: scrollView)
                return
            }

            let anchor = visibleAnchor()
            self.document = document
            self.documentID = document.id
            self.presentation = presentation
            self.showWhitespace = showWhitespace
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
                rowView.configure(unified: line, showWhitespace: showWhitespace)
            } else if let document {
                rowView.configure(
                    split: document.splitRows[row],
                    lines: document.lines,
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
}

private struct HunGitRenderedSplitRow {
    let left: HunGitDiffLine?
    let right: HunGitDiffLine?
    let isSeparator: Bool
}

private final class HunGitDiffRowView: NSView {
    private enum Content {
        case unified(HunGitDiffLine)
        case split(HunGitRenderedSplitRow)
    }

    private var content = Content.unified(
        HunGitDiffLine(kind: .context, content: "", oldLineNumber: nil, newLineNumber: nil)
    )
    private var showWhitespace = false

    override var isFlipped: Bool { true }

    func configure(unified line: HunGitDiffLine, showWhitespace: Bool) {
        content = .unified(line)
        self.showWhitespace = showWhitespace
        toolTip = line.content
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(accessibilityLabel(for: line))
        needsDisplay = true
    }

    func configure(
        split row: HunGitSplitDiffRow,
        lines: [HunGitDiffLine],
        showWhitespace: Bool
    ) {
        let renderedRow = HunGitRenderedSplitRow(
            left: row.left(in: lines),
            right: row.right(in: lines),
            isSeparator: row.isSeparator
        )
        content = .split(renderedRow)
        self.showWhitespace = showWhitespace
        switch (renderedRow.left?.content, renderedRow.right?.content) {
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
        case let .unified(line):
            drawUnified(line)
        case let .split(row):
            drawSplit(row)
        }
    }

    private func drawUnified(_ line: HunGitDiffLine) {
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
            rect: NSRect(
                x: visibleRect.minX + 4,
                y: 1,
                width: max(0, visibleRect.width - 8),
                height: bounds.height - 2
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
        drawText(
            line.displayContent(showWhitespace: showWhitespace),
            rect: NSRect(
                x: HunGitDiffMetrics.unifiedCodeOffset + 14,
                y: 0,
                width: max(1, bounds.width - HunGitDiffMetrics.unifiedCodeOffset - 18),
                height: bounds.height
            ),
            color: color(for: line.kind),
            alignment: .left
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
        _ line: HunGitDiffLine?,
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
        guard let line else { return }

        drawChangeBackground(
            kind: line.kind,
            rect: NSRect(
                x: chromeOriginX + 4,
                y: 1,
                width: max(0, width - 8),
                height: bounds.height - 2
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
        drawText(
            line.displayContent(showWhitespace: showWhitespace),
            rect: NSRect(
                x: textOriginX + HunGitDiffMetrics.splitCodeOffset + 8,
                y: 0,
                width: max(
                    1,
                    bounds.width - textOriginX - HunGitDiffMetrics.splitCodeOffset - 12
                ),
                height: bounds.height
            ),
            color: color(for: line.kind),
            alignment: .left
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawChangeBackground(kind: HunGitDiffLineKind, rect: NSRect) {
        let fill: NSColor
        switch kind {
        case .addition: fill = HunGitDiffPalette.additionFill
        case .deletion: fill = HunGitDiffPalette.deletionFill
        case .context, .separator: return
        }
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
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
        case let (left?, right?) where left.kind == .deletion && right.kind == .addition:
            return "Changed from \(left.content) to \(right.content)"
        case let (left?, _):
            return accessibilityLabel(for: left)
        case let (_, right?):
            return accessibilityLabel(for: right)
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
}
