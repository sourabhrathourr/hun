import AppKit
import SwiftUI
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// The welcome a person sees the first time they open Hun: what it is, their
// license, their coding agent, their first project (set up by that agent,
// live), running it, and where Hun lives in the menu bar. Shown once, to
// everyone, with "Skip intro" on every screen after the license.

enum HunOnboarding {
    static let completedKey = "hun.onboarding.completed"

    #if DEBUG
    /// Debug builds: the welcome plays as for a brand-new user (no license,
    /// no projects), from Settings › About.
    @MainActor static var rehearsingAsNewUser = false

    /// Starts a rehearsal of the welcome: as a new user (no license, no
    /// projects) or as a beta tester whose beta has ended (projects kept).
    @MainActor static func rehearse(asBeta: Bool, license: HunLicenseManager) {
        rehearsingAsNewUser = !asBeta
        license.startRehearsal(asBeta: asBeta)
        UserDefaults.standard.set(false, forKey: completedKey)
    }
    #endif

    /// Which copy of the app finished the welcome: its file number on disk
    /// and its version, as "inode:version".
    private static let completedInstallKey = "hun.onboarding.install"

    /// Preferences outlive the app, so deleting Hun and installing it again
    /// would skip the welcome. A copy of the same version on a new file is a
    /// reinstall, so the welcome shows again; a new version is an update
    /// (Sparkle or Homebrew), so it doesn't. Call before any view reads
    /// `completedKey`.
    static func checkForReinstall() {
        #if !DEBUG
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: completedKey),
              let saved = defaults.string(forKey: completedInstallKey),
              let current = installIdentity()
        else { return }
        switch installChange(from: saved, to: current) {
        case .reinstalled:
            defaults.set(false, forKey: completedKey)
            defaults.removeObject(forKey: completedInstallKey)
        case .updated:
            defaults.set(current, forKey: completedInstallKey)
        case .same:
            break
        }
        #endif
    }

    enum InstallChange: Equatable { case same, updated, reinstalled }

    /// Compares two "inode:version" identities of the app.
    static func installChange(from saved: String, to current: String) -> InstallChange {
        guard saved != current else { return .same }
        func version(_ identity: String) -> Substring? {
            identity.split(separator: ":", maxSplits: 1).dropFirst().first
        }
        return version(saved) == version(current) ? .reinstalled : .updated
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
        if let identity = installIdentity() {
            UserDefaults.standard.set(identity, forKey: completedInstallKey)
        }
    }

    private static func installIdentity() -> String? {
        guard let number = (try? FileManager.default.attributesOfItem(atPath: Bundle.main.bundlePath))?[.systemFileNumber] as? NSNumber
        else { return nil }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "\(number.uint64Value):\(version)"
    }

    /// Decodes every step's photo (both appearances) in the background, so a
    /// step never waits on its photo while something else is busy.
    @MainActor
    static func preloadPhotos() {
        let names = Step.allCases.map(\.background)
        Task.detached(priority: .utility) {
            for name in names {
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                        guard let image = NSImage(named: name) else { return }
                        var rect = CGRect(origin: .zero, size: image.size)
                        _ = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)?.dataProvider?.data
                    }
                }
            }
        }
    }

    /// In light mode the welcome is always Clay: its photos are warm paper
    /// and sunlight. Not saved, so the person's own palette comes back when
    /// the welcome ends. (Dark mode is the same in both palettes.)
    @MainActor
    static func holdClay() {
        guard HunPalette.current != .clay else { return }
        HunPalette.current = .clay
        hunApp.redrawColors()
    }

    @MainActor
    static func releaseClay() {
        let saved = UserDefaults.standard.string(forKey: HunPalette.key).flatMap(HunPalette.init) ?? .clay
        guard HunPalette.current != saved else { return }
        HunPalette.current = saved
        hunApp.redrawColors()
    }

    enum Step: Int, CaseIterable {
        case welcome, license, agent, project, run, modes, menuBar

        var background: String {
            switch self {
            case .welcome: return "OnboardingWelcome"
            case .license: return "OnboardingLicense"
            case .agent: return "OnboardingAgent"
            case .project: return "OnboardingProject"
            case .run: return "OnboardingRun"
            case .modes: return "OnboardingModes"
            case .menuBar: return "OnboardingMenuBar"
            }
        }
    }
}

struct HunOnboardingView: View {
    @Environment(HunStore.self) private var store
    @Environment(HunLicenseManager.self) private var license
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let onFinish: () -> Void

    @State private var step: HunOnboarding.Step = .welcome
    @State private var music = HunOnboardingMusic()
    @State private var muted = UserDefaults.standard.bool(forKey: HunOnboardingMusic.mutedKey)
    /// The project the person added or picked, for "Run it".
    @State private var projectPath: String?
    @State private var drift = false
    /// Moving back a step slides the other way.
    @State private var goingBack = false
    /// Debug builds: a jump straight to a step stays there, licensed or not.
    @State private var debugHolds = false

    var body: some View {
        Group {
            if step == .welcome {
                HunWelcomeHero(onContinue: advance)
                    .transition(.opacity)
            } else {
                card
                    .transition(.opacity)
            }
        }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The photo is a background, so its shape never moves the card.
            .background { background }
            .overlay(alignment: .topTrailing) { topControls }
            .overlay(alignment: .topLeading) {
                if step != .welcome {
                    backButton
                        // Clear of the window's traffic lights.
                        .padding(.leading, 80)
                        .padding(.top, 13)
                        .transition(.opacity)
                }
            }
        .background(WindowChromeConfigurator())
        .onAppear {
            HunOnboarding.holdClay()
            HunOnboarding.preloadPhotos()
            // Once the window is on screen, blur everything behind it.
            DispatchQueue.main.async { HunOnboardingBackdrop.show(step: step) }
            music.start()
            if !reduceMotion {
                withAnimation(.linear(duration: 40).repeatForever(autoreverses: true)) { drift = true }
            }
        }
        .onChange(of: step) { _, next in
            music.setStep(next.rawValue)
            HunOnboardingBackdrop.update(step: next)
            if next == .license && license.isLicensed && !debugHolds { advance() }
        }
        #if DEBUG
        .onReceive(DistributedNotificationCenter.default().publisher(for: .init("sh.hun.debug.onboardingStep"))) { note in
            if let raw = (note.object as? String).flatMap(Int.init), let target = HunOnboarding.Step(rawValue: raw) {
                debugHolds = true
                withAnimation(.easeInOut(duration: 0.45)) { step = target }
            }
        }
        #endif
    }

    // MARK: Frame

    private var background: some View {
        ZStack {
            AppTheme.appBackground
            Image(step.background)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .scaleEffect(drift ? 1.06 : 1.0)
                .id(step)
                .transition(.opacity.animation(.easeInOut(duration: 0.6)))
            // A soft wash so the card reads on any photo.
            AppTheme.appBackground.opacity(0.18)
        }
        .ignoresSafeArea()
        .clipped()
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch step {
                case .welcome: EmptyView()
                case .license: HunLicenseStep(onContinue: advance)
                case .agent: HunAgentStep(onContinue: advance)
                case .project: HunProjectStep(projectPath: $projectPath, music: music, onContinue: advance)
                case .run: HunRunStep(projectPath: $projectPath, music: music, onContinue: advance)
                case .modes: HunModesStep(projectPath: projectPath, onContinue: advance)
                case .menuBar: HunMenuBarStep(onFinish: finish)
                }
            }
            .id(step)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: goingBack ? -18 : 18)),
                        removal: .opacity.combined(with: .offset(x: goingBack ? 18 : -18))
                    )
            )

            // The first screen is centred; the dots start on the next one.
            if step != .welcome {
                HStack(spacing: 6) {
                    ForEach(HunOnboarding.Step.allCases, id: \.self) { item in
                        HunRoundedShape()
                            .fill(item == step ? AppTheme.textPrimary : AppTheme.textTertiary.opacity(0.35))
                            .frame(width: item == step ? 16 : 5, height: 5)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: step)
                .padding(.top, 30)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }
        }
        .padding(36)
        .frame(width: 540)
        .modifier(HunOnboardingCardSurface())
        .animation(.easeInOut(duration: 0.35), value: step)
    }

    private var topControls: some View {
        HStack(spacing: 14) {
            if step.rawValue > HunOnboarding.Step.license.rawValue && step != .menuBar {
                if colorScheme == .dark {
                    Button(action: finish) {
                        Text("Skip intro")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .hunFrosted()
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Skip intro", action: finish)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary.opacity(0.75))
                }
            }
            Button {
                muted.toggle()
                music.setMuted(muted)
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary.opacity(colorScheme == .dark ? 1 : 0.75))
                    .frame(width: 28, height: 28)
                    .modifier(HunMuteSurface(isDark: colorScheme == .dark))
            }
            .buttonStyle(.plain)
            .accessibilityHint(muted ? "Play music" : "Mute music")
        }
        .padding(18)
    }

    // MARK: Moving on

    private func advance() {
        guard let next = HunOnboarding.Step(rawValue: step.rawValue + 1) else { return finish() }
        goingBack = false
        withAnimation(.easeInOut(duration: 0.45)) { step = next }
    }

    /// One step back. The license step is passed over once Hun is unlocked.
    private func goBack() {
        guard var previous = HunOnboarding.Step(rawValue: step.rawValue - 1) else { return }
        if previous == .license && license.isLicensed {
            previous = .welcome
        }
        goingBack = true
        withAnimation(.easeInOut(duration: 0.45)) { step = previous }
    }

    private var backButton: some View {
        Button(action: goBack) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("Back")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(AppTheme.textPrimary.opacity(0.75))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("[", modifiers: .command)
        .accessibilityLabel("Back")
    }

    private func finish() {
        // Without a license there's nothing to finish into yet.
        guard license.isLicensed else {
            withAnimation(.easeInOut(duration: 0.45)) { step = .license }
            return
        }
        HunMenuBarCallout.hide()
        music.stop()
        HunOnboarding.releaseClay()
        HunOnboardingBackdrop.hide()
        #if DEBUG
        HunOnboarding.rehearsingAsNewUser = false
        license.endRehearsal()
        #endif
        if let projectPath, let project = store.model.projects.first(where: { $0.path == projectPath }) {
            store.selectProject(project.id)
        }
        HunOnboarding.markCompleted()
        withAnimation(.easeInOut(duration: 0.5)) { onFinish() }
    }
}

// MARK: - Shared pieces

/// A small spinning arc in a given colour (the system spinner ignores tint
/// at this size, and vanished on the white button).
private struct HunSpinner: View {
    let color: Color
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 11, height: 11)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { spinning = true }
            }
    }
}

/// A quiet line under a field: what went wrong, or that something's good.
private struct HunInlineNote: View {
    enum Tone { case problem, good }
    let text: String
    let tone: Tone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: tone == .problem ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(tone == .problem ? AppTheme.danger : AppTheme.success)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A short side-to-side shake, the macOS way of saying "not that".
private struct HunShake: GeometryEffect {
    var amount: Int
    var animatableData: CGFloat {
        get { CGFloat(amount) }
        set { progress = newValue }
    }
    private var progress: CGFloat = 0

    init(amount: Int) {
        self.amount = amount
        self.progress = CGFloat(amount)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(progress * .pi * 4), y: 0))
    }
}

// Light mode is solid warm paper over sunlit photos. Dark mode is frosted
// glass over night photos, with faint wells for the boxes inside the card.

private struct HunOnboardingCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // No card: the photo stays whole, and a soft glow of the page
        // colour sits behind the words so they read on any photo.
        content.background(
            RadialGradient(
                colors: [AppTheme.appBackground.opacity(colorScheme == .dark ? 0.62 : 0.78), AppTheme.appBackground.opacity(0)],
                center: .center,
                startRadius: 60,
                endRadius: 460
            )
            .padding(-160)
            .blur(radius: 24)
        )
    }
}

private struct HunMuteSurface: ViewModifier {
    let isDark: Bool

    func body(content: Content) -> some View {
        if isDark {
            content.hunFrosted()
        } else {
            content.background(HunRoundedShape().fill(AppTheme.textPrimary.opacity(0.07)))
        }
    }
}

private enum HunWellLevel {
    case sunken, base, hover, selected

    var fill: Color {
        switch self {
        case .sunken: return Color.black.opacity(0.22)
        case .base: return Color.white.opacity(0.06)
        case .hover: return Color.white.opacity(0.1)
        case .selected: return Color.white.opacity(0.14)
        }
    }
}

private struct HunWell: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let light: Color
    let border: Color?
    let darkLevel: HunWellLevel
    let focused: Bool

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
                .background(HunRoundedShape().fill(darkLevel.fill))
                .overlay(HunRoundedShape().strokeBorder(Color.white.opacity(focused ? 0.22 : 0.08), lineWidth: 1))
        } else {
            content
                .background(HunRoundedShape().fill(light))
                .overlay {
                    if let border { HunRoundedShape().strokeBorder(border, lineWidth: 1) }
                }
        }
    }
}

private extension View {
    func hunWell(_ light: Color, border: Color? = AppTheme.divider, darkLevel: HunWellLevel = .base, focused: Bool = false) -> some View {
        modifier(HunWell(light: light, border: border, darkLevel: darkLevel, focused: focused))
    }

    /// Frosted blur, like a macOS sidebar or popover.
    func hunFrosted() -> some View {
        self.background(HunRoundedShape().fill(.ultraThinMaterial))
            .overlay(HunRoundedShape().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}


private struct HunStepTitle: View {
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(HunFonts.display(size: 36))
                .tracking(-1.1)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(text)
                .font(.system(size: 14.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// The welcome's ink pill: dark ink in light mode, white in dark mode,
/// centred, with an arrow that nudges on hover.
private struct HunPrimaryButton: View {
    let title: String
    var isLoading = false
    var isEnabled = true
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var ink: Color {
        colorScheme == .dark ? .white : Color(red: 0x1F / 255, green: 0x1B / 255, blue: 0x16 / 255)
    }
    private var inkText: Color { colorScheme == .dark ? .black : .white }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    HunSpinner(color: inkText)
                }
                Text(title)
                if !isLoading {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .offset(x: hovering && isEnabled ? 2 : 0)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(inkText)
            .padding(.horizontal, 22)
            .frame(height: 42)
            .background(HunRoundedShape().fill(ink))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .frame(maxWidth: .infinity)
    }
}

private struct HunQuietButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A finished check, a spinner, or a quiet dot, with a line beside it.
private struct HunCheckRow: View {
    enum State { case waiting, working, done, note }
    let state: State
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                switch state {
                case .waiting:
                    Circle().fill(AppTheme.textTertiary.opacity(0.35)).frame(width: 6, height: 6)
                case .working:
                    ProgressView().controlSize(.mini).scaleEffect(0.75)
                case .done:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.success)
                case .note:
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(state == .waiting ? AppTheme.textTertiary : AppTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeOut(duration: 0.2), value: state == .done)
    }
}

/// A project's services as quiet rows: a status dot, the name, its port.
private struct HunServiceRows: View {
    let services: [HunService]
    var linksPorts = false
    /// Past this many, the last row says how many more, so the card never overflows.
    private let maxRows = 6

    private var shown: [HunService] {
        services.count > maxRows ? Array(services.prefix(maxRows - 1)) : services
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, service in
                HStack(spacing: 10) {
                    Circle()
                        .fill(color(service.status))
                        .frame(width: 7, height: 7)
                    Text(service.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(service.command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if service.port > 0 {
                        if linksPorts && service.status == .running {
                            Button {
                                if let url = URL(string: "http://localhost:\(service.port)") { NSWorkspace.shared.open(url) }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(verbatim: ":\(service.port)")
                                    Image(systemName: "arrow.up.right").font(.system(size: 8.5, weight: .bold))
                                }
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppTheme.textPrimary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Open localhost:\(service.port)")
                        } else {
                            Text(verbatim: ":\(service.port)")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .transition(.opacity.combined(with: .offset(y: 4)))
                if index < services.count - 1 {
                    Rectangle().fill(AppTheme.divider).frame(height: 1).padding(.leading, 29)
                }
            }
            if shown.count < services.count {
                Text("and \(services.count - shown.count) more")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 29)
                    .frame(height: 36)
            }
        }
        .hunWell(AppTheme.elevated)
        .animation(.easeOut(duration: 0.25), value: services.map(\.id))
        .animation(.easeOut(duration: 0.25), value: services.map(\.status))
    }

    private func color(_ status: ProjectStatus) -> Color {
        switch status {
        case .running: return AppTheme.success
        case .starting: return AppTheme.warning
        case .crashed: return AppTheme.danger
        case .stopped: return AppTheme.textTertiary.opacity(0.5)
        }
    }
}

// MARK: - 1. Welcome

/// The first thing anyone sees: no card, just Hun on the photo, set like
/// the hun.sh hero.
private struct HunWelcomeHero: View {
    let onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var shows = false

    private var ink: Color { colorScheme == .dark ? .white : Color(red: 0x1F / 255, green: 0x1B / 255, blue: 0x16 / 255) }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
                .accessibilityHidden(true)

            Text("Welcome to Hun")
                .font(HunFonts.display(size: 64))
                .tracking(-2.4)
                .foregroundStyle(ink)
                .padding(.top, 26)

            Text("Every dev server, in one place.")
                .font(.system(size: 18))
                .foregroundStyle(ink.opacity(0.68))
                .padding(.top, 10)

            HunPrimaryButton(title: "Get started", action: onContinue)
                .keyboardShortcut(.defaultAction)
            .padding(.top, 34)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 80)
        .padding(.vertical, 60)
        // A soft glow of the page colour behind the words, so they read on any photo.
        .background(
            RadialGradient(
                colors: [AppTheme.appBackground.opacity(colorScheme == .dark ? 0.55 : 0.7), AppTheme.appBackground.opacity(0)],
                center: .center,
                startRadius: 40,
                endRadius: 380
            )
            .blur(radius: 20)
        )
        .opacity(shows ? 1 : 0)
        .offset(y: shows || reduceMotion ? 0 : 10)
        .onAppear {
            if reduceMotion { shows = true; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.9)) { shows = true }
            }
        }
    }
}

// MARK: - 2. License

private struct HunLicenseStep: View {
    @Environment(HunLicenseManager.self) private var license
    let onContinue: () -> Void
    @State private var key = ""
    @State private var foundOnClipboard = false
    @FocusState private var focused: Bool

    private var isActivating: Bool {
        if case .activating = license.state { return true }
        return false
    }

    /// Bumped on each failed try, to shake the field.
    @State private var shakes = 0
    /// An error the person has since started fixing (by typing) is hidden.
    @State private var dismissedError: String?

    private var showsError: Bool {
        guard let error = license.errorMessage, !isActivating else { return false }
        return error != dismissedError
    }

    private var fieldBorder: Color {
        focused ? AppTheme.dividerStrong : AppTheme.divider
    }

    private var buysFirst: Bool {
        license.betaEnded && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isActivating
    }

    private func buy() {
        NSWorkspace.shared.open(license.configuration.checkoutURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HunStepTitle(
                title: license.betaEnded ? "Thanks for testing Hun" : "Unlock Hun",
                text: license.betaEnded
                    ? "The beta has ended. Buy Hun to keep going, then paste the key from your receipt. Your projects are all still here."
                    : "Paste the license key from your purchase. It's in your receipt email too, and it works on up to 3 Macs."
            )

            VStack(alignment: .leading, spacing: 8) {
                TextField("License key", text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .hunWell(AppTheme.searchField, border: fieldBorder, focused: focused)
                    .overlay {
                        if showsError {
                            HunRoundedShape().strokeBorder(AppTheme.danger.opacity(0.55), lineWidth: 1)
                        }
                    }
                    .modifier(HunShake(amount: shakes))
                    .focused($focused)
                    .onSubmit(activate)
                    .disabled(isActivating)
                    .onChange(of: key) { _, _ in dismissedError = license.errorMessage }

                if case let .unavailable(message) = license.state {
                    // A license that couldn't be checked (offline too long).
                    HunInlineNote(text: message, tone: .problem)
                } else if showsError, let error = license.errorMessage {
                    HunInlineNote(text: error, tone: .problem)
                        .transition(.opacity.combined(with: .offset(y: -3)))
                } else if foundOnClipboard {
                    HunInlineNote(text: "Found your key on the clipboard", tone: .good)
                        .transition(.opacity)
                }
            }
            .padding(.top, 24)

            // Beta testers have no key yet: until one is typed, the main
            // button buys Hun.
            if buysFirst {
                HunPrimaryButton(title: "Buy Hun · $9", action: buy)
                    .padding(.top, 20)
                Text("Bought it already? Paste the key above.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            } else {
                HunPrimaryButton(
                    title: isActivating ? "Checking your key…" : "Unlock Hun",
                    isLoading: isActivating,
                    isEnabled: !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: activate
                )
                .padding(.top, 20)

                HStack(spacing: 4) {
                    Text("Don't have one yet?")
                        .foregroundStyle(AppTheme.textTertiary)
                    HunQuietButton(title: "Buy Hun · $9", action: buy)
                }
                .font(.system(size: 12.5))
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            }

        }
        .onAppear {
            focused = true
            pickUpClipboardKey()
        }
        // Coming back from the browser after buying (or back online).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            pickUpClipboardKey()
            if case .unavailable = license.state {
                Task { await license.retryValidation() }
            }
        }
        .onChange(of: license.isLicensed) { _, licensed in
            if licensed { onContinue() }
        }
        .onChange(of: license.errorMessage) { _, error in
            dismissedError = nil
            if error != nil { withAnimation(.default) { shakes += 1 } }
        }
        .animation(.easeOut(duration: 0.2), value: showsError)
    }

    /// The purchase page copies the key; if it's on the clipboard, use it.
    private func pickUpClipboardKey() {
        guard key.isEmpty, let text = NSPasteboard.general.string(forType: .string) else { return }
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeKey = candidate.count >= 16 && candidate.count <= 80
            && candidate.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
            && candidate.contains("-")
        guard looksLikeKey else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            key = candidate
            foundOnClipboard = true
        }
    }

    private func activate() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isActivating else { return }
        Task {
            await license.activate(trimmed)
            if license.isLicensed { HunConfetti.celebrate() }
        }
    }
}

// MARK: - 3. Your agent

private struct HunAgentStep: View {
    @Environment(HunStore.self) private var store
    let onContinue: () -> Void
    @State private var checked = 0
    @State private var agent: HunAgent?
    /// Every agent on this Mac; `agent` is the one Hun will use.
    @State private var installed: Set<HunAgentKind> = []
    @State private var skillInstalled = false
    @State private var cliPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HunAgentPair(found: installed, isLooking: checked == 0)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
            HunStepTitle(
                title: "Your coding agent",
                text: "Hun works best alongside the agent you already use. It reads your projects to set them up, and starts and checks servers through Hun."
            )

            VStack(alignment: .leading, spacing: 18) {
                if let agent {
                    HunCheckRow(
                        state: rowState(0),
                        title: installed.count > 1
                            ? "Claude Code and Codex are on this Mac"
                            : "\(agent.kind.displayName) is on this Mac",
                        detail: installed.count > 1
                            ? "Hun will ask \(agent.kind.displayName) to read each project you add and set it up."
                            : "Hun will ask it to read each project you add and set it up."
                    )
                } else {
                    HunCheckRow(
                        state: checked > 0 ? .note : rowState(0),
                        title: checked > 0 ? "No coding agent yet" : "Looking for your agent",
                        detail: checked > 0
                            ? "Hun will work setups out from each project's files. Add Claude Code or Codex anytime, and Hun will use it."
                            : "Claude Code or Codex."
                    )
                }
                HunCheckRow(
                    state: rowState(1),
                    title: "Your agents know Hun",
                    detail: "Claude Code, Codex and Cursor now start, stop and check dev servers through Hun, so you see everything they run."
                )
                HunCheckRow(
                    state: cliPath == nil && checked > 2 ? .note : rowState(2),
                    title: "The hun command works in your terminal",
                    detail: cliPath.map { "It's at \($0)." } ?? "Open Hun from Applications once and it adds itself."
                )
            }
            // Rows read left-aligned, as a block centred in the column.
            .frame(maxWidth: 380, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, 26)

            HunPrimaryButton(title: "Continue", isEnabled: checked >= 3, action: onContinue)
                .padding(.top, 28)
        }
        .task { await check() }
    }

    private func rowState(_ index: Int) -> HunCheckRow.State {
        checked > index ? .done : (checked == index ? .working : .waiting)
    }

    private func check() async {
        agent = await store.resolveAgent()
        installed = Set(await store.installedAgents().map(\.kind))
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(.easeOut(duration: 0.2)) { checked = 1 }

        skillInstalled = await Task.detached(priority: .userInitiated) {
            (try? HunAgentSkillInstaller.installBundledSkillGlobally()) != nil
        }.value
        try? await Task.sleep(for: .milliseconds(550))
        withAnimation(.easeOut(duration: 0.2)) { checked = 2 }

        let home = FileManager.default.homeDirectoryForCurrentUser
        cliPath = HunCLILinker.directories(home: home)
            .map { $0.appendingPathComponent("hun").path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { $0.replacingOccurrences(of: home.path, with: "~") }
        try? await Task.sleep(for: .milliseconds(550))
        withAnimation(.easeOut(duration: 0.2)) { checked = 3 }
    }
}

/// Claude Code and Codex, side by side. The one on this Mac is lit and
/// ticked; the other waits, dimmed.
private struct HunAgentPair: View {
    let found: Set<HunAgentKind>
    let isLooking: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            tile(.claude)
            tile(.codex)
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: found)
        .accessibilityHidden(true)
    }

    private func tile(_ kind: HunAgentKind) -> some View {
        let lit = isLooking || found.contains(kind)
        return VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Image(kind.markAsset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(AppTheme.divider, lineWidth: 1))
                    .shadow(color: .black.opacity(lit ? 0.12 : 0), radius: 10, y: 4)
                if found.contains(kind) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(AppTheme.success))
                        .overlay(Circle().strokeBorder(colorScheme == .dark ? Color.black : Color.white, lineWidth: 2))
                        .offset(x: 5, y: 5)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            Text(kind.shortName)
                .font(.system(size: 11.5, weight: found.contains(kind) ? .semibold : .medium))
                .foregroundStyle(found.contains(kind) ? AppTheme.textPrimary : AppTheme.textTertiary)
        }
        .opacity(lit ? 1 : 0.45)
        .saturation(lit ? 1 : 0.2)
    }
}

// MARK: - 4. First project

private struct HunProjectStep: View {
    @Environment(HunStore.self) private var store
    @Binding var projectPath: String?
    let music: HunOnboardingMusic
    let onContinue: () -> Void
    @State private var suggestions: [HunProjectSuggestion] = []
    @State private var adding = false
    @State private var showsAddAnother = false
    @State private var dropTargeted = false
    @State private var chimed = false

    private var existing: [HunProject] {
        #if DEBUG
        if HunOnboarding.rehearsingAsNewUser { return [] }
        #endif
        return store.model.projects
    }

    private var project: HunProject? {
        projectPath.flatMap { path in store.model.projects.first { $0.path == path } }
    }

    private var setup: HunAgentMessage? {
        projectPath.flatMap { store.agentChats[$0]?.messages.first }
    }

    private var isSettingUp: Bool {
        adding || setup?.status == .working
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let projectPath, let name = project?.name ?? Optional(URL(fileURLWithPath: projectPath).lastPathComponent) {
                settingUp(name: name)
            } else if !existing.isEmpty && !showsAddAnother {
                yourProjects
            } else {
                choose
            }
        }
        .onAppear {
            let registered = Set(store.model.projects.map(\.path))
            Task.detached(priority: .userInitiated) {
                let found = HunProjectSuggestions.find(limit: 4, excluding: registered)
                await MainActor.run { withAnimation(.easeOut(duration: 0.25)) { suggestions = found } }
            }
        }
        .onChange(of: isSettingUp) { was, now in
            if was && !now && !chimed {
                chimed = true
                music.chime()
            }
        }
        #if DEBUG
        .onReceive(DistributedNotificationCenter.default().publisher(for: .init("sh.hun.debug.onboardingAdd"))) { note in
            if let path = note.object as? String { add(URL(fileURLWithPath: path, isDirectory: true)) }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .init("sh.hun.debug.onboardingChoose"))) { _ in
            withAnimation(.easeOut(duration: 0.25)) { showsAddAnother = true }
        }
        #endif
    }

    // Someone who already has projects in Hun.
    private var yourProjects: some View {
        VStack(alignment: .leading, spacing: 0) {
            HunStepTitle(
                title: existing.count == 1 ? "You already have a project in Hun" : "You already have \(existing.count) projects in Hun",
                text: "They're all set up. Pick one to try the next step with, or add another to watch your agent set it up."
            )
            VStack(spacing: 6) {
                ForEach(existing.prefix(4)) { item in
                    HunPickRow(
                        title: item.name,
                        detail: item.services.count == 1 ? "1 service" : "\(item.services.count) services",
                        badge: nil,
                        isSelected: projectPath == item.path
                    ) { projectPath = item.path }
                }
            }
            .padding(.top, 22)
            HStack {
                Spacer()
                HunQuietButton(title: "Add another project") {
                    withAnimation(.easeOut(duration: 0.25)) { showsAddAnother = true }
                }
                Spacer()
            }
            .padding(.top, 14)
            HunPrimaryButton(title: "Continue") {
                if projectPath == nil { projectPath = existing.first?.path }
                onContinue()
            }
            .padding(.top, 22)
        }
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: 0) {
            HunStepTitle(
                title: "Add your first project",
                text: store.availableAgent.map { "Pick a project you're working on. \($0.kind.shortName) will read it and set it up for you." }
                    ?? "Pick a project you're working on, and Hun will set it up."
            )

            if !suggestions.isEmpty {
                VStack(spacing: 6) {
                    ForEach(suggestions) { suggestion in
                        HunPickRow(
                            title: suggestion.name,
                            detail: [suggestion.place, suggestion.kind].compactMap { $0 }.joined(separator: " · "),
                            badge: suggestion.hasConfig ? "Has a .hun.yml" : nil,
                            isSelected: false
                        ) { add(URL(fileURLWithPath: suggestion.path)) }
                    }
                }
                .padding(.top, 22)
                .transition(.opacity)
            }

            Button(action: chooseFolder) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                    Text(suggestions.isEmpty ? "Choose a project folder, or drop one here" : "Another folder… or drop one here")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(dropTargeted ? AppTheme.textPrimary : AppTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: suggestions.isEmpty ? 92 : 44)
                .background(
                    HunRoundedShape()
                        .strokeBorder(dropTargeted ? AppTheme.accent : AppTheme.dividerStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, suggestions.isEmpty ? 22 : 10)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in add(url) }
                }
                return true
            }

            if !existing.isEmpty {
                HStack {
                    Spacer()
                    HunQuietButton(title: "Back to your projects") {
                        withAnimation(.easeOut(duration: 0.25)) { showsAddAnother = false }
                    }
                    Spacer()
                }
                .padding(.top, 16)
            }
        }
    }

    @ViewBuilder
    private func settingUp(name: String) -> some View {
        let working = isSettingUp
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let kind = store.agentChats[projectPath ?? ""]?.agent {
                    HunAgentMark(kind: kind, isWorking: working, size: 28)
                }
                Text(working
                     ? "\(store.agentChats[projectPath ?? ""]?.agent.shortName ?? "Hun") is setting up \(name)"
                     : "\(name) is ready")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .contentTransition(.opacity)
            }

            if working {
                Text("Reading the project to work out what runs, and how. About 20 seconds.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.top, 8)
                HunAgentLiveSteps(steps: setup?.steps ?? [], isThinking: setup?.isThinking == true, limit: 4)
                    .padding(.top, 22)
                HunFileChips(files: setup?.files ?? [])
                    .padding(.top, 12)
                    .frame(minHeight: 44, alignment: .top)
            } else {
                if let summary = setup?.text, !summary.isEmpty, setup?.status == .done {
                    HunMarkdownText(text: summary, color: AppTheme.textSecondary)
                        .padding(.top, 10)
                }
                if let project {
                    HunServiceRows(services: project.services.filter { !$0.isExternal })
                        .padding(.top, 18)
                }
                HunPrimaryButton(title: "Continue", action: onContinue)
                    .padding(.top, 24)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: working)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        panel.message = "Choose a project you're working on."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(url)
    }

    private func add(_ url: URL) {
        let path = url.standardizedFileURL.path
        withAnimation(.easeInOut(duration: 0.35)) {
            projectPath = path
            adding = true
        }
        Task {
            await store.addProject(at: url)
            // The registered path, if Hun normalised it.
            if let match = store.model.projects.first(where: {
                URL(fileURLWithPath: $0.path).standardizedFileURL.path == path
            }) {
                projectPath = match.path
            }
            withAnimation(.easeOut(duration: 0.25)) { adding = false }
        }
    }
}

private struct HunPickRow: View {
    let title: String
    let detail: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppTheme.success)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(HunRoundedShape().fill(AppTheme.success.opacity(0.1)))
                }
                Image(systemName: isSelected ? "checkmark" : "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.success : AppTheme.textTertiary)
                    .opacity(isSelected || hovering ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .hunWell(
                isSelected ? AppTheme.selectedFill : (hovering ? AppTheme.hover : AppTheme.elevated),
                border: isSelected ? AppTheme.dividerStrong : AppTheme.divider,
                darkLevel: isSelected ? .selected : (hovering ? .hover : .base)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - 5. Run it

private struct HunRunStep: View {
    @Environment(HunStore.self) private var store
    @Binding var projectPath: String?
    let music: HunOnboardingMusic
    let onContinue: () -> Void
    @State private var started = false

    private var project: HunProject? {
        projectPath.flatMap { path in store.model.projects.first { $0.path == path } }
            ?? store.model.projects.first
    }

    private var services: [HunService] {
        project?.services.filter { !$0.isExternal } ?? []
    }

    private var runningPort: Int? {
        services.first { $0.status == .running && $0.port > 0 }?.port
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let project {
                HunStepTitle(
                    title: started ? (runningPort != nil ? "\(project.name) is running" : "Starting \(project.name)…") : "Now run it",
                    text: started
                        ? "Hun starts each service in the right order and keeps its logs. Click a port to open it."
                        : "One click starts everything \(project.name) needs, in the right order."
                )
                HunServiceRows(services: services, linksPorts: true)
                    .padding(.top, 22)
                if started {
                    HunPrimaryButton(title: "Continue", action: onContinue)
                        .padding(.top, 24)
                } else {
                    HunPrimaryButton(title: "Run \(project.name)") {
                        projectPath = project.path
                        music.swell()
                        withAnimation(.easeOut(duration: 0.25)) { started = true }
                        store.run(project)
                    }
                    .padding(.top, 24)
                    HStack {
                        Spacer()
                        HunQuietButton(title: "Not now", action: onContinue)
                        Spacer()
                    }
                    .padding(.top, 14)
                }
            } else {
                HunStepTitle(
                    title: "Run anything with one click",
                    text: "Once a project is in Hun, one click starts everything it needs, in the right order."
                )
                HunPrimaryButton(title: "Continue", action: onContinue)
                    .padding(.top, 24)
            }
        }
        .animation(.easeOut(duration: 0.3), value: started)
    }
}

// MARK: - 6. How projects run

private struct HunModesStep: View {
    @Environment(HunStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let projectPath: String?
    let onContinue: () -> Void

    /// Where the little demo is: 0, the first project runs alone; 1, the
    /// second one is starting (and, in Focus, the first is stopping); 2, done.
    @State private var phase = 2
    @State private var playID = 0
    @Namespace private var segment

    private var first: HunProject? {
        projectPath.flatMap { path in store.model.projects.first { $0.path == path } }
            ?? store.model.projects.first
    }

    /// Their own project names when there are two, so the demo is theirs.
    private var names: (String, String) {
        let one = first?.name ?? "web"
        let two = store.model.projects.first { $0.id != first?.id }?.name ?? "api"
        return (one, two)
    }

    private var mode: HunMode { store.displayedMode }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HunStepTitle(
                title: "One project at a time, or several?",
                text: "Choose what happens when you start a project while another one is running. You can change it anytime."
            )

            HStack(spacing: 2) {
                segmentButton(.multitask, "Multitask")
                segmentButton(.focus, "Focus")
            }
            .padding(3)
            .hunWell(AppTheme.modeSelectorBackground, border: nil, darkLevel: .sunken)
            .padding(.top, 22)

            VStack(spacing: 0) {
                demoRow(names.0, state: firstState)
                Rectangle().fill(AppTheme.divider).frame(height: 1).padding(.leading, 30)
                demoRow(names.1, state: secondState)
            }
            .padding(.vertical, 4)
            .hunWell(AppTheme.elevated)
            .padding(.top, 12)

            Text(caption)
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                .id(mode)
                .transition(.opacity)
                .padding(.top, 12)

            HunPrimaryButton(title: "Continue", action: onContinue)
                .padding(.top, 20)
        }
        .animation(.easeOut(duration: 0.25), value: mode)
        .onAppear(perform: play)
        .onChange(of: mode) { _, _ in play() }
    }

    private var caption: String {
        switch mode {
        case .multitask:
            return "\(names.0) keeps running, and \(names.1) moves to :3001 because :3000 is taken."
        case .focus:
            return "Hun stops \(names.0) first, so \(names.1) gets its own port, :3000."
        }
    }

    private enum RowState: Equatable { case running(Int), starting, stopping, stopped }

    private var firstState: RowState {
        if mode == .focus && phase >= 1 { return phase == 1 ? .stopping : .stopped }
        return .running(3000)
    }

    private var secondState: RowState {
        switch phase {
        case 0: return .stopped
        case 1: return .starting
        default: return .running(mode == .multitask ? 3001 : 3000)
        }
    }

    private func segmentButton(_ value: HunMode, _ title: String) -> some View {
        let selected = mode == value
        return Button {
            store.changeMode(value, preferredProject: first?.id)
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? AppTheme.textPrimary : AppTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background {
                    if selected {
                        HunRoundedShape()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.14) : AppTheme.elevated)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.08), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "segment", in: segment)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func demoRow(_ name: String, state: RowState) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor(state))
                .frame(width: 7, height: 7)
            Text(name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(state == .stopped ? AppTheme.textTertiary : AppTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Group {
                switch state {
                case .running(let port):
                    Text(verbatim: ":\(port)")
                        .foregroundStyle(port == 3000 ? AppTheme.textSecondary : highlight)
                case .starting: Text("starting…").foregroundStyle(AppTheme.textTertiary)
                case .stopping: Text("stopping…").foregroundStyle(AppTheme.textTertiary)
                case .stopped: Text("stopped").foregroundStyle(AppTheme.textTertiary)
                }
            }
            .font(.system(size: 11.5, design: .monospaced))
            .contentTransition(.opacity)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .animation(.easeOut(duration: 0.25), value: state)
    }

    private func dotColor(_ state: RowState) -> Color {
        switch state {
        case .running: return AppTheme.success
        case .starting, .stopping: return AppTheme.warning
        case .stopped: return AppTheme.textTertiary.opacity(0.45)
        }
    }

    /// The accent, lifted in dark mode so it reads on glass.
    private var highlight: Color {
        AppTheme.accentText
    }

    /// Acts the choice out: the second project starts, and in Focus the first stops.
    private func play() {
        guard !reduceMotion else { phase = 2; return }
        playID += 1
        let id = playID
        phase = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard id == playID else { return }
            phase = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard id == playID else { return }
                phase = 2
            }
        }
    }
}

// MARK: - 7. The menu bar

private struct HunMenuBarStep: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HunStepTitle(
                title: "Hun lives in your menu bar",
                text: "Click the switch up there anytime to see what's running, open a port, or stop it all. Close this window whenever you like: your servers keep running."
            )
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.top, 2)
                Text("The Focus | Multitask switch is in there too, so you can change how projects run anytime.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .hunWell(AppTheme.searchField, border: nil)
            .padding(.top, 20)
            HunPrimaryButton(title: "Start using Hun", action: onFinish)
                .padding(.top, 24)
        }
        .onAppear { HunMenuBarCallout.show() }
        .onDisappear { HunMenuBarCallout.hide() }
    }
}

/// A small note that points at Hun's switch in the real menu bar.
@MainActor
enum HunMenuBarCallout {
    private static var panel: NSPanel?

    static func show() {
        guard let target = HunStatusItemController.buttonFrameOnScreen else { return }
        let size = NSSize(width: 236, height: 70)
        let panel = self.panel ?? {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: HunCalloutBubble())
            return panel
        }()
        self.panel = panel
        let origin = NSPoint(x: target.midX - size.width / 2, y: target.minY - size.height - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 1
        }
    }

    static func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }
}

private struct HunCalloutBubble: View {
    @State private var bob = false

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(AppTheme.textPrimary)
                .frame(width: 14, height: 7)
            Text("Hun lives here. Click it anytime.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.appBackground)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(HunRoundedShape().fill(AppTheme.textPrimary))
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .offset(y: bob ? 3 : 0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bob = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

/// While the welcome is open, every screen behind Hun's window shows the
/// desktop wallpaper, heavily blurred and darkened, so other apps and icons
/// fall away and only the welcome is lit. The wallpaper (not a live blur of
/// whatever is behind) keeps it even, whatever is open. Clicking it brings
/// Hun's window back to front.
@MainActor
enum HunOnboardingBackdrop {
    private static var windows: [NSWindow] = []
    /// The layer showing the scene on each screen.
    private static var sceneLayers: [CALayer] = []
    private static var observers: [NSObjectProtocol] = []
    private static var isDark = false
    private static var currentAsset: String?
    /// Each step's blurred night photo, made ahead in the background.
    private static var nightCache: [String: CGImage] = [:]

    static func show(step: HunOnboarding.Step) {
        guard windows.isEmpty,
              let main = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
        else { return }

        // Light mode: the desktop wallpaper, blurred. Dark mode: the step's
        // own night photo, blurred across the whole screen, so the window
        // looks like the lit middle of a bigger night scene.
        isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        for screen in NSScreen.screens {
            let backdrop = HunBackdropWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            backdrop.isOpaque = true
            backdrop.backgroundColor = .black
            backdrop.hasShadow = false
            backdrop.level = main.level
            backdrop.collectionBehavior = [.fullScreenAuxiliary, .transient]
            backdrop.isReleasedWhenClosed = false

            let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.black.cgColor
            let scene = CALayer()
            scene.frame = content.bounds
            scene.contentsGravity = .resizeAspectFill
            scene.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            if !isDark { scene.contents = blurredWallpaper(for: screen) }
            content.layer?.addSublayer(scene)
            sceneLayers.append(scene)

            let dim = CALayer()
            dim.frame = content.bounds
            dim.backgroundColor = NSColor.black.withAlphaComponent(isDark ? 0.45 : 0.62).cgColor
            dim.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            content.layer?.addSublayer(dim)
            if isDark {
                // Darker toward the edges, so the window glows in the middle.
                let vignette = CAGradientLayer()
                vignette.type = .radial
                vignette.frame = content.bounds
                vignette.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.7).cgColor]
                vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
                vignette.endPoint = CGPoint(x: 1.15, y: 1.15)
                vignette.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                content.layer?.addSublayer(vignette)
            }
            backdrop.contentView = content
            backdrop.onClick = { main.makeKeyAndOrderFront(nil) }

            backdrop.alphaValue = 0
            backdrop.order(.below, relativeTo: main.windowNumber)
            windows.append(backdrop)
        }
        if isDark { prepareNights(startingWith: step) }
        update(step: step, animated: false)
        NSApp.activate()
        main.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            windows.forEach { $0.animator().alphaValue = 1 }
        }

        // Keep the backdrop just behind Hun's window when Hun comes back.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                windows.forEach { $0.order(.below, relativeTo: main.windowNumber) }
            }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: main, queue: .main) { _ in
            MainActor.assumeIsolated { hide() }
        })
    }

    /// Follows the welcome from step to step: the scene behind (in dark
    /// mode), and the menu bar and Dock, hidden until the last step, which
    /// points at Hun up in the menu bar. macOS restores both whenever Hun
    /// isn't the active app.
    /// A step whose photo wasn't ready when it came up.
    private static var pendingAsset: String?

    static func update(step: HunOnboarding.Step, animated: Bool = true) {
        guard !windows.isEmpty else { return }
        if isDark && nightCache[step.background] == nil { pendingAsset = step.background }
        NSApp.presentationOptions = step == .menuBar ? [] : [.hideDock, .hideMenuBar]

        guard isDark, currentAsset != step.background else { return }
        // Made ahead in the background; if this one isn't ready yet, it's
        // shown the moment it is (see prepareNights).
        guard let image = nightCache[step.background] else { return }
        currentAsset = step.background
        for layer in sceneLayers {
            if animated {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.6
                layer.add(fade, forKey: "scene")
            }
            layer.contents = image
        }
    }

    /// Blurs every step's night photo off the main thread, the current step
    /// first, so moving between steps never waits on it.
    private static func prepareNights(startingWith step: HunOnboarding.Step) {
        let names = [step.background] + HunOnboarding.Step.allCases.map(\.background).filter { $0 != step.background }
        // Read the night version of each photo here (it needs the dark
        // appearance), then do the slow part elsewhere.
        let sources: [(String, CGImage)] = names.compactMap { name in
            guard nightCache[name] == nil, let image = nightSource(named: name) else { return nil }
            return (name, image)
        }
        Task.detached(priority: .userInitiated) {
            for (name, source) in sources {
                // Same softness as a radius-28 blur on the full-size photo.
                guard let blurred = HunBackdropBlur.blur(source, radius: 14) else { continue }
                await MainActor.run {
                    nightCache[name] = blurred
                    // Show it if its step is up and waiting.
                    if currentAsset == nil || (currentAsset != name && pendingAsset == name) {
                        pendingAsset = nil
                        if let step = HunOnboarding.Step.allCases.first(where: { $0.background == name }) {
                            update(step: step, animated: currentAsset != nil)
                        }
                    }
                }
            }
        }
    }

    static func hide() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        NSApp.presentationOptions = []
        sceneLayers.removeAll()
        currentAsset = nil
        pendingAsset = nil
        let closing = windows
        windows.removeAll()
        guard !closing.isEmpty else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            closing.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated { closing.forEach { $0.orderOut(nil) } }
        }
    }

    /// The screen's wallpaper, small and very soft (it's shown huge and dim,
    /// so a small blurred copy is enough, and quick).
    private static func blurredWallpaper(for screen: NSScreen) -> CGImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 640,
              ] as CFDictionary)
        else { return nil }
        return blurred(thumbnail)
    }

    /// A step's night photo, drawn small (it's blurred and shown huge).
    private static func nightSource(named name: String) -> CGImage? {
        guard let image = NSImage(named: name) else { return nil }
        let width = 900.0
        let height = width * image.size.height / max(image.size.width, 1)
        guard let context = CGContext(
            data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.restoreGraphicsState()
        }
        return context.makeImage()
    }

    private static func blurred(_ image: CGImage) -> CGImage? {
        HunBackdropBlur.blur(image)
    }
}

/// The backdrop's blur, safe to run off the main thread.
nonisolated enum HunBackdropBlur {
    static func blur(_ image: CGImage, radius: Double = 28) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let blur = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: input.clampedToExtent(),
            kCIInputRadiusKey: radius,
        ])?.outputImage?.cropped(to: input.extent)
        else { return nil }
        return CIContext().createCGImage(blur, from: input.extent)
    }
}

private final class HunBackdropWindow: NSWindow {
    var onClick: (() -> Void)?
    override var canBecomeKey: Bool { false }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
