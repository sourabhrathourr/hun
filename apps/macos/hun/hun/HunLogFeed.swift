import Foundation
import Observation

/// The log lines in view: the selected project's, for the selected service or
/// for all of them. It lives apart from the project model so a stream of new
/// lines only redraws the log view.
@MainActor
@Observable
final class HunLogFeed {
    static let capacity = 5_000

    /// Oldest first, at most `capacity`. Each line's `id` is its sequence
    /// number, which only grows, so a view can append what it hasn't drawn.
    private(set) var lines: [HunLogLine] = []
    /// Bumped whenever lines change other than by appending (a reload, a
    /// clear), which tells a view to redraw from scratch.
    private(set) var generation = 0
    /// The sequence number of the newest line ever added, kept when old lines
    /// are trimmed, so "N new" counts stay right at the cap.
    private(set) var lastSeq = 0

    @ObservationIgnored private var subscription = 0

    /// Replaces the lines, for a new project, service or scope.
    func replace(with newLines: [HunLogLine]) {
        lines = stamped(Array(newLines.suffix(Self.capacity)))
        generation += 1
    }

    /// Adds a batch from the current subscription; batches from an older one
    /// are dropped.
    func append(_ batch: [HunLogLine], subscription: Int) {
        guard subscription == self.subscription, !batch.isEmpty else { return }
        lines.append(contentsOf: stamped(batch))
        if lines.count > Self.capacity {
            lines.removeFirst(lines.count - Self.capacity)
        }
    }

    /// Removes one service's lines, or all of them.
    func clear(service: String?) {
        if let service {
            lines.removeAll { $0.service == service }
        } else {
            lines.removeAll()
        }
        generation += 1
    }

    /// Starts a new subscription; only its batches are accepted from now on.
    func beginSubscription() -> Int {
        subscription += 1
        return subscription
    }

    private func stamped(_ batch: [HunLogLine]) -> [HunLogLine] {
        batch.map { line in
            var line = line
            lastSeq += 1
            line.id = lastSeq
            return line
        }
    }
}

/// Collects lines from a log stream's reader thread and hands them to the
/// main actor in batches, at most about 30 times a second however fast they
/// arrive. Classification and time formatting happen on the reader thread.
nonisolated final class HunLogBatcher: @unchecked Sendable {
    static let interval: Duration = .milliseconds(33)

    private let lock = NSLock()
    private var pending: [HunLogLine] = []
    private var flushScheduled = false
    private let deliver: @MainActor ([HunLogLine]) -> Void

    init(deliver: @escaping @MainActor ([HunLogLine]) -> Void) {
        self.deliver = deliver
    }

    func add(_ line: HunDaemonLogLine) {
        let converted = HunLogLine(line)
        lock.lock()
        pending.append(converted)
        let shouldSchedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        guard shouldSchedule else { return }
        Task { @MainActor [self] in
            try? await Task.sleep(for: Self.interval)
            deliver(takePending())
        }
    }

    private func takePending() -> [HunLogLine] {
        lock.lock()
        defer { lock.unlock() }
        let batch = pending
        pending = []
        flushScheduled = false
        return batch
    }
}
