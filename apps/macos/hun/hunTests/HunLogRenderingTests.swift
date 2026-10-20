import AppKit
import SwiftUI
import Testing
@testable import hun

/// The log view appends new lines and trims old ones instead of redrawing.
/// After any sequence of appends it must hold exactly what a full redraw of
/// the same lines would.
@MainActor
struct HunLogRenderingTests {
    private func line(_ i: Int) -> HunLogLine {
        HunLogLine(HunDaemonLogLine(
            timestamp: "2026-10-20T17:00:00.000Z",
            service: ["api", "web", "worker"][i % 3],
            project: "app",
            text: i % 7 == 0 ? "request \(i) failed with error" : "request \(i) ok",
            isErr: false
        ))
    }

    private func host(_ feed: HunLogFeed, filter: HunLogFilter, showService: Bool) -> (NSHostingView<AnyView>, NSWindow) {
        let view = AnyView(LogsTailContainer(feed: feed, filter: filter, showService: showService).frame(width: 700, height: 400))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    private func textView(in view: NSView) -> LogsTextViewKit? {
        if let match = view as? LogsTextViewKit { return match }
        for subview in view.subviews {
            if let match = textView(in: subview) { return match }
        }
        return nil
    }

    @Test(arguments: [
        (HunLogFilter(service: nil, query: ""), true),
        (HunLogFilter(service: "web", query: ""), false),
        (HunLogFilter(service: nil, query: "error"), true),
    ])
    func incrementalRenderingMatchesAFullRedraw(filter: HunLogFilter, showService: Bool) throws {
        let feed = HunLogFeed()
        feed.replace(with: (0..<4_900).map(line))
        let subscription = feed.beginSubscription()
        let (live, liveWindow) = host(feed, filter: filter, showService: showService)
        defer { liveWindow.orderOut(nil) }

        // Push past the cap so old lines are trimmed from the top as well.
        var next = 4_900
        for size in [1, 50, 3, 400, 17, 250] {
            feed.append((next..<(next + size)).map(line), subscription: subscription)
            next += size
            live.rootView = AnyView(LogsTailContainer(feed: feed, filter: filter, showService: showService).frame(width: 700, height: 400))
            live.layoutSubtreeIfNeeded()
        }

        let (fresh, freshWindow) = host(feed, filter: filter, showService: showService)
        defer { freshWindow.orderOut(nil) }
        let incremental = try #require(textView(in: live))
        let redrawn = try #require(textView(in: fresh))

        #expect(incremental.string == redrawn.string)
        #expect(incremental.lastLineRange == redrawn.lastLineRange)
        let expectedLines = feed.lines.filter(filter.matches).count
        #expect(incremental.string.split(separator: "\n", omittingEmptySubsequences: false).count == expectedLines)
    }
}
