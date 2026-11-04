import AppKit
import AVFoundation
import CryptoKit
import SwiftUI

// Music from the menu bar. It only plays when you press play (and can be
// turned off in Settings). Ten pieces, played in a shuffled order that
// doesn't repeat until all have played; each crossfades into the next near
// its end. Doorway (the welcome's music) ships in the app; the other nine
// download the first time music plays, into ~/.hun/music, so the app stays
// small and nobody downloads music they never play. Next and previous only
// move between pieces already on this Mac, so they never wait on the
// network. While it plays, it takes the middle of the sky as a record drawn
// in the sky's own ink.

@MainActor
@Observable
final class HunMenuMusic {
    static let shared = HunMenuMusic()
    static let enabledKey = "hun.menu.music.enabled"

    struct Piece {
        let title: String
        /// The file's name, without its extension.
        let file: String
        /// For a downloaded piece, its SHA-256; nil for one in the app.
        let sha256: String?

        var isBundled: Bool { sha256 == nil }
    }

    static let pieces = [
        Piece(title: "Doorway", file: "OnboardingMusic", sha256: nil),
        Piece(title: "Long Day", file: "MenuMusic-LongDay", sha256: "7d05f0d28f601db005c880517b7c4839b031acf890e7f721594587e8e4bf0540"),
        Piece(title: "Hillside", file: "MenuMusic-Hillside", sha256: "f810cbf9f417e2c25181dabc825ef517902f2d24a6874c8a0f2f8ec0510376d7"),
        Piece(title: "Harbour", file: "MenuMusic-Harbour", sha256: "a65a971905f1b5665157b0f54caba96881ba0c37ed2ef1a3f344216d6c167b47"),
        Piece(title: "First Snow", file: "MenuMusic-FirstSnow", sha256: "c9069f1f5891c512afd983f964069a194d7596a068615ffa577dbf5151544018"),
        Piece(title: "After Rain", file: "MenuMusic-AfterRain", sha256: "04023979ffb3aebaee0dc4931cde764c9e52ab6b54963964677ad21d44c5e8ac"),
        Piece(title: "Sunlit", file: "MenuMusic-Sunlit", sha256: "69b9f193ed4ce2fcd3d66fb4de7750c57920f3c62dc67d3605847294a647e860"),
        Piece(title: "Quiet Sea", file: "MenuMusic-QuietSea", sha256: "3a299458e7624f377329536b1ff4500ca985217d006acfc5bdaba9377daac868"),
        Piece(title: "Meadow", file: "MenuMusic-Meadow", sha256: "4351b1f7ac0f797ad81c3db57a60fc3d1bc50c9cc6bf6718984654dca98476d5"),
        Piece(title: "Still Water", file: "MenuMusic-StillWater", sha256: "4f6a22eb16f06b7dc11d17f3800b41347ff2a56320d7a186952cab9dd382056d"),
    ]

    /// Where the downloaded pieces come from: one GitHub release, beside the
    /// app's own downloads. That release must never be deleted, renamed or
    /// changed; new music goes in a new release (see docs/menu-music.md).
    /// A debug build can point elsewhere for testing.
    static var downloadBase: URL {
        #if DEBUG
        if let custom = UserDefaults.standard.string(forKey: "hun.menu.music.baseURL"), let url = URL(string: custom) {
            return url
        }
        #endif
        return URL(string: "https://github.com/sourabhrathourr/hun/releases/download/menu-music-1/")!
    }

    /// Where downloaded pieces live: ~/.hun/music (~/.hun-dev/music in debug).
    static var directory: URL { HunPaths.homeURL.appendingPathComponent("music", isDirectory: true) }

    /// How long one piece takes to hand over to the next.
    static let crossfade: TimeInterval = 3

    /// How long the spin takes to come up to speed, and to wind down.
    static let spinUp: Double = 0.8
    static let spinDown: Double = 1.6
    /// How long a note takes to rise and fade; motion runs this long after a pause.
    static let noteLife: Double = 3.2

    private(set) var isPlaying = false
    /// The pieces in this round's shuffled order, and where we are in it.
    private var order: [Int] = Array(HunMenuMusic.pieces.indices).shuffled()
    private var position = 0
    /// The pieces as they've played, oldest first, and where we are along
    /// it: back and forward retrace it before the shuffle carries on.
    private var trail: [Int] = []
    private var at = 0
    /// The piece playing now (or next, while paused).
    private var current: Int { trail[at] }
    /// When playback last started or stopped, and how far things had turned.
    private(set) var changedAt = Date.distantPast
    private(set) var turnsAtChange: Double = 0
    /// When the current (or last) stretch of playing began.
    private(set) var playStartedAt = Date.distantPast
    /// Bumps once everything has come to rest after a pause.
    private(set) var settled = 0

    private var player: AVAudioPlayer?
    private var pauseTask: Task<Void, Never>?
    /// Watches for the end of a piece, to move on to the next.
    private var endTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var isLocked = false
    private var resumeOnUnlock = false
    private var observers: [NSObjectProtocol] = []
    private let volume: Float = 0.35
    private var downloadTask: Task<Void, Never>?
    private var downloadAttempts = 0

    var piece: Piece { Self.pieces[current] }

    private init() {
        trail = [order[position]]
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let suspend: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend() }
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: suspend))
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: suspend))
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLocked = true
                self?.suspend()
            }
        })
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLocked = false
                self?.resumeIfSuspended()
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isLocked else { return }
                self.resumeIfSuspended()
            }
        })
    }

    // MARK: Playback

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !isPlaying else { return }
        pauseTask?.cancel()
        // Every press of play tries again, so a failed download never sticks.
        downloadAttempts = 0
        downloadMissing()
        if !isAvailable(current), let next = nextInOrder() { trail[at] = next }
        if player == nil { player = makePlayer() }
        guard let player else { return }
        mark(playing: true)
        if !player.isPlaying {
            player.volume = 0
            player.play()
        }
        player.setVolume(volume, fadeDuration: 2)
        watchForEnd()
    }

    func pause(fade: TimeInterval = 1.2) {
        guard isPlaying else { return }
        mark(playing: false)
        endTask?.cancel()
        let fading = player
        fading?.setVolume(0, fadeDuration: fade)
        pauseTask?.cancel()
        pauseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(fade + 0.05))
            guard !Task.isCancelled, let self, !self.isPlaying else { return }
            fading?.pause()
        }
    }

    /// Crossfades to the next piece, and plays.
    func skip() {
        while at + 1 < trail.count, !isAvailable(trail[at + 1]) { trail.remove(at: at + 1) }
        if at + 1 < trail.count {
            at += 1
        } else if let next = nextInOrder() {
            trail.append(next)
            at += 1
            if trail.count > 50 {
                trail.removeFirst()
                at -= 1
            }
        }
        crossfadeToCurrent()
    }

    /// Crossfades back to the piece before, and plays. From the first piece
    /// it goes round: to the last one still to come.
    func previous() {
        while at > 0, !isAvailable(trail[at - 1]) {
            trail.remove(at: at - 1)
            at -= 1
        }
        if at > 0 {
            at -= 1
        } else if let before = pieceBefore() {
            trail.insert(before, at: 0)
            if trail.count > 50 { trail.removeLast() }
        }
        crossfadeToCurrent()
    }

    /// What comes before the first piece, going round: the last piece still
    /// to come in this shuffle, taken out of it so it won't play twice; once
    /// all have played, any other piece. Nil with only one piece here (then
    /// that piece starts over).
    private func pieceBefore() -> Int? {
        if let last = order.indices.last(where: { $0 > position && isAvailable(order[$0]) }) {
            return order.remove(at: last)
        }
        return Self.pieces.indices.filter { $0 != current && isAvailable($0) }.randomElement()
    }

    private func crossfadeToCurrent() {
        let old = player
        old?.setVolume(0, fadeDuration: Self.crossfade)
        Task {
            try? await Task.sleep(for: .seconds(Self.crossfade + 0.1))
            old?.stop()
        }
        player = makePlayer()
        if isPlaying {
            player?.volume = 0
            player?.play()
            player?.setVolume(volume, fadeDuration: Self.crossfade)
            watchForEnd()
        } else {
            play()
        }
    }

    /// The next piece on this Mac in the shuffled order; a new order once
    /// all have played, never starting with the piece that just ended. With
    /// only Doorway here so far, that's Doorway again.
    private func nextInOrder() -> Int? {
        for _ in 0..<(Self.pieces.count * 2) {
            position += 1
            if position >= order.count {
                let last = order.last
                var next = Array(Self.pieces.indices).shuffled()
                if next.count > 1, next.first == last { next.swapAt(0, next.count - 1) }
                order = next
                position = 0
            }
            if isAvailable(order[position]) { return order[position] }
        }
        return nil
    }

    // MARK: Downloads

    private func isAvailable(_ index: Int) -> Bool {
        url(for: Self.pieces[index]) != nil
    }

    private func url(for piece: Piece) -> URL? {
        if piece.isBundled {
            return Bundle.main.url(forResource: piece.file, withExtension: "m4a")
                ?? Bundle.main.url(forResource: piece.file, withExtension: "mp3")
        }
        let file = Self.directory.appendingPathComponent("\(piece.file).m4a")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Fetches the pieces not on this Mac yet, one at a time, in the
    /// background; each is checked against its SHA-256 before it's kept. A
    /// failure is retried a minute later, up to three times, and again the
    /// next time someone presses play. Only one download runs at a time.
    private func downloadMissing() {
        guard downloadTask == nil else { return }
        let missing = Self.pieces.filter { !$0.isBundled && url(for: $0) == nil }
        guard !missing.isEmpty, downloadAttempts < 3 else { return }
        downloadAttempts += 1
        downloadTask = Task { [weak self] in
            var failed = false
            for piece in missing {
                if Task.isCancelled { return }
                if await !Self.download(piece) { failed = true }
            }
            if failed {
                try? await Task.sleep(for: .seconds(60))
            }
            guard let self else { return }
            self.downloadTask = nil
            if failed { self.downloadMissing() }
        }
    }

    /// Downloads one piece; true once it's on disk and checked.
    private nonisolated static func download(_ piece: Piece) async -> Bool {
        guard let expected = piece.sha256 else { return true }
        let name = "\(piece.file).m4a"
        let source = await downloadBase.appendingPathComponent(name)
        let destination = await directory.appendingPathComponent(name)
        do {
            let (temporary, response) = try await URLSession.shared.download(from: source)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let data = try Data(contentsOf: temporary)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == expected else { return false }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Written whole beside it, then moved in, so a half file never shows.
            let partial = destination.appendingPathExtension("partial")
            try data.write(to: partial)
            _ = try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partial, to: destination)
            return true
        } catch {
            return false
        }
    }

    /// Moves on to the next piece a crossfade before this one ends.
    private func watchForEnd() {
        endTask?.cancel()
        endTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.isPlaying, let player = self.player else { return }
                if player.duration - player.currentTime <= Self.crossfade {
                    self.skip()
                    return
                }
            }
        }
    }

    /// Stops for good (the setting was turned off).
    func stop() {
        pause(fade: 0.8)
        resumeOnUnlock = false
    }

    private func suspend() {
        guard isPlaying else { return }
        resumeOnUnlock = true
        pause(fade: 0.4)
    }

    private func resumeIfSuspended() {
        guard resumeOnUnlock else { return }
        resumeOnUnlock = false
        play()
    }

    private func makePlayer() -> AVAudioPlayer? {
        guard let url = url(for: piece), let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = 0
        player.prepareToPlay()
        return player
    }

    // MARK: Motion

    private func mark(playing: Bool) {
        let now = Date()
        turnsAtChange = turns(at: now)
        changedAt = now
        if playing { playStartedAt = now }
        isPlaying = playing
        settleTask?.cancel()
        if !playing {
            settleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(Self.spinDown, Self.noteLife) + 0.1))
                guard !Task.isCancelled else { return }
                self?.settled += 1
            }
        }
    }

    /// Whether anything is still moving: playing, or winding down after a pause.
    var isAnimating: Bool {
        _ = settled
        return isPlaying || Date().timeIntervalSince(changedAt) < max(Self.spinDown, Self.noteLife)
    }

    /// How many turns at one turn a second, easing up on play and down on pause.
    func turns(at date: Date) -> Double {
        let dt = max(date.timeIntervalSince(changedAt), 0)
        if isPlaying {
            let up = Self.spinUp
            return turnsAtChange + (dt < up ? dt * dt / (2 * up) : up / 2 + (dt - up))
        }
        let down = Self.spinDown
        return turnsAtChange + (dt < down ? dt - dt * dt / (2 * down) : down / 2)
    }

    /// 0 at rest, 1 in full swing, eased the same way as the spin.
    func level(at date: Date) -> Double {
        let dt = max(date.timeIntervalSince(changedAt), 0)
        return isPlaying ? min(dt / Self.spinUp, 1) : max(1 - dt / Self.spinDown, 0)
    }

    /// Notes are let go every `period` seconds while music plays; this says
    /// whether the note let go at `time` was.
    func emitted(at time: Date) -> Bool {
        isPlaying ? time >= playStartedAt : time >= playStartedAt && time < changedAt
    }
}

// MARK: - Preview

/// Debug builds set this (sh.hun.debug.menuPreview) to show the sky in a mode,
/// or with a stand-in project name, without touching the daemon.
@MainActor
@Observable
final class HunMenuPreview {
    static let shared = HunMenuPreview()
    var mode: HunMode?
    var focusName: String?
    /// Show the sky as if this many projects were running (0: nothing).
    var count: Int?

    func running(_ running: [HunProject], all: [HunProject]) -> [HunProject] {
        guard let count, let any = all.first else { return running }
        return Array(repeating: any, count: count)
    }
}

// MARK: - Shared pieces

/// Ink for things drawn straight on the vista, matching the sky's words.
func vistaInk(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? .white : Color(red: 0x2B / 255, green: 0x26 / 255, blue: 0x22 / 255)
}

/// Three bars that breathe while music plays and lie low when it doesn't.
struct HunMusicBars: View {
    var color: Color = AppTheme.textSecondary
    var height: CGFloat = 11

    private func barHeight(level: Double, swing: Double) -> CGFloat {
        let lift: Double = level * (0.35 + 0.65 * swing)
        return 3 + (height - 3) * CGFloat(lift)
    }
    private let music = HunMenuMusic.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !music.isAnimating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let level = music.level(at: context.date)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { bar in
                    let speed = [2.3, 3.1, 2.7][bar]
                    let phase = [0.0, 1.9, 4.1][bar]
                    let swing = 0.5 + 0.5 * sin(t * speed + phase)
                    Capsule()
                        .fill(color)
                        .frame(width: 2.2, height: barHeight(level: level, swing: swing))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
    }
}

/// Notes that float up from where the music plays, sway a little, and fade.
struct HunMusicNotes: View {
    var period: Double = 0.95
    var rise: CGFloat = 64
    @Environment(\.colorScheme) private var colorScheme
    private let music = HunMenuMusic.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !music.isAnimating)) { context in
            Canvas { canvas, size in
                let now = context.date.timeIntervalSinceReferenceDate
                let life = HunMenuMusic.noteLife
                let newest = Int(floor(now / period))
                let oldest = Int(floor((now - life) / period))
                guard newest >= oldest else { return }
                for k in oldest...newest {
                    let born = Double(k) * period
                    let age = now - born
                    guard age >= 0, age <= life, music.emitted(at: Date(timeIntervalSinceReferenceDate: born)) else { continue }
                    let seed = Double((k &* 7919) % 97) / 97
                    let p = age / life
                    // Typed step by step: one long mixed expression is too
                    // slow for the compiler on CI.
                    let drift: Double = (seed - 0.5) * 22
                    let sway: Double = sin(age * 1.7 + seed * 6) * 5
                    let x: CGFloat = size.width / 2 + CGFloat(drift + sway)
                    let risen: Double = 1 - pow(1 - p, 1.6)
                    let y: CGFloat = size.height - 4 - rise * CGFloat(risen)
                    let fadeIn = min(age / 0.35, 1)
                    let fadeOut = min((life - age) / 1.3, 1)
                    var text = canvas.resolve(
                        Text(seed > 0.5 ? "♪" : "♫")
                            .font(.system(size: 10 + CGFloat(seed) * 3, weight: .semibold))
                            .foregroundStyle(vistaInk(colorScheme).opacity(colorScheme == .dark ? 0.85 : 0.6))
                    )
                    text.shading = .color(vistaInk(colorScheme).opacity(colorScheme == .dark ? 0.85 : 0.6))
                    var layer = canvas
                    layer.opacity = fadeIn * fadeOut
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .degrees(sin(age * 2.1 + seed * 5) * 12))
                    layer.scaleBy(x: 0.8 + 0.3 * p, y: 0.8 + 0.3 * p)
                    layer.draw(text, at: .zero)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - In the sky

/// The sky's corner switch: a note to start the music, breathing bars to
/// pause it.
struct HunSkyMusicToggle: View {
    @Environment(\.colorScheme) private var colorScheme
    private let music = HunMenuMusic.shared
    @State private var hovering = false

    var body: some View {
        let ink = vistaInk(colorScheme)
        Button(action: music.toggle) {
            ZStack {
                if music.isPlaying {
                    HunMusicBars(color: ink.opacity(0.8), height: 11)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ink.opacity(hovering ? 0.9 : 0.6))
                }
            }
            .frame(width: 26, height: 26)
            .background(Circle().fill(ink.opacity(hovering ? 0.12 : 0)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(.easeOut(duration: 0.15)) { hovering = over } }
        .help(music.isPlaying ? "Pause music" : "Play music")
        .accessibilityLabel(music.isPlaying ? "Pause music" : "Play music")
    }
}

/// What's playing, in the middle of the sky. Click it to pause; hover for
/// the piece before and the next, on either side of the record.
struct HunSkyMusic: View {
    @Environment(\.colorScheme) private var colorScheme
    private let music = HunMenuMusic.shared
    @State private var hovering = false

    private var ink: Color { vistaInk(colorScheme) }

    var body: some View {
        VStack(spacing: 7) {
            // Same width each side, so the record stays in the middle and
            // the buttons never move, whatever the title.
            HStack(spacing: 0) {
                HunSkyStep(forward: false, label: "Previous piece", ink: ink, shown: hovering, action: music.previous)
                HunSkyRecord(ink: ink)
                    .overlay(alignment: .topTrailing) { notes }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: music.toggle)
                HunSkyStep(forward: true, label: "Next piece", ink: ink, shown: hovering, action: music.skip)
            }
            Text(music.piece.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink.opacity(0.78))
        }
        // The sky's words carry the same soft glow.
        .shadow(color: (colorScheme == .dark ? Color.black : Color.white).opacity(0.35), radius: 14)
        .onHover { over in withAnimation(.easeOut(duration: 0.2)) { hovering = over } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing: \(music.piece.title)")
    }

    private var notes: some View {
        HunMusicNotes(rise: 46)
            .frame(width: 44, height: 64)
            .offset(x: 30, y: -54)
    }

}

/// A quiet step back or forward beside the record: there only while the
/// pointer is over the music, faint until it's over the button itself.
private struct HunSkyStep: View {
    let forward: Bool
    let label: String
    let ink: Color
    let shown: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HunSoftTriangle()
                .fill(ink.opacity(hovering ? 0.8 : 0.4))
                .frame(width: 8, height: 10)
                // A triangle's weight sits on its flat side: nudged toward
                // its point (to its centroid), it looks centred in the circle.
                .offset(x: 8 / 6)
                .scaleEffect(x: forward ? 1 : -1)
                .frame(width: 22, height: 22)
                .background(Circle().fill(ink.opacity(hovering ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Level with the middle of the record, not of its frame.
        .offset(y: 1)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .onHover { over in withAnimation(.easeOut(duration: 0.15)) { hovering = over } }
        .accessibilityLabel(label)
    }
}

/// A small triangle pointing right, its corners softly rounded.
private struct HunSoftTriangle: Shape {
    var radius: CGFloat = 1.6

    func path(in rect: CGRect) -> Path {
        let a = CGPoint(x: rect.minX, y: rect.minY)
        let b = CGPoint(x: rect.maxX, y: rect.midY)
        let c = CGPoint(x: rect.minX, y: rect.maxY)
        var path = Path()
        path.move(to: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2))
        path.addArc(tangent1End: a, tangent2End: b, radius: radius)
        path.addArc(tangent1End: b, tangent2End: c, radius: radius)
        path.addArc(tangent1End: c, tangent2End: a, radius: radius)
        path.closeSubpath()
        return path
    }
}

/// A record in ink line: grooves, a label with its hole, and a tonearm that
/// swings onto the record while it plays and off when it stops.
private struct HunSkyRecord: View {
    let ink: Color
    private let music = HunMenuMusic.shared
    private let d: CGFloat = 70

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !music.isAnimating)) { context in
            let turn = music.turns(at: context.date) * 0.55 * 360
            let level = music.level(at: context.date)
            ZStack(alignment: .topLeading) {
                disc
                    .rotationEffect(.degrees(turn))
                    .frame(width: d, height: d)
                    .offset(y: 4)
                arm
                    .rotationEffect(.degrees(4 + 24 * level), anchor: UnitPoint(x: (d + 12) / (d + 26), y: 8 / (d + 6)))
            }
            .frame(width: d + 26, height: d + 6, alignment: .topLeading)
            // As much room on the left as the arm takes on the right, so the
            // record itself sits in the middle, over its title.
            .padding(.leading, 26)
        }
    }

    private var disc: some View {
        ZStack {
            Circle().fill(ink.opacity(0.1))
            ForEach(1..<5, id: \.self) { groove in
                Circle()
                    .strokeBorder(ink.opacity(0.2), lineWidth: 0.6)
                    .padding(CGFloat(groove) * 4.5)
            }
            Circle().strokeBorder(ink.opacity(0.75), lineWidth: 1.4)
            // Light on the grooves, so the turn shows.
            Circle().trim(from: 0.04, to: 0.15)
                .stroke(ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .padding(7)
            Circle().trim(from: 0.55, to: 0.61)
                .stroke(ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .padding(13)
            // The label, with a mark and the hole cut out of it.
            ZStack {
                Circle().fill(ink.opacity(0.7))
                Circle().trim(from: 0, to: 0.22)
                    .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 15, height: 15)
                    .blendMode(.destinationOut)
                Circle().frame(width: 4, height: 4).blendMode(.destinationOut)
            }
            .frame(width: 24, height: 24)
            .compositingGroup()
        }
    }

    private var arm: some View {
        let pivot = CGPoint(x: d + 12, y: 8)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: pivot)
                path.addLine(to: CGPoint(x: pivot.x + 2, y: pivot.y + 40))
                path.addLine(to: CGPoint(x: pivot.x - 3, y: pivot.y + 54))
            }
            .stroke(ink.opacity(0.75), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            RoundedRectangle(cornerRadius: 1.5)
                .fill(ink.opacity(0.75))
                .frame(width: 5, height: 9)
                .rotationEffect(.degrees(20))
                .position(x: pivot.x - 4, y: pivot.y + 56)
            Circle()
                .fill(ink.opacity(0.15))
                .overlay(Circle().strokeBorder(ink.opacity(0.75), lineWidth: 1.4))
                .frame(width: 10, height: 10)
                .position(pivot)
        }
        .frame(width: d + 26, height: d + 6, alignment: .topLeading)
    }
}
