import AppKit
import SwiftUI

enum HunPanelResizeAxis {
    case horizontal
    case vertical

    fileprivate func coordinate(in point: NSPoint) -> CGFloat {
        switch self {
        case .horizontal:
            point.x
        case .vertical:
            point.y
        }
    }

    fileprivate var cursor: NSCursor {
        switch self {
        case .horizontal:
            .resizeLeftRight
        case .vertical:
            .resizeUpDown
        }
    }

    fileprivate var accessibilityOrientation: NSAccessibilityOrientation {
        switch self {
        case .horizontal:
            .vertical
        case .vertical:
            .horizontal
        }
    }
}

enum HunPanelResizeMetrics {
    static let accessibilityAdjustment: CGFloat = 24
}

enum HunWorkspacePanelMetrics {
    static let servicesDefaultWidth: CGFloat = 320
    static let gitDefaultWidth: CGFloat = 310
    static let minimumWidth: CGFloat = 140
    static let maximumWidth: CGFloat = 640
    static let minimumDetailWidth: CGFloat = 160
    static let splitterWidth: CGFloat = 9

    static func clamp(_ requestedWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let range = allowedRange(availableWidth: availableWidth)
        return min(max(requestedWidth, range.lowerBound), range.upperBound)
    }

    static func allowedRange(availableWidth: CGFloat) -> ClosedRange<CGFloat> {
        let availableMaximum = availableWidth - minimumDetailWidth - splitterWidth
        let maximum = max(minimumWidth, min(maximumWidth, availableMaximum))
        return minimumWidth ... maximum
    }
}

enum HunWorkspacePanelPreference {
    static let servicesWidth = "hun.dashboard.servicesPanelWidth"
    static let gitChangesWidth = "hun.git.changesPanelWidth"
}

struct HunResizableWorkspaceSplit<Primary: View, Detail: View>: View {
    @Binding private var preferredWidth: Double
    private let accessibilityLabel: String
    private let primary: Primary
    private let detail: Detail

    init(
        preferredWidth: Binding<Double>,
        accessibilityLabel: String,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder detail: () -> Detail
    ) {
        _preferredWidth = preferredWidth
        self.accessibilityLabel = accessibilityLabel
        self.primary = primary()
        self.detail = detail()
    }

    var body: some View {
        GeometryReader { proxy in
            let allowedRange = HunWorkspacePanelMetrics.allowedRange(
                availableWidth: proxy.size.width
            )
            let visibleWidth = HunWorkspacePanelMetrics.clamp(
                CGFloat(preferredWidth),
                availableWidth: proxy.size.width
            )

            HStack(spacing: 0) {
                primary
                    .frame(width: visibleWidth)
                    .frame(maxHeight: .infinity)
                    .clipped()

                HunWorkspaceResizeHandle(
                    preferredWidth: $preferredWidth,
                    allowedRange: allowedRange,
                    accessibilityLabel: accessibilityLabel
                )
                .frame(width: HunWorkspacePanelMetrics.splitterWidth)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct HunWorkspaceResizeHandle: View {
    @Binding var preferredWidth: Double
    let allowedRange: ClosedRange<CGFloat>
    let accessibilityLabel: String

    @State private var hovering = false

    var body: some View {
        ZStack {
            HunWorkspaceResizeSurface(
                preferredWidth: $preferredWidth,
                allowedRange: allowedRange,
                accessibilityLabel: accessibilityLabel
            )

            Rectangle()
                .fill(hovering ? AppTheme.dividerStrong : AppTheme.divider)
                .frame(width: hovering ? 2 : 1)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct HunWorkspaceResizeSurface: NSViewRepresentable {
    @Binding var preferredWidth: Double
    let allowedRange: ClosedRange<CGFloat>
    let accessibilityLabel: String

    func makeNSView(context: Context) -> HunPanelResizeSurfaceView {
        let view = HunPanelResizeSurfaceView(axis: .horizontal)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.splitter)
        view.setAccessibilityLabel(accessibilityLabel)
        view.setAccessibilityHelp("Drag to resize, or use increment and decrement actions.")
        configure(view)
        return view
    }

    func updateNSView(_ view: HunPanelResizeSurfaceView, context: Context) {
        configure(view)
    }

    private func configure(_ view: HunPanelResizeSurfaceView) {
        view.configure(
            preferredValue: CGFloat(preferredWidth),
            allowedRange: allowedRange,
            onResize: { preferredWidth = Double($0) }
        )
    }
}

final class HunPanelResizeSurfaceView: NSView {
    private let axis: HunPanelResizeAxis
    private(set) var currentValue: CGFloat = 0
    private var allowedRange: ClosedRange<CGFloat> = 0 ... 0
    private var onResize: ((CGFloat) -> Void)?

    private var dragStartValue: CGFloat?
    private var dragStartCoordinate: CGFloat?

    init(axis: HunPanelResizeAxis) {
        self.axis = axis
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: axis.cursor)
    }

    func configure(
        preferredValue: CGFloat,
        allowedRange: ClosedRange<CGFloat>,
        onResize: @escaping (CGFloat) -> Void
    ) {
        self.allowedRange = allowedRange
        self.onResize = onResize
        currentValue = min(max(preferredValue, allowedRange.lowerBound), allowedRange.upperBound)
        updateAccessibilityValues()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartValue = currentValue
        dragStartCoordinate = axis.coordinate(in: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartValue, let dragStartCoordinate else { return }
        let translation = axis.coordinate(in: event.locationInWindow) - dragStartCoordinate
        resize(to: dragStartValue + translation)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartValue = nil
        dragStartCoordinate = nil
    }

    override func accessibilityPerformIncrement() -> Bool {
        resize(to: currentValue + HunPanelResizeMetrics.accessibilityAdjustment)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        resize(to: currentValue - HunPanelResizeMetrics.accessibilityAdjustment)
        return true
    }

    private func resize(to requestedValue: CGFloat) {
        let value = min(max(requestedValue, allowedRange.lowerBound), allowedRange.upperBound)
        guard value != currentValue else { return }
        currentValue = value
        onResize?(value)
        updateAccessibilityValues()
    }

    private func updateAccessibilityValues() {
        setAccessibilityOrientation(axis.accessibilityOrientation)
        setAccessibilityValue(currentValue)
        setAccessibilityMinValue(allowedRange.lowerBound)
        setAccessibilityMaxValue(allowedRange.upperBound)
        setAccessibilityValueDescription("\(Int(currentValue)) points")
    }
}
