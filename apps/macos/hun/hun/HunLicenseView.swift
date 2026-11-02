import AppKit
import SwiftUI

struct HunLicensedRootView: View {
    @Environment(HunStore.self) private var store
    @Environment(HunLicenseManager.self) private var license
    @State private var storeStarted = false
    @AppStorage(HunOnboarding.completedKey) private var onboardingDone = false
    /// Without a license (never activated, deactivated, a beta key that
    /// ended, or one that can't be checked), Hun opens the welcome, which
    /// unlocks it. Once open, it stays open until it's finished.
    @State private var welcomeOpen = false

    var body: some View {
        ZStack {
            if !onboardingDone || welcomeOpen {
                HunOnboardingView(onFinish: {
                    onboardingDone = true
                    welcomeOpen = false
                })
                .ignoresSafeArea()
                .transition(.opacity)
            } else if license.isLicensed {
                ContentView()
                    .transition(.opacity)
            } else {
                // Checking the license at launch: a moment, so just the canvas.
                Color.clear
            }
        }
        .background(AppTheme.appBackground)
        .onChange(of: license.state, initial: true) { _, state in
            switch state {
            case .needsActivation, .unavailable:
                welcomeOpen = true
            default:
                break
            }
        }
        .task {
            await license.restore()
        }
        .task(id: license.isLicensed) {
            guard license.isLicensed, !storeStarted else { return }
            storeStarted = true
            await store.start()
        }
    }
}

struct HunLicenseMenuBarView: View {
    @Environment(HunLicenseManager.self) private var license

    var body: some View {
        if license.isLicensed {
            MenuBarView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(license.betaEnded ? "The Hun beta has ended" : "Hun needs a license")
                    .font(.system(size: 13, weight: .semibold))
                Text(license.betaEnded ? "Open Hun to buy a license." : "Open Hun to activate your license.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textSecondary)
                Button("Open Hun") {
                    hunApp.openDashboard()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)
            }
            .padding(14)
            .frame(width: 260, alignment: .leading)
            .background(AppTheme.menuBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.dividerStrong, lineWidth: 1))
        }
    }
}
