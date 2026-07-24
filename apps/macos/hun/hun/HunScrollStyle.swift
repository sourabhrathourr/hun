import AppKit
import SwiftUI

enum HunScrollStyleMetrics {
    static let laneWidth: CGFloat = 10
    static let thumbWidth: CGFloat = 2
    static let minimumThumbLength: CGFloat = 28
    static let thumbOpacity: CGFloat = 0.26
    static let pressedThumbOpacity: CGFloat = 0.42
    static let nativeScrollerOpacity: CGFloat = 0.52
    static let revealDuration: TimeInterval = 0.14
    static let hideDelay: TimeInterval = 0.55
}

extension View {
    func hunScrollStyle() -> some View {
        modifier(HunScrollStyleModifier())
    }
}

private struct HunScrollStyleModifier: ViewModifier {
    @State private var pointerInside = false

    func body(content: Content) -> some View {
        content
            .background {
                HunScrollViewResolver(pointerInside: pointerInside)
                    .frame(width: 0, height: 0)
            }
            .onHover { pointerInside = $0 }
    }
}

private struct HunScrollViewResolver: NSViewRepresentable {
    let pointerInside: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> HunScrollProbeView {
        let view = HunScrollProbeView()
        view.onHierarchyChange = { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.invalidateResolution()
            coordinator.resolve(from: view)
        }
        return view
    }

    func updateNSView(_ view: HunScrollProbeView, context: Context) {
        context.coordinator.pointerInside = pointerInside
        context.coordinator.resolve(from: view)
    }

    @MainActor
    final class Coordinator {
        var pointerInside = false {
            didSet {
                visibilityController?.setPointerInside(pointerInside)
            }
        }

        private var visibilityController: HunScrollVisibilityController?
        private weak var resolvedScrollView: NSScrollView?
        private var resolutionScheduled = false

        func invalidateResolution() {
            resolutionScheduled = false
            resolvedScrollView = nil
            visibilityController = nil
        }

        func resolve(from probe: NSView) {
            if resolvedScrollView != nil {
                visibilityController?.bindToWindow()
                visibilityController?.setPointerInside(pointerInside)
                return
            }
            guard !resolutionScheduled else { return }
            resolutionScheduled = true
            DispatchQueue.main.async { [weak self, weak probe] in
                guard let self, let probe else { return }
                resolutionScheduled = false
                guard let scrollView = Self.enclosingScrollView(for: probe) else { return }
                guard resolvedScrollView !== scrollView else {
                    visibilityController?.setPointerInside(pointerInside)
                    return
                }

                let controller = HunScrollVisibilityController()
                controller.install(on: scrollView)
                controller.setPointerInside(pointerInside)
                visibilityController = controller
                resolvedScrollView = scrollView
            }
        }

        private static func enclosingScrollView(for view: NSView) -> NSScrollView? {
            var ancestor = view.superview
            while let current = ancestor {
                if let scrollView = current as? NSScrollView {
                    return scrollView
                }
                if let scrollView = nearestScrollView(to: view, within: current) {
                    return scrollView
                }
                ancestor = current.superview
            }
            return nil
        }

        private static func nearestScrollView(to probe: NSView, within container: NSView) -> NSScrollView? {
            guard probe.window != nil else { return nil }
            let probePoint = probe.convert(NSPoint(x: probe.bounds.midX, y: probe.bounds.midY), to: nil)
            let candidates = descendantScrollViews(in: container).filter { scrollView in
                guard scrollView.window === probe.window, !scrollView.isHidden else { return false }
                return scrollView.convert(scrollView.bounds, to: nil).insetBy(dx: -1, dy: -1).contains(probePoint)
            }
            return candidates.min { lhs, rhs in
                lhs.bounds.width * lhs.bounds.height < rhs.bounds.width * rhs.bounds.height
            }
        }

        private static func descendantScrollViews(in view: NSView) -> [NSScrollView] {
            var result: [NSScrollView] = []
            var pending = view.subviews
            while let candidate = pending.popLast() {
                if let scrollView = candidate as? NSScrollView {
                    result.append(scrollView)
                } else {
                    pending.append(contentsOf: candidate.subviews)
                }
            }
            return result
        }
    }
}

private final class HunScrollProbeView: NSView {
    var onHierarchyChange: (() -> Void)?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        onHierarchyChange?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onHierarchyChange?()
    }
}

@MainActor
final class HunScrollVisibilityController {
    private weak var scrollView: NSScrollView?
    private weak var hostView: NSView?
    private weak var focusView: NSView?
    private weak var scroller: NSScroller?
    private weak var observedWindow: NSWindow?
    private var pointerInside = false
    private var liveScrolling = false
    private var hideWorkItem: DispatchWorkItem?
    private var scrollObservers: [NSObjectProtocol] = []
    private var windowObserver: NSObjectProtocol?

    deinit {
        hideWorkItem?.cancel()
        scrollObservers.forEach(NotificationCenter.default.removeObserver)
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
    }

    func install(on scrollView: NSScrollView) {
        let scroller: HunOverlayScroller
        if let existing = scrollView.verticalScroller as? HunOverlayScroller {
            scroller = existing
        } else {
            scroller = HunOverlayScroller()
            scrollView.verticalScroller = scroller
        }

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay

        if self.scrollView !== scrollView {
            scrollObservers.forEach(NotificationCenter.default.removeObserver)
            scrollObservers.removeAll()
            self.scrollView = scrollView

            let center = NotificationCenter.default
            scrollObservers.append(
                center.addObserver(
                    forName: NSScrollView.willStartLiveScrollNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.liveScrolling = true
                        self?.refreshVisibility(animated: true)
                    }
                }
            )
            scrollObservers.append(
                center.addObserver(
                    forName: NSScrollView.didEndLiveScrollNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.liveScrolling = false
                        self?.scheduleHide()
                    }
                }
            )
        }

        install(scroller: scroller, hostView: scrollView, focusView: scrollView)
    }

    func install(scroller: NSScroller, hostView: NSView, focusView: NSView) {
        let targetChanged = self.scroller !== scroller || self.hostView !== hostView
        self.scroller = scroller
        self.hostView = hostView
        self.focusView = focusView
        if targetChanged {
            scroller.alphaValue = 0
        }
        bindToWindow()
        refreshVisibility(animated: false)
    }

    func bindToWindow() {
        let window = hostView?.window
        guard observedWindow !== window else { return }
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
            self.windowObserver = nil
        }
        observedWindow = window
        guard let window else { return }

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.bindToWindow()
                self.refreshVisibility(animated: true)
            }
        }
    }

    func setPointerInside(_ pointerInside: Bool) {
        bindToWindow()
        self.pointerInside = pointerInside
        if pointerInside {
            hideWorkItem?.cancel()
            refreshVisibility(animated: true)
        } else {
            scheduleHide()
        }
    }

    func refresh() {
        bindToWindow()
        refreshVisibility(animated: true)
    }

    private var containsFirstResponder: Bool {
        guard let focusView,
              let responder = focusView.window?.firstResponder as? NSView
        else {
            return false
        }
        return responder === focusView || responder.isDescendant(of: focusView)
    }

    private func refreshVisibility(animated: Bool) {
        let shouldReveal = pointerInside || liveScrolling || containsFirstResponder
        setScrollerRevealed(shouldReveal, animated: animated)
    }

    private func setScrollerRevealed(_ revealed: Bool, animated: Bool) {
        guard let scroller else { return }
        if let scroller = scroller as? HunOverlayScroller {
            scroller.setRevealed(revealed, animated: animated)
            return
        }

        let targetAlpha: CGFloat = revealed ? HunScrollStyleMetrics.nativeScrollerOpacity : 0
        guard scroller.alphaValue != targetAlpha else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = HunScrollStyleMetrics.revealDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scroller.animator().alphaValue = targetAlpha
            }
        } else {
            scroller.alphaValue = targetAlpha
        }
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshVisibility(animated: true)
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + HunScrollStyleMetrics.hideDelay,
            execute: workItem
        )
    }
}

final class HunStyledScrollView: NSScrollView {
    private let visibilityController = HunScrollVisibilityController()
    private var pointerTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        visibilityController.install(on: self)
    }

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        visibilityController.setPointerInside(true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        visibilityController.setPointerInside(false)
        super.mouseExited(with: event)
    }

    private func configure() {
        scrollerStyle = .overlay
        autohidesScrollers = false
        visibilityController.install(on: self)
    }
}

final class HunOverlayScroller: NSScroller {
    private var revealed = false

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        HunScrollStyleMetrics.laneWidth
    }

    func setRevealed(_ revealed: Bool, animated: Bool) {
        guard self.revealed != revealed else { return }
        self.revealed = revealed
        let targetAlpha: CGFloat = revealed ? 1 : 0

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = HunScrollStyleMetrics.revealDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = targetAlpha
            }
        } else {
            alphaValue = targetAlpha
        }
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // The content itself is the track. An extra rail adds visual noise.
    }

    override func drawKnob() {
        guard knobProportion < 0.999 else { return }
        let sourceRect = rect(for: .knob)
        let length = min(
            sourceRect.height,
            max(HunScrollStyleMetrics.minimumThumbLength, sourceRect.height - 6)
        )
        let thumbRect = NSRect(
            x: sourceRect.midX - HunScrollStyleMetrics.thumbWidth / 2,
            y: sourceRect.midY - length / 2,
            width: HunScrollStyleMetrics.thumbWidth,
            height: length
        )
        let thumb = NSBezierPath(
            roundedRect: thumbRect,
            xRadius: HunScrollStyleMetrics.thumbWidth / 2,
            yRadius: HunScrollStyleMetrics.thumbWidth / 2
        )
        let pressed = (NSEvent.pressedMouseButtons & 0x1) != 0
        NSColor.labelColor.withAlphaComponent(
            pressed
                ? HunScrollStyleMetrics.pressedThumbOpacity
                : HunScrollStyleMetrics.thumbOpacity
        ).setFill()
        thumb.fill()
    }
}
