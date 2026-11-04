import SwiftUI

/// The spinner for an action in progress. Once the action has run long
/// enough to be stuck (HunStore.forceStopDelay), the spinner becomes a thin
/// turning ring with a small square in its middle, the mark of progress you
/// can stop, at exactly the same size, so nothing around it moves. Whoever
/// shows it makes it clickable.
struct HunPendingSpinner: View {
    /// Whether force stop is on offer: the ring and square instead of the
    /// system spinner.
    var stoppable = false
    var hovering = false
    var size: CGFloat = 11
    var tint: Color = AppTheme.textSecondary

    var body: some View {
        ZStack {
            if stoppable {
                HunStopRing(size: size, tint: tint, emphasized: hovering)
                    .transition(.opacity)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .scaleEffect(size / 17.7)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.25), value: stoppable)
    }
}

private struct HunStopRing: View {
    let size: CGFloat
    let tint: Color
    let emphasized: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: 1.3)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(tint.opacity(emphasized ? 0.95 : 0.7), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    .rotationEffect(.degrees(turn * 360))
                RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                    .fill(tint.opacity(emphasized ? 1 : 0.8))
                    .frame(width: size * 0.34, height: size * 0.34)
            }
            .padding(0.65)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.15), value: emphasized)
    }
}
