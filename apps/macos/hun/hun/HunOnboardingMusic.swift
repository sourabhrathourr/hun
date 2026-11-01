import AVFoundation
import Foundation

// The welcome's music. If the app bundles "OnboardingMusic" (m4a or mp3), it
// plays that, looped, with fades. Otherwise Hun plays a small live score: a
// warm pad that moves to a new chord with each step, sparse bell notes from
// that chord, and two cues (a rising chime when the first project is set up,
// a swell on Run), all through a large reverb. Quiet by default, and muted
// for good once the person mutes it.

@MainActor
final class HunOnboardingMusic {
    static let mutedKey = "hun.onboarding.musicMuted"

    private(set) var isMuted: Bool = UserDefaults.standard.bool(forKey: HunOnboardingMusic.mutedKey)

    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var synth: HunScoreSynth?
    private var sourceNode: AVAudioSourceNode?
    private var track: AVAudioPlayer?
    private var bellTimer: Timer?
    private var started = false
    private let level: Float = 0.22

    /// Chords for each step, as MIDI notes (a soft D major / lydian colour).
    static let chords: [[Int]] = [
        [50, 57, 62, 64, 69],   // Dmaj9 (no 3rd low): D A D E A
        [47, 54, 57, 62, 66],   // Bm11 colour: B F# A D F#
        [43, 50, 54, 57, 61],   // Gmaj7#11: G D F# A C#
        [45, 52, 57, 59, 64],   // Asus2: A E A B E
        [50, 57, 61, 64, 66],   // Dmaj7: D A C# E F#
        [40, 47, 54, 55, 62],   // Em9 colour: E B F# G D
        [43, 50, 55, 59, 62],   // Gadd9 landing: G D G B D
    ]

    func start() {
        guard !started else { return }
        started = true
        if let url = Bundle.main.url(forResource: "OnboardingMusic", withExtension: "m4a")
            ?? Bundle.main.url(forResource: "OnboardingMusic", withExtension: "mp3"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            track = player
            player.numberOfLoops = -1
            player.volume = 0
            player.play()
            player.setVolume(isMuted ? 0 : 0.4, fadeDuration: 2.5)
            return
        }
        startScore()
    }

    /// Moves the score to the chord for `step`.
    func setStep(_ step: Int) {
        guard let synth else { return }
        let chord = Self.chords[min(max(step, 0), Self.chords.count - 1)]
        synth.setChord(chord.map(Self.frequency))
    }

    /// A rising three-note chime, for "your project is set up".
    func chime() {
        guard let synth, !isMuted else { return }
        let notes = [74, 78, 81, 86]
        for (index, note) in notes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.16) {
                synth.ring(Self.frequency(note), amplitude: 0.16)
            }
        }
    }

    /// A gentle swell, for Run.
    func swell() {
        synth?.swell()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        UserDefaults.standard.set(muted, forKey: Self.mutedKey)
        track?.setVolume(muted ? 0 : 0.4, fadeDuration: 0.6)
        synth?.setMaster(muted ? 0 : level, seconds: 0.6)
    }

    /// Fades out, then stops.
    func stop(fade: TimeInterval = 2) {
        bellTimer?.invalidate()
        bellTimer = nil
        track?.setVolume(0, fadeDuration: fade)
        synth?.setMaster(0, seconds: Float(fade))
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.2) { [weak self] in
            self?.track?.stop()
            self?.engine.stop()
        }
    }

    private func startScore() {
        let output = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = output.sampleRate > 0 ? output.sampleRate : 48_000
        let synth = HunScoreSynth(sampleRate: Float(sampleRate))
        self.synth = synth
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            synth.render(frames: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(bufferList))
            return noErr
        }
        sourceNode = node
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 42
        engine.attach(node)
        engine.attach(reverb)
        engine.connect(node, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            return
        }
        synth.setChord(Self.chords[0].map(Self.frequency))
        synth.setMaster(isMuted ? 0 : level, seconds: 3)
        scheduleBell()
    }

    /// A bell from the current chord, two octaves up, every few seconds.
    private func scheduleBell() {
        bellTimer?.invalidate()
        bellTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 2.6...5.2), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let synth = self.synth else { return }
                if let note = synth.currentChordFrequencies.randomElement() {
                    let octave: Float = Bool.random() ? 4 : 2
                    synth.ring(note * octave, amplitude: Float.random(in: 0.05...0.09))
                }
                self.scheduleBell()
            }
        }
    }

    static func frequency(_ midi: Int) -> Float {
        440 * pow(2, Float(midi - 69) / 12)
    }
}

/// The score's voices, rendered on the audio thread. Parameters are plain
/// floats written from the main thread; a stale value for one buffer is
/// inaudible, so there are no locks on the render path.
final class HunScoreSynth: @unchecked Sendable {
    private let sampleRate: Float
    private static let padVoices = 5

    // Two banks of pad voices; a chord change fades one out and the other in.
    private var padFrequency = [[Float]](repeating: [Float](repeating: 0, count: padVoices), count: 2)
    private var padPhase = [[Float]](repeating: [Float](repeating: 0, count: padVoices * 2), count: 2)
    private var bankLevel: [Float] = [0, 0]
    private var bankTarget: [Float] = [0, 0]
    private var activeBank = 0
    private(set) var currentChordFrequencies: [Float] = []

    private var bellFrequency = [Float](repeating: 0, count: 6)
    private var bellPhase = [Float](repeating: 0, count: 6)
    private var bellLevel = [Float](repeating: 0, count: 6)
    private var nextBell = 0

    private var master: Float = 0
    private var masterTarget: Float = 0
    private var masterStep: Float = 0
    private var brightness: Float = 0
    private var lfoPhase: Float = 0

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
    }

    func setChord(_ frequencies: [Float]) {
        currentChordFrequencies = frequencies
        let next = 1 - activeBank
        for voice in 0..<Self.padVoices {
            padFrequency[next][voice] = voice < frequencies.count ? frequencies[voice] : 0
        }
        bankTarget[activeBank] = 0
        bankTarget[next] = 1
        activeBank = next
    }

    func ring(_ frequency: Float, amplitude: Float) {
        let slot = nextBell
        nextBell = (nextBell + 1) % bellFrequency.count
        bellLevel[slot] = 0
        bellPhase[slot] = 0
        bellFrequency[slot] = frequency
        bellLevel[slot] = amplitude
    }

    func swell() {
        brightness = 1
    }

    func setMaster(_ level: Float, seconds: Float) {
        masterTarget = level
        masterStep = abs(level - master) / max(seconds * sampleRate, 1)
    }

    func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        let twoPi = Float.pi * 2
        // A chord crossfade takes about three seconds.
        let bankStep = 1 / (3 * sampleRate)
        let bellDecay = exp(-1 / (1.8 * sampleRate))
        let brightnessDecay = exp(-1 / (2.5 * sampleRate))
        let lfoStep = twoPi * 0.07 / sampleRate
        let left = buffers[0].mData?.assumingMemoryBound(to: Float.self)
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil

        for frame in 0..<frames {
            if master < masterTarget { master = min(masterTarget, master + masterStep) }
            else if master > masterTarget { master = max(masterTarget, master - masterStep) }

            lfoPhase += lfoStep
            if lfoPhase > twoPi { lfoPhase -= twoPi }
            let breath = 0.85 + 0.15 * sin(lfoPhase)

            var l: Float = 0
            var r: Float = 0
            for bank in 0..<2 {
                if bankLevel[bank] < bankTarget[bank] { bankLevel[bank] = min(bankTarget[bank], bankLevel[bank] + bankStep) }
                else if bankLevel[bank] > bankTarget[bank] { bankLevel[bank] = max(bankTarget[bank], bankLevel[bank] - bankStep) }
                let level = bankLevel[bank]
                if level < 0.0001 { continue }
                for voice in 0..<Self.padVoices {
                    let base = padFrequency[bank][voice]
                    if base == 0 { continue }
                    // Two slightly detuned oscillators per note, one each side.
                    for side in 0..<2 {
                        let index = voice * 2 + side
                        let detune: Float = side == 0 ? 0.9985 : 1.0015
                        var phase = padPhase[bank][index] + twoPi * base * detune / sampleRate
                        if phase > twoPi { phase -= twoPi }
                        padPhase[bank][index] = phase
                        let tone = sin(phase) + (0.18 + 0.12 * brightness) * sin(2 * phase) + 0.05 * sin(3 * phase)
                        let sample = tone * level * 0.11 * breath
                        if side == 0 { l += sample } else { r += sample }
                    }
                }
            }

            for slot in 0..<bellFrequency.count where bellLevel[slot] > 0.0005 {
                var phase = bellPhase[slot] + twoPi * bellFrequency[slot] / sampleRate
                if phase > twoPi { phase -= twoPi }
                bellPhase[slot] = phase
                let tone = sin(phase) + 0.25 * sin(2.76 * phase)
                let sample = tone * bellLevel[slot]
                bellLevel[slot] *= bellDecay
                // Bells sit a little left or right of centre.
                if slot % 2 == 0 { l += sample * 0.8; r += sample * 0.5 } else { l += sample * 0.5; r += sample * 0.8 }
            }

            brightness *= brightnessDecay
            let swellGain = 1 + 0.45 * brightness
            left?[frame] = l * master * swellGain
            right?[frame] = r * master * swellGain
        }
    }
}
