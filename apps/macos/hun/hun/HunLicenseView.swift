import AppKit
import SwiftUI

struct HunLicensedRootView: View {
    @Environment(HunStore.self) private var store
    @Environment(HunLicenseManager.self) private var license
    @State private var storeStarted = false

    var body: some View {
        Group {
            if license.isLicensed {
                ContentView()
            } else {
                HunLicenseGateView()
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
                Text("Hun needs a license")
                    .font(.system(size: 13, weight: .semibold))
                Text("Open Hun to activate the public beta.")
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
            .background(AppTheme.sidebar)
            .preferredColorScheme(.dark)
        }
    }
}

private struct HunLicenseGateView: View {
    @Environment(HunLicenseManager.self) private var license
    @State private var licenseKey = ""
    @FocusState private var licenseFieldFocused: Bool

    var body: some View {
        ZStack {
            AppTheme.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 48)
                content
                    .frame(maxWidth: 420)
                Spacer(minLength: 48)
            }
            .padding(.horizontal, 32)
        }
        .preferredColorScheme(.dark)
        .background(WindowChromeConfigurator())
        .onAppear {
            if case .needsActivation = license.state {
                licenseFieldFocused = true
            }
        }
        .onChange(of: license.state) { _, state in
            if case .needsActivation = state {
                licenseFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch license.state {
        case .checking:
            statusView(
                title: "Checking your license",
                detail: "This usually takes a moment."
            ) {
                ProgressView().controlSize(.small)
            }
        case .activating:
            statusView(
                title: "Activating Hun",
                detail: "Registering this Mac with your beta license."
            ) {
                ProgressView().controlSize(.small)
            }
        case .expired:
            statusView(
                title: "The public beta has ended",
                detail: "Thanks for testing Hun. Visit hun.sh for the next release."
            ) {
                Button("Visit hun.sh") {
                    NSWorkspace.shared.open(URL(string: "https://hun.sh")!)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
        case let .unavailable(message):
            statusView(title: "Could not verify your license", detail: message) {
                Button("Try again") {
                    Task { await license.retryValidation() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
        case .needsActivation:
            activationForm
        case .active:
            EmptyView()
        }
    }

    private var activationForm: some View {
        VStack(alignment: .leading, spacing: 24) {
            appIdentity

            VStack(alignment: .leading, spacing: 8) {
                Text("Activate the public beta")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Paste the license key from your Dodo Payments email. Beta access is free and ends for everyone on 31 August 2026.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("License key", text: $licenseKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(AppTheme.searchField)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(AppTheme.dividerStrong, lineWidth: 1)
                    }
                    .focused($licenseFieldFocused)
                    .onSubmit(activate)
                    .accessibilityLabel("Hun license key")

                if let error = license.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: activate) {
                    Text("Activate Hun")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.appBackground)
                .background(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(
                    licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? 0.45
                        : 1
                )
                .keyboardShortcut(.defaultAction)
            }

            HStack {
                Button("Get a free beta key") {
                    NSWorkspace.shared.open(license.configuration.checkoutURL)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textSecondary)
                .underline()

                Spacer()

                Text("2 Macs per key")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private var appIdentity: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("hun")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("native macOS workspace")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private func statusView<Actions: View>(
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            actions()
        }
        .frame(maxWidth: .infinity)
    }

    private func activate() {
        Task { await license.activate(licenseKey) }
    }
}
