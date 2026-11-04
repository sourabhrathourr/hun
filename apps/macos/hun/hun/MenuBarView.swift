import SwiftUI
import AppKit

/// The menu bar panel: what's running, a quick way to run or stop anything,
/// and the way into the dashboard.
struct MenuBarView: View {
    @Environment(HunStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HunMenuLook.lightVistaKey) private var lightVista = HunMenuLook.defaultLightVista.rawValue
    @AppStorage(HunMenuLook.darkVistaKey) private var darkVista = HunMenuLook.defaultDarkVista.rawValue
    @AppStorage(HunMenuMusic.enabledKey) private var musicEnabled = true

    private var scene: HunMenuLook.Scene {
        colorScheme == .dark
            ? HunMenuLook.vista(named: darkVista, dark: true)
            : HunMenuLook.vista(named: lightVista, dark: false)
    }

    private var projects: [HunProject] {
        store.model.projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var running: [HunProject] {
        projects.filter { $0.status != .stopped || store.projectAction(for: $0) == .stopProject }
    }

    /// The rest, but not idle worktrees: a project can have dozens, and
    /// they show here only while they run (the dashboard lists them all).
    private var others: [HunProject] {
        projects.filter { project in !project.isWorktree && !running.contains { $0.id == project.id } }
    }

    /// Running first (they matter most), then the rest by name.
    private var ordered: [HunProject] { running + others }

    var body: some View {
        ZStack(alignment: .bottom) {
            HunVistaImage(scene: scene)

            VStack(spacing: 0) {
                MenuSky(
                    showsGlow: scene.needsGlow,
                    // Up if any service runs; a crashed service is counted on its own.
                    running: HunMenuPreview.shared.running(running.filter { project in project.services.contains { $0.status == .running || $0.status == .starting } }, all: projects),
                    crashedCount: running.reduce(0) { $0 + $1.services.filter { $0.status == .crashed }.count },
                    mode: HunMenuPreview.shared.mode ?? store.displayedMode,
                    showsMusic: musicEnabled
                )
                .padding(.top, 44)

                Spacer(minLength: 56)

                // The glass sill: every project, with its switch.
                VStack(spacing: 0) {
                    if projects.isEmpty {
                        MenuEmptyState()
                    } else {
                        SleekMenuScrollView(maxHeight: 236) {
                            VStack(spacing: 2) {
                                ForEach(ordered) { project in
                                    MenuSwitchRow(
                                        project: project,
                                        pendingAction: store.projectAction(for: project),
                                        onForceStop: store.forceStopAction(for: project),
                                        onOpen: { open(project) },
                                        onRun: { store.globalMode == .focus ? store.focus(project) : store.run(project) },
                                        onStop: { store.stop(project) },
                                        onRestart: { store.restart(project) }
                                    )
                                }
                            }
                            .padding(6)
                        }
                    }
                    MenuDivider()
                    MenuSillFooter(
                        mode: Binding(
                            get: { store.displayedMode },
                            set: { store.changeMode($0, preferredProject: nil) }
                        ),
                        isModePending: store.isChangingMode
                    )
                }
                // Solid, in the dashboard's own colours: warm near-white in
                // light mode, a deep near-black in dark mode.
                .background(HunRoundedShape().fill(colorScheme == .dark ? Color(red: 0.05, green: 0.05, blue: 0.055).opacity(0.94) : AppTheme.menuBackground.opacity(0.95)))
                .background(HunRoundedShape().fill(.ultraThinMaterial))
                .overlay(HunRoundedShape().strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : AppTheme.divider, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(10)
            }
        }
        .frame(width: 340)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
    }

    private func open(_ project: HunProject) {
        store.selectProject(project.id)
        hunApp.openDashboard()
    }
}

/// Vistas: the photos behind Hun's menu bar panel.
enum HunMenuLook {
    /// The vista chosen for each appearance; dark mode offers only the
    /// vistas that have night versions.
    static let lightVistaKey = "hun.menu.vista.light"
    static let darkVistaKey = "hun.menu.vista.dark"
    static let defaultLightVista = Scene.valley
    static let defaultDarkVista = Scene.lavender

    static func vista(named name: String, dark: Bool) -> Scene {
        let fallback = dark ? defaultDarkVista : defaultLightVista
        let scene = Scene(rawValue: name) ?? fallback
        return dark && !scene.hasNightVersion ? fallback : scene
    }

    enum Scene: String, CaseIterable {
        case doorway, valley, lavender, path, dunes, wall, saltpans
        case meadow, birches, mountains, lake

        var title: String {
            switch self {
            case .doorway: return "Doorway"
            case .valley: return "Olive valley"
            case .lavender: return "Lavender"
            case .path: return "Hill path"
            case .dunes: return "Dunes"
            case .wall: return "Plaster wall"
            case .saltpans: return "Salt pans"
            case .meadow: return "Meadow tree"
            case .birches: return "Birches"
            case .mountains: return "Mountains"
            case .lake: return "Lake"
            }
        }

        var asset: String {
            switch self {
            case .doorway: return "OnboardingWelcome"
            case .valley: return "OnboardingLicense"
            case .lavender: return "OnboardingModes"
            case .path: return "OnboardingRun"
            case .dunes: return "OnboardingAgent"
            case .wall: return "OnboardingProject"
            case .saltpans: return "OnboardingMenuBar"
            default: return "MenuScene-\(rawValue)"
            }
        }

        /// Busy enough behind the header that its words need a soft glow.
        var needsGlow: Bool { self == .meadow || self == .birches }

        /// 1–7 come with night versions; the website's are darkened instead.
        var hasNightVersion: Bool { !asset.hasPrefix("MenuScene-") }

        /// Which part of the photo shows, across (0 left, 1 right) and down
        /// (0 top, 1 bottom), so its subject sits above the glass sill.
        var focus: CGPoint {
            switch self {
            case .doorway: return CGPoint(x: 0.5, y: 0.62)
            case .valley: return CGPoint(x: 0.35, y: 0.45)
            case .lavender: return CGPoint(x: 0.5, y: 0.35)
            case .path: return CGPoint(x: 0.8, y: 0.4)
            case .dunes: return CGPoint(x: 0.5, y: 0.45)
            case .wall: return CGPoint(x: 0.5, y: 0.3)
            case .saltpans: return CGPoint(x: 0.5, y: 0.4)
            case .meadow: return CGPoint(x: 0.62, y: 0.4)
            case .birches: return CGPoint(x: 0.72, y: 0.4)
            case .mountains: return CGPoint(x: 0.5, y: 0.4)
            case .lake: return CGPoint(x: 0.5, y: 0.4)
            }
        }
    }
}

/// A vista filling its frame, framed on its subject. The menu bar's
/// backdrop, and the thumbnails in Settings.
struct HunVistaImage: View {
    let scene: HunMenuLook.Scene
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let image = NSImage(named: scene.asset)
            let natural = image?.size ?? CGSize(width: 16, height: 9)
            // Fill the panel, then slide the photo so its focus point shows.
            let scale = max(proxy.size.width / natural.width, proxy.size.height / natural.height)
            let size = CGSize(width: natural.width * scale, height: natural.height * scale)
            let x = -(size.width - proxy.size.width) * scene.focus.x
            let y = -(size.height - proxy.size.height) * scene.focus.y
            Image(scene.asset)
                .resizable()
                .interpolation(.high)
                // A little less warmth in light mode; deeper at night, so the
                // panel sits as dark as the dashboard.
                .saturation(colorScheme == .dark ? 0.8 : 0.82)
                .frame(width: size.width, height: size.height)
                .offset(x: x, y: y)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
                .overlay(colorScheme == .dark ? Color.black.opacity(scene.hasNightVersion ? 0.12 : 0.4) : Color.clear)
        }
        .accessibilityHidden(true)
    }
}

/// The sky: today's date, and how many projects are running, large, like
/// a clock on a lock screen.
private struct MenuSky: View {
    /// A soft glow behind the words, for the vistas busy enough to need it.
    let showsGlow: Bool
    let running: [HunProject]
    let crashedCount: Int
    let mode: HunMode
    /// Music is turned on in Settings: the corner switch shows.
    var showsMusic = false
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var sky

    private var music: HunMenuMusic { .shared }
    /// How far the corner row sits above the sky, in the strip at the top
    /// of the panel, clear of the date.
    static let cornerLift: CGFloat = 30

    /// Words that make way for the flying hero: out at once, back in only
    /// after it has landed, so it never passes over them.
    static let wordsTransition = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.42)),
        removal: .opacity.animation(.easeOut(duration: 0.14))
    )

    /// While music plays it takes the middle of the sky.
    private var musicPlaying: Bool { showsMusic && music.isPlaying }

    private var ink: Color { colorScheme == .dark ? .white : Color(red: 0x2B / 255, green: 0x26 / 255, blue: 0x22 / 255) }

    /// Focus runs one project at a time, so it shows which; Multitask shows how many.
    private var focused: HunProject? { mode == .focus ? running.first : nil }

    /// The focused project's name (a debug preview can stand in a long one).
    private var focusedName: String? { focused.map { HunMenuPreview.shared.focusName ?? $0.name } }

    /// The widest the hero may be at rest; a longer name is cut in the middle.
    static let heroWidth: CGFloat = 232

    var body: some View {
        ZStack {
            if musicPlaying {
                // The corner words come in once the hero has landed beside them.
                VStack(spacing: 0) {
                    musicHeader
                    Spacer(minLength: 0)
                }
                .padding(.top, -Self.cornerLift)
                .transition(Self.wordsTransition)
                VStack(spacing: 0) {
                    Color.clear.frame(height: 24)
                    Spacer(minLength: 0)
                    // A little below the middle, nearer the sill.
                    HunSkyMusic()
                        .offset(y: 18)
                    Spacer(minLength: 0)
                }
                // The header rides up into the strip above the sky, level
                // with the corner switch, leaving the middle to the music.
                .padding(.top, -Self.cornerLift)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96)).animation(.smooth(duration: 0.5).delay(0.12)),
                    removal: .opacity.animation(.easeOut(duration: 0.18))
                ))
            } else {
                quiet
                    .transition(Self.wordsTransition)
            }
            hero
            if isEmpty {
                quietWords
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 14)
        // One height in Focus and Multitask, with or without music, so the
        // panel never resizes; full width, so the corner switch sits in the corner.
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .overlay(alignment: .topTrailing) {
            if showsMusic {
                HunSkyMusicToggle()
                    .padding(.top, 14 - Self.cornerLift - 1)
                    .padding(.trailing, 12)
            }
        }
        // A soft glow of the page colour behind the words, so they read on
        // any vista.
        .background(
            RadialGradient(
                colors: [AppTheme.menuBackground.opacity(showsGlow ? (colorScheme == .dark ? 0.55 : 0.7) : 0), AppTheme.menuBackground.opacity(0)],
                center: .center,
                startRadius: 10,
                endRadius: 150
            )
            .blur(radius: 12)
        )
        .animation(.spring(duration: 0.4), value: running.map(\.id))
        // No bounce: the hero's size and place settle together.
        .animation(.smooth(duration: 0.6), value: musicPlaying)
    }

    /// While music plays: what's running, small, up in the corner.
    private var musicHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if focused != nil {
                Text("Focused on")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.7))
                heroText(size: heroSize.small)
                    .opacity(0)
                    .matchedGeometryEffect(id: "heroSmall", in: sky)
            } else {
                if !running.isEmpty {
                    heroText(size: heroSize.small)
                        .opacity(0)
                        .matchedGeometryEffect(id: "heroSmall", in: sky)
                }
                if isEmpty {
                    quietText
                        .opacity(0)
                        .matchedGeometryEffect(id: "quietSmall", in: sky)
                } else {
                    Text(caption)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(crashedCount > 0 && running.isEmpty ? AppTheme.danger : ink.opacity(0.72))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .padding(.leading, -12)
        .padding(.trailing, 24)
        .shadow(color: (colorScheme == .dark ? Color.black : Color.white).opacity(0.35), radius: 14)
    }

    /// The count (or, in Focus, the project's name): drawn once and flown
    /// between the middle of the sky and the corner, so its size and its
    /// place change together and land together.
    private var hero: some View {
        heroText(size: heroSize.big)
            .contentTransition(.numericText())
            .offset(x: focused == nil ? Self.opticalOffset(of: heroWords) * heroSize.big : 0)
            .shadow(color: (colorScheme == .dark ? Color.black : Color.white).opacity(0.35), radius: 14)
            // With nothing running the corner has no number: the 0 shrinks
            // away where it is, quickly, before "all quiet" flies past it;
            // and comes back only once "all quiet" is home beneath it.
            .scaleEffect(musicPlaying && isEmpty ? 0.7 : 1)
            .opacity(musicPlaying && isEmpty ? 0 : 1)
            .animation(musicPlaying ? .easeOut(duration: 0.16) : .smooth(duration: 0.4).delay(0.4), value: musicPlaying)
            .scaleEffect(musicPlaying && !isEmpty ? heroSize.small / heroSize.big : 1)
            .matchedGeometryEffect(id: musicPlaying && !isEmpty ? "heroSmall" : "heroBig", in: sky, properties: .position, isSource: false)
            .allowsHitTesting(false)
    }

    /// Nothing running (and no Focus): the sky shows 0 and "all quiet".
    private var isEmpty: Bool { focused == nil && running.isEmpty }

    /// With nothing running, "all quiet" is what's left in the corner while
    /// music plays: drawn once and flown there from under the 0, and back,
    /// the way the count flies.
    private var quietWords: some View {
        quietText
            .shadow(color: (colorScheme == .dark ? Color.black : Color.white).opacity(0.35), radius: 14)
            .matchedGeometryEffect(id: musicPlaying ? "quietSmall" : "quietBig", in: sky, properties: .position, isSource: false)
            .allowsHitTesting(false)
    }

    private var quietText: some View {
        Text(caption)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(crashedCount > 0 ? AppTheme.danger : ink.opacity(0.72))
            .lineLimit(1)
            .fixedSize()
    }

    /// How far to move a count so it looks centred, as a fraction of its
    /// size. Digits don't sit in the middle of their own space: a 1's flag
    /// takes room on its left, so its stem (which is what the eye centres)
    /// sits right of middle; a 5 leans right too, a 7 left. Each digit's
    /// clear space on the left and right of what the eye sees (for a 1, its
    /// stem), measured in SF Pro Rounded Semibold; a count is centred by
    /// its first digit's left and its last digit's right.
    static func opticalOffset(of count: String) -> CGFloat {
        let margins: [Character: (left: CGFloat, right: CGFloat)] = [
            "0": (0.040, 0.043), "1": (0.230, 0.112), "2": (0.050, 0.035),
            "3": (0.050, 0.046), "4": (0.035, 0.022), "5": (0.065, 0.030),
            "6": (0.040, 0.037), "7": (0.025, 0.033), "8": (0.040, 0.038),
            "9": (0.035, 0.043),
        ]
        guard let first = count.first.flatMap({ margins[$0] }),
              let last = count.last.flatMap({ margins[$0] }) else { return 0 }
        return (last.right - first.left) / 2
    }

    /// The hero's type size at rest and in the corner.
    private var heroSize: (big: CGFloat, small: CGFloat) {
        // The corner count sits a little above "running" (12.5pt), not over it.
        guard let name = focusedName else { return (88, 15) }
        // Long names get smaller to fit across the sky, down to 22pt; past
        // that they're cut in the middle.
        let nominal: CGFloat = name.count > 12 ? 34 : 46
        let fits = Self.heroWidth / (CGFloat(max(name.count, 1)) * 0.58)
        return (min(nominal, max(22, fits)), 13)
    }

    /// The hero's words: the count, or the focused name, cut in the middle
    /// when it won't fit across the sky even at 22pt. Both copies (at rest
    /// and in the corner) show the same characters.
    private var heroWords: String {
        guard let name = focusedName else { return "\(running.count)" }
        let fits = Int(Self.heroWidth / (heroSize.big * 0.58))
        guard name.count > fits, fits > 4 else { return name }
        let head = (fits - 1 + 1) / 2
        return String(name.prefix(head)) + "…" + String(name.suffix(fits - 1 - head))
    }

    private func heroText(size: CGFloat) -> some View {
        Text(verbatim: heroWords)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(ink.opacity(focused == nil ? (colorScheme == .dark ? 0.88 : 0.78) : (colorScheme == .dark ? 0.9 : 0.8)))
            .lineLimit(1)
            .fixedSize()
    }

    /// The sky at rest: today's date and how many projects run, large.
    private var quiet: some View {
        VStack(spacing: 0) {
            Text(focused == nil ? Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)) : "Focused on")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(ink.opacity(0.7))
            heroText(size: heroSize.big)
                .opacity(0)
                .matchedGeometryEffect(id: "heroBig", in: sky)
                .padding(.vertical, focused == nil ? 0 : 8)
                .padding(.top, focused == nil ? -4 : 0)
            Group {
                if isEmpty {
                    quietText
                        .opacity(0)
                        .matchedGeometryEffect(id: "quietBig", in: sky)
                } else {
                    Text(caption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(crashedCount > 0 && running.isEmpty ? AppTheme.danger : ink.opacity(0.72))
                }
            }
            .padding(.top, focused == nil ? -8 : -4)
        }
    }

    private var caption: String {
        let crashed = crashedCount == 0 ? nil : (crashedCount == 1 ? "1 service crashed" : "\(crashedCount) services crashed")
        if let focused {
            let services = focused.services.filter { $0.status == .running }.count
            let up = services == 1 ? "1 service running" : "\(services) services running"
            return [up, crashed].compactMap { $0 }.joined(separator: " · ")
        }
        if running.isEmpty { return crashed ?? "all quiet" }
        return ["running", crashed].compactMap { $0 }.joined(separator: " · ")
    }
}

/// One project on the sill: its icon and name, what it serves, and Hun's
/// switch, which runs or stops it. Click the row to open it in Hun.
private struct MenuSwitchRow: View {
    let project: HunProject
    let pendingAction: HunActionKind?
    /// Force stop for the pending action, once it has run long enough.
    var onForceStop: (() -> Void)?
    let onOpen: () -> Void
    let onRun: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var crashedServices: [HunService] { project.services.filter { $0.status == .crashed } }
    private var anyUp: Bool { project.services.contains { $0.status == .running || $0.status == .starting } }
    /// Still running, even if a service crashed: on, with its ports.
    private var isOn: Bool { project.status == .running || project.status == .starting || (project.status == .crashed && anyUp) }
    /// Nothing left running: the whole project is down.
    private var crashed: Bool { project.status == .crashed && !anyUp }
    /// Running, but some services crashed.
    private var partlyCrashed: Bool { isOn && !crashedServices.isEmpty }

    private var ports: [HunService] {
        project.services.filter { $0.status == .running && $0.port > 0 }.sorted { $0.port < $1.port }
    }

    var body: some View {
        HStack(spacing: 10) {
            ProjectIconView(
                name: project.name, iconPath: project.iconPath, size: 22, cornerRadius: 6, emphasized: false,
                // The switch says running or crashed; the icon stays plain.
                status: nil,
                badgeRim: colorScheme == .dark ? Color(red: 0.05, green: 0.05, blue: 0.055) : AppTheme.menuBackground
            )
            .opacity(isOn || crashed || hovering ? 1 : 0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn || crashed || hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let pendingAction {
                    Text(pendingAction.statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                } else if crashed {
                    Text("Crashed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.danger)
                } else if isOn && (!ports.isEmpty || partlyCrashed) {
                    // A crash is a short count, never a service name, so the
                    // line stays the same size however services are called.
                    HStack(spacing: 4) {
                        if partlyCrashed {
                            Text("\(crashedServices.count) crashed")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(AppTheme.danger)
                                .padding(.horizontal, 5)
                                .frame(height: 17)
                                .background(HunRoundedShape().fill(AppTheme.danger.opacity(0.12)))
                                .fixedSize()
                        }
                        let shown = partlyCrashed ? 1 : 3
                        ForEach(ports.prefix(shown)) { service in
                            MenuPortLink(service: service)
                        }
                        if ports.count > shown {
                            Text("+\(ports.count - shown)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(AppTheme.textTertiary)
                                .fixedSize()
                        }
                    }
                }
            }
            Spacer(minLength: 6)
            if (crashed || partlyCrashed) && pendingAction == nil {
                MenuIconButton(systemImage: "arrow.clockwise", help: "Restart \(project.name)", action: onRestart)
            }
            MenuHunSwitch(
                isOn: isOn || crashed,
                isBusy: pendingAction != nil,
                onForceStop: onForceStop,
                // Dark mode: a deeper green than the bright system one.
                tint: crashed ? AppTheme.danger : (colorScheme == .dark ? Color(red: 0x2A / 255, green: 0x8C / 255, blue: 0x50 / 255) : AppTheme.success),
                help: onForceStop != nil ? "Taking a while? Force stop" : (isOn || crashed ? "Stop \(project.name)" : "Run \(project.name)")
            ) {
                if let onForceStop { onForceStop() } else if isOn || crashed { onStop() } else { onRun() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(HunRoundedShape().fill(hovering ? AppTheme.rowHover : (isOn ? AppTheme.textPrimary.opacity(0.05) : Color.clear)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .accessibilityHint("Open \(project.name) in Hun")
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// A port that opens in the browser.
private struct MenuPortLink: View {
    let service: HunService
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = service.browserURL { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 2) {
                Text(verbatim: ":\(service.port)")
                    .font(.system(size: 10.5, design: .monospaced))
                if hovering {
                    Image(systemName: "arrow.up.right").font(.system(size: 7, weight: .bold))
                }
            }
            .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textTertiary)
            .padding(.horizontal, 5)
            .frame(height: 17)
            .background(HunRoundedShape().fill(hovering ? AppTheme.hover : AppTheme.searchField))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(service.browserURL == nil)
        .onHover { hovering = $0 }
        .accessibilityHint(service.browserURL.map { "Open \(service.name) at \($0.absoluteString)" } ?? service.name)
    }
}

/// Hun's switch, the one in its logo and the menu bar: on runs, off stops.
private struct MenuHunSwitch: View {
    let isOn: Bool
    let isBusy: Bool
    /// Set once a pending action has run long enough: the knob shows the
    /// stop mark and a click force-stops.
    var onForceStop: (() -> Void)?
    let tint: Color
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? tint : AppTheme.textTertiary.opacity(hovering ? 0.4 : 0.28))
                    .frame(width: 34, height: 20)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    .padding(2)
                    .overlay {
                        if isBusy {
                            HunPendingSpinner(stoppable: onForceStop != nil, hovering: hovering, size: 10, tint: Color.black.opacity(0.75))
                        }
                    }
            }
            .frame(width: 34, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy && onForceStop == nil)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.28, bounce: 0.25), value: isOn)
        .accessibilityHint(help)
        .accessibilityLabel(help)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// The bottom of the sill: how projects run, and the way into Hun.
private struct MenuSillFooter: View {
    @Binding var mode: HunMode
    let isModePending: Bool

    var body: some View {
        HStack(spacing: 6) {
            MenuModeSwitch(mode: $mode, isPending: isModePending)
            Spacer(minLength: 8)
            MenuIconButton(systemImage: "macwindow", help: "Open Hun (⌘D)") { hunApp.openDashboard() }
            MenuIconButton(systemImage: "power", help: "Quit Hun (⌘Q)") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

private struct SleekMenuScrollView<Content: View>: View {
    let maxHeight: CGFloat
    let content: Content

    @State private var contentHeight: CGFloat
    @State private var viewportHeight: CGFloat
    @State private var contentOffset: CGFloat = 0
    @State private var hovering = false

    init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
        self._contentHeight = State(initialValue: maxHeight)
        self._viewportHeight = State(initialValue: maxHeight)
    }

    var body: some View {
        AppKitMenuScrollView(
            contentHeight: $contentHeight,
            viewportHeight: $viewportHeight,
            contentOffset: $contentOffset
        ) {
            content
        }
        .frame(height: scrollHeight)
        .overlay(alignment: .trailing) {
            if canScroll && hovering {
                MenuScrollIndicator(
                    viewportHeight: viewportHeight,
                    contentHeight: contentHeight,
                    contentOffset: contentOffset
                )
                .padding(.trailing, 3)
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
    }

    private var canScroll: Bool {
        contentHeight > viewportHeight + 1
    }

    private var scrollHeight: CGFloat {
        min(maxHeight, max(1, contentHeight))
    }
}

private struct AppKitMenuScrollView<Content: View>: NSViewRepresentable {
    @Binding var contentHeight: CGFloat
    @Binding var viewportHeight: CGFloat
    @Binding var contentOffset: CGFloat
    let content: Content

    init(
        contentHeight: Binding<CGFloat>,
        viewportHeight: Binding<CGFloat>,
        contentOffset: Binding<CGFloat>,
        @ViewBuilder content: () -> Content
    ) {
        self._contentHeight = contentHeight
        self._viewportHeight = viewportHeight
        self._contentOffset = contentOffset
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            contentHeight: $contentHeight,
            viewportHeight: $viewportHeight,
            contentOffset: $contentOffset
        )
    }

    func makeNSView(context: Context) -> NoScrollerScrollView {
        let scrollView = NoScrollerScrollView()
        let documentView = FlippedDocumentView(frame: .zero)
        let hostingView = NSHostingView(rootView: content)

        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        documentView.addSubview(hostingView)
        scrollView.documentView = documentView

        context.coordinator.install(
            scrollView: scrollView,
            documentView: documentView,
            hostingView: hostingView
        )

        DispatchQueue.main.async {
            context.coordinator.updateLayout()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NoScrollerScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = content
        scrollView.disableNativeScrollers()

        DispatchQueue.main.async {
            context.coordinator.updateLayout()
        }
    }

    final class Coordinator: NSObject {
        var hostingView: NSHostingView<Content>?

        private weak var scrollView: NoScrollerScrollView?
        private weak var documentView: FlippedDocumentView?
        private var boundsObserver: NSObjectProtocol?
        private var layoutScheduled = false
        private var contentHeight: Binding<CGFloat>
        private var viewportHeight: Binding<CGFloat>
        private var contentOffset: Binding<CGFloat>

        init(
            contentHeight: Binding<CGFloat>,
            viewportHeight: Binding<CGFloat>,
            contentOffset: Binding<CGFloat>
        ) {
            self.contentHeight = contentHeight
            self.viewportHeight = viewportHeight
            self.contentOffset = contentOffset
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func install(
            scrollView: NoScrollerScrollView,
            documentView: FlippedDocumentView,
            hostingView: NSHostingView<Content>
        ) {
            self.scrollView = scrollView
            self.documentView = documentView
            self.hostingView = hostingView
            scrollView.onLayout = { [weak self] in
                self?.scheduleLayout()
            }

            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleLayout()
            }
        }

        func scheduleLayout() {
            guard !layoutScheduled else { return }
            layoutScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.layoutScheduled = false
                self?.updateLayout()
            }
        }

        func updateLayout() {
            guard let scrollView, let documentView, let hostingView else { return }

            scrollView.disableNativeScrollers()

            let viewportSize = scrollView.contentView.bounds.size
            let width = max(1, viewportSize.width)
            hostingView.frame.size.width = width
            let measuredHeight = max(1, hostingView.fittingSize.height)
            let documentHeight = max(measuredHeight, viewportSize.height)

            documentView.frame = NSRect(x: 0, y: 0, width: width, height: documentHeight)
            hostingView.frame = documentView.bounds

            setMetrics(
                contentHeight: measuredHeight,
                viewportHeight: max(1, viewportSize.height),
                contentOffset: -scrollView.contentView.bounds.origin.y
            )
        }

        private func setMetrics(contentHeight: CGFloat, viewportHeight: CGFloat, contentOffset: CGFloat) {
            DispatchQueue.main.async {
                if abs(self.contentHeight.wrappedValue - contentHeight) > 0.5 {
                    self.contentHeight.wrappedValue = contentHeight
                }
                if abs(self.viewportHeight.wrappedValue - viewportHeight) > 0.5 {
                    self.viewportHeight.wrappedValue = viewportHeight
                }
                if abs(self.contentOffset.wrappedValue - contentOffset) > 0.5 {
                    self.contentOffset.wrappedValue = contentOffset
                }
            }
        }
    }
}

private final class NoScrollerScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layout() {
        super.layout()
        disableNativeScrollers()
        onLayout?()
    }

    override func tile() {
        disableNativeScrollers()
        super.tile()
        disableNativeScrollers()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        disableNativeScrollers()
        onLayout?()
    }

    override func flashScrollers() {}

    func disableNativeScrollers() {
        hasVerticalScroller = false
        hasHorizontalScroller = false
        verticalScroller = nil
        horizontalScroller = nil
    }

    private func configure() {
        drawsBackground = false
        borderType = .noBorder
        autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollerStyle = .overlay
        verticalScrollElasticity = .automatic
        horizontalScrollElasticity = .none
        usesPredominantAxisScrolling = true
        contentView.postsBoundsChangedNotifications = true
        disableNativeScrollers()
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private struct MenuScrollIndicator: View {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let contentOffset: CGFloat

    private var trackHeight: CGFloat {
        max(1, viewportHeight - 12)
    }

    private var thumbHeight: CGFloat {
        let proportional = trackHeight * min(1, viewportHeight / max(contentHeight, 1))
        return min(trackHeight, max(44, proportional))
    }

    private var thumbOffset: CGFloat {
        let maxScroll = max(contentHeight - viewportHeight, 1)
        let travel = max(trackHeight - thumbHeight, 0)
        let scrolled = min(max(-contentOffset, 0), maxScroll)
        return (scrolled / maxScroll) * travel
    }

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(
                    Color(nsColor: .labelColor)
                        .opacity(HunScrollStyleMetrics.thumbOpacity)
                )
                .frame(width: HunScrollStyleMetrics.thumbWidth, height: thumbHeight)
                .offset(y: thumbOffset)
        }
        .frame(width: 8, height: viewportHeight)
        .animation(.easeOut(duration: 0.10), value: thumbOffset)
    }
}

// MARK: - Header

private struct MenuModeSwitch: View {
    @Binding var mode: HunMode
    let isPending: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HunMode.allCases, id: \.self) { option in
                let active = mode == option
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { mode = option }
                } label: {
                    Text(option.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(active ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(maxHeight: .infinity)
                        .background(HunRoundedShape().fill(active ? AppTheme.tabActive : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(option.helpText)
            }
        }
        .padding(2)
        .frame(height: 24)
        .background(HunRoundedShape().fill(AppTheme.searchField))
        .disabled(isPending)
        .opacity(isPending ? 0.6 : 1)
    }
}

// MARK: - Rows

private struct MenuSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.textTertiary)
            // Lines up with the project icons below.
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }
}

/// One project. The row opens it in the dashboard; its action (run, switch,
/// stop, restart) appears on hover, and stays while it's in progress.
private struct MenuIconButton: View {
    enum Tone { case neutral, danger }

    let systemImage: String
    let help: String
    var tone: Tone = .neutral
    var isLoading = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .scaleEffect(0.55)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(foreground)
                }
            }
            .frame(width: 24, height: 22)
            .background(HunRoundedShape().fill(background))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering = $0 }
        .accessibilityHint(help)
        .accessibilityLabel(help)
    }

    private var foreground: Color {
        guard hovering else { return AppTheme.textSecondary }
        return tone == .danger ? AppTheme.danger : AppTheme.textPrimary
    }

    private var background: Color {
        guard hovering else { return AppTheme.searchField }
        return tone == .danger ? AppTheme.danger.opacity(0.14) : AppTheme.hover
    }
}

private struct MenuEmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("No projects yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text("Add one from the dashboard to run it from here.")
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Footer

private struct MenuDivider: View {
    var body: some View {
        Rectangle().fill(AppTheme.divider).frame(height: 1)
    }
}

private struct MenuFooter: View {
    @State private var hoveringOpen = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                hunApp.openDashboard()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Open Hun")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer(minLength: 8)
                    Text("⌘D")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(HunRoundedShape().fill(hoveringOpen ? AppTheme.rowHover : Color.clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringOpen = $0 }

            MenuIconButton(systemImage: "power", help: "Quit Hun (⌘Q)") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }
}

#Preview {
    MenuBarView()
        .environment(HunStore(startAutomatically: false))
}
