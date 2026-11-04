import AppKit
import SwiftUI

// What's new, once, on the first launch after an update. A release with
// something new gets a card over the dashboard; one with only fixes and
// improvements gets a small notice at the bottom instead. The words come from
// the website's changelog (website/content/changelog.json), which the build
// copies into the app, so the card, Sparkle's notes and hun.sh always agree.

struct HunRelease: Decodable, Identifiable, Equatable {
    struct Group: Decodable, Equatable {
        let title: String
        let changes: [String]
    }

    let version: String
    let date: String
    let title: String
    let summary: String
    let groups: [Group]

    var id: String { version }

    func changes(_ group: String) -> [String] {
        groups.first { $0.title == group }?.changes ?? []
    }

    /// Something new, worth a card; otherwise a notice will do.
    var hasNew: Bool { !changes("New").isEmpty }

    var changelogURL: URL { URL(string: "https://hun.sh/changelog#v\(version)")! }

    /// "2 November".
    var displayDate: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let day = parser.date(from: date) else { return date }
        return day.formatted(.dateTime.day().month(.wide))
    }
}

@MainActor
@Observable
final class HunWhatsNew {
    static let shared = HunWhatsNew()
    static let lastSeenKey = "hun.whatsNew.lastSeenVersion"

    enum Presentation: Equatable {
        /// Newest first.
        case card([HunRelease])
        case notice([HunRelease])
    }

    var presentation: Presentation?

    let releases: [HunRelease]
    let currentVersion: String
    /// Whether this Mac had finished the welcome before this launch: a fresh
    /// install hasn't, and its first launch isn't an update.
    private let wasSetUp: Bool
    private var checked = false
    private var noticeTask: Task<Void, Never>?

    private init() {
        let url = Bundle.main.url(forResource: "Changelog", withExtension: "json")
        releases = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([HunRelease].self, from: $0) } ?? []
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        wasSetUp = UserDefaults.standard.bool(forKey: HunOnboarding.completedKey)
    }

    /// The dashboard is up: show what's new if Hun was updated since it was
    /// last open. Runs once per launch.
    func checkAfterLaunch() {
        guard !checked else { return }
        checked = true
        let defaults = UserDefaults.standard
        let lastSeen = defaults.string(forKey: Self.lastSeenKey)
        defaults.set(currentVersion, forKey: Self.lastSeenKey)
        guard wasSetUp, lastSeen != currentVersion else { return }
        let since = releases(after: lastSeen)
        guard !since.isEmpty else { return }
        Task {
            // Let the window settle first.
            try? await Task.sleep(for: .seconds(0.7))
            present(since)
        }
    }

    /// Releases after `version` up to this one, newest first.
    func releases(after version: String?) -> [HunRelease] {
        Self.pending(releases, current: currentVersion, lastSeen: version)
    }

    /// The last version without What's new. A Mac that was set up but has no
    /// version recorded came from it or earlier: every later version records
    /// itself.
    nonisolated static let lastVersionBeforeWhatsNew = "0.5.1"

    /// What to show after an update: every release after the one last seen,
    /// up to the running one, newest first. With none recorded, everything
    /// since the last version without What's new, so someone jumping from
    /// 0.5.x straight to a later version still hears about 0.6.0.
    nonisolated static func pending(_ all: [HunRelease], current: String, lastSeen: String?) -> [HunRelease] {
        let since = lastSeen ?? lastVersionBeforeWhatsNew
        return all.filter { compare($0.version, current) <= 0 && compare($0.version, since) > 0 }
    }

    /// The release a card leads with: the newest one with something new (after
    /// skipped versions, the big one, not the fixes that followed); the rest fold.
    nonisolated static func lead(of releases: [HunRelease]) -> HunRelease? {
        releases.first(where: \.hasNew) ?? releases.first
    }

    func present(_ releases: [HunRelease]) {
        guard !releases.isEmpty else { return }
        if releases.contains(where: \.hasNew) {
            presentation = .card(releases)
        } else {
            presentation = .notice(releases)
            noticeTask?.cancel()
            noticeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled, let self, case .notice = self.presentation else { return }
                self.presentation = nil
            }
        }
    }

    /// This version's card, from Settings.
    func showCurrent() {
        if let release = releases.first(where: { $0.version == currentVersion }) ?? releases.first {
            presentation = .card([release])
        }
    }

    func dismiss() {
        noticeTask?.cancel()
        presentation = nil
    }

    nonisolated static func compare(_ a: String, _ b: String) -> Int {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }
}

// MARK: - Host

/// Sits over the dashboard: the card with its dimmed backdrop, or the notice.
struct HunWhatsNewHost: View {
    private let whatsNew = HunWhatsNew.shared

    var body: some View {
        ZStack {
            if case .card(let releases) = whatsNew.presentation {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial).opacity(0.7)
                    Color.black.opacity(0.18)
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { whatsNew.dismiss() }
                .transition(.opacity)

                HunWhatsNewCard(releases: releases, onClose: { whatsNew.dismiss() })
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 16)),
                        removal: .opacity.combined(with: .scale(scale: 0.98))
                    ))
            }
            if case .notice(let releases) = whatsNew.presentation {
                HunWhatsNewNotice(releases: releases)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.12), value: whatsNew.presentation)
    }
}

// MARK: - Card

struct HunWhatsNewCard: View {
    let releases: [HunRelease]
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HunMenuLook.lightVistaKey) private var lightVista = HunMenuLook.defaultLightVista.rawValue
    @AppStorage(HunMenuLook.darkVistaKey) private var darkVista = HunMenuLook.defaultDarkVista.rawValue
    @State private var shown = false
    @State private var drift = false
    @State private var showsFixes = false
    @State private var openOlder: Set<String> = []

    private var latest: HunRelease { HunWhatsNew.lead(of: releases) ?? releases[0] }
    private var older: [HunRelease] { releases.filter { $0 != latest } }
    private var scene: HunMenuLook.Scene {
        colorScheme == .dark ? HunMenuLook.vista(named: darkVista, dark: true) : HunMenuLook.vista(named: lightVista, dark: false)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    changes(of: latest, from: 0)
                    if !older.isEmpty { olderReleases }
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .hunScrollStyle()
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
            // A soft edge where the list runs on below.
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [AppTheme.dialogBackground.opacity(0), AppTheme.dialogBackground], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                    .allowsHitTesting(false)
            }
            footer
        }
        .frame(width: 480)
        .background(AppTheme.dialogBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(AppTheme.floatingBorder, lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18), radius: 40, y: 18)
        .background {
            Button("", action: onClose).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)
        }
        .onAppear {
            shown = true
            drift = true
        }
    }

    // The person's own vista, drifting, fading into the card; the release's
    // title and summary below it.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                HunVistaImage(scene: scene)
                    .scaleEffect(drift ? 1.08 : 1, anchor: .center)
                    .animation(.linear(duration: 26).repeatForever(autoreverses: true), value: drift)
                LinearGradient(
                    stops: [
                        .init(color: AppTheme.dialogBackground.opacity(0), location: 0.35),
                        .init(color: AppTheme.dialogBackground, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                HStack(spacing: 7) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text("Hun \(latest.version)")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("·").foregroundStyle(AppTheme.textTertiary)
                    Text(latest.displayDate)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.leading, 6)
                .padding(.trailing, 10)
                .frame(height: 28)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(AppTheme.floatingBorder, lineWidth: 1))
                .padding(18)
            }
            .frame(height: 150)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text("What's new")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(latest.title)
                    .font(HunFonts.display(size: 28))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(latest.summary)
                    .font(.system(size: 13.5))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.top, -26)
            .padding(.bottom, 20)
            .modifier(Reveal(shown: shown, step: 0))
        }
    }

    /// One release's changes: New given room, Improved compact, Fixes folded.
    @ViewBuilder
    private func changes(of release: HunRelease, from step: Int) -> some View {
        let new = release.changes("New"), improved = release.changes("Improved"), fixes = release.changes("Fixes")
        VStack(alignment: .leading, spacing: 20) {
            if !new.isEmpty {
                group("New", tint: AppTheme.accent) {
                    ForEach(Array(new.enumerated()), id: \.offset) { index, change in
                        item(change, dot: AppTheme.accent, size: 13, color: AppTheme.textPrimary)
                            .modifier(Reveal(shown: shown, step: step + 1 + index))
                    }
                }
            }
            if !improved.isEmpty {
                group("Improved", tint: AppTheme.textTertiary) {
                    ForEach(Array(improved.enumerated()), id: \.offset) { index, change in
                        item(change, dot: AppTheme.textTertiary, size: 12.5, color: AppTheme.textSecondary)
                            .modifier(Reveal(shown: shown, step: step + 1 + new.count + index))
                    }
                }
            }
            if !fixes.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Button {
                        withAnimation(.spring(duration: 0.35, bounce: 0.1)) { showsFixes.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(fixes.count == 1 ? "And 1 fix" : "And \(fixes.count) fixes")
                                .font(.system(size: 12.5, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(showsFixes ? 90 : 0))
                        }
                        .foregroundStyle(AppTheme.textSecondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showsFixes {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(fixes.enumerated()), id: \.offset) { _, change in
                                item(change, dot: AppTheme.textTertiary, size: 12.5, color: AppTheme.textSecondary)
                            }
                        }
                        .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
                .modifier(Reveal(shown: shown, step: step + 1 + new.count + improved.count))
            }
        }
    }

    /// Releases skipped on the way here, folded to a line each.
    private var olderReleases: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(AppTheme.divider).frame(height: 1)
            Text("Also since you last updated")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.top, 6)
            ForEach(older) { release in
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                            if openOlder.contains(release.version) { openOlder.remove(release.version) } else { openOlder.insert(release.version) }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(release.version)
                                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(AppTheme.textTertiary)
                                .frame(width: 38, alignment: .leading)
                            Text(release.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AppTheme.textTertiary)
                                .rotationEffect(.degrees(openOlder.contains(release.version) ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if openOlder.contains(release.version) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array((release.changes("New") + release.changes("Improved")).enumerated()), id: \.offset) { _, change in
                                item(change, dot: AppTheme.textTertiary, size: 12.5, color: AppTheme.textSecondary)
                            }
                        }
                        .padding(.leading, 48)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
            }
        }
        .modifier(Reveal(shown: shown, step: 6))
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AppTheme.divider).frame(height: 1)
            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(latest.changelogURL)
                } label: {
                    HStack(spacing: 5) {
                        Text("Full changelog")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                Spacer()
                Button(action: onClose) {
                    Text("Continue")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 32)
                        .background(HunRoundedShape().fill(AppTheme.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(HunPressStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private func group<Content: View>(_ title: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 10) { content() }
        }
    }

    private func item(_ text: String, dot: Color, size: CGFloat, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(dot).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(text)
                .font(.system(size: size))
                .foregroundStyle(color)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Rows come in one after another, quickly: a fade and a few points' rise.
private struct Reveal: ViewModifier {
    let shown: Bool
    let step: Int

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .animation(.smooth(duration: 0.45).delay(0.12 + Double(min(step, 10)) * 0.04), value: shown)
    }
}

private struct HunPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Notice

/// For releases with only fixes and improvements: one line at the bottom of
/// the window, gone by itself after a few seconds.
struct HunWhatsNewNotice: View {
    let releases: [HunRelease]
    @Environment(\.colorScheme) private var colorScheme
    private let whatsNew = HunWhatsNew.shared

    private var latest: HunRelease { releases[0] }
    private var detail: String {
        let fixes = releases.reduce(0) { $0 + $1.changes("Fixes").count }
        let improved = releases.reduce(0) { $0 + $1.changes("Improved").count }
        var parts: [String] = []
        if improved > 0 { parts.append(improved == 1 ? "1 improvement" : "\(improved) improvements") }
        if fixes > 0 { parts.append(fixes == 1 ? "1 fix" : "\(fixes) fixes") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 20, height: 20)
            HStack(spacing: 5) {
                Text("Updated to Hun \(latest.version)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                if !detail.isEmpty {
                    Text("· \(detail)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Button {
                whatsNew.presentation = .card(releases)
            } label: {
                Text("See what's new")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { whatsNew.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background(Capsule().fill(AppTheme.dialogRaised.opacity(0.92)))
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(AppTheme.floatingBorder, lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 18, y: 6)
    }
}
