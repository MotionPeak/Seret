import DebridCore
import DebridUI
import SwiftUI

/// The sign-in screen. Default: device-code. Secondary: paste a personal API token
/// (real-debrid.com/apitoken), which bypasses the throttled device-code endpoint.
struct SignInView: View {
    let model: SignInModel

    var body: some View {
        SignInContent(phase: model.phase,
                      onRetry: { model.retry() },
                      onSubmitToken: { token in Task { await model.signInWithToken(token) } })
            .task(id: model.attempt) { await model.run() }
    }
}

/// What the sign-in screen draws for a phase — split from `SignInView` so the `-uiPreview signin`
/// harness can show each state without a model (whose flow is the real, throttled RD endpoint).
struct SignInContent: View {
    let phase: SignInModel.Phase
    let onRetry: () -> Void
    let onSubmitToken: (String) -> Void
    @State private var showingTokenEntry: Bool
    @State private var tokenText = ""

    init(phase: SignInModel.Phase, showingTokenEntry: Bool = false,
         onRetry: @escaping () -> Void, onSubmitToken: @escaping (String) -> Void) {
        self.phase = phase
        self.onRetry = onRetry
        self.onSubmitToken = onSubmitToken
        _showingTokenEntry = State(initialValue: showingTokenEntry)
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            if showingTokenEntry {
                tokenEntry
            } else {
                switch phase {
                case .idle, .requestingCode:
                    SeretLoader(label: "Preparing sign‑in…")
                case .awaitingAuthorization(let code):
                    deviceCode(code)
                case .validatingToken:
                    SeretLoader(label: "Checking token…")
                case .signedIn:
                    SeretLoader(label: "Signing in…")
                case .failed(let message):
                    failure(message)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deviceCode(_ code: RDDeviceCode) -> some View {
        VStack(spacing: 56) {
            Wordmark(hebrewSize: 64)
            HStack(alignment: .center, spacing: 80) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("On your phone or computer, go to")
                        .calloutText().foregroundStyle(Theme.Palette.textSecondary)
                    Text(displayURL(code.verificationURL))
                        .screenTitle().foregroundStyle(Theme.Palette.textPrimary)
                    Text("and enter this code:")
                        .calloutText().foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.top, 6)
                    Text(code.userCode)
                        .font(.system(size: 96, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                if let qr = QRCode.image(from: code.verificationURL) {
                    qr.resizable().interpolation(.none).scaledToFit()
                        .frame(width: 300, height: 300).padding(20)
                        // White is the QR's own ground, not chrome: a scanner needs the contrast.
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            VStack(spacing: 28) {
                Label("Waiting for authorization…", systemImage: "hourglass")
                    .calloutText().foregroundStyle(Theme.Palette.textSecondary)
                Button("Use a Real‑Debrid token instead") { showingTokenEntry = true }
                    .buttonStyle(SeretActionButtonStyle())
            }
        }
        .padding(80)
    }

    private var tokenEntry: some View {
        VStack(spacing: 28) {
            Text("Sign in with a token").screenTitle().foregroundStyle(Theme.Palette.textPrimary)
            Text("Get your token at real‑debrid.com/apitoken, then paste it here.")
                .calloutText().foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 800)
            SecureField("Real‑Debrid API token", text: $tokenText)
                .textContentType(.password)
                .frame(maxWidth: 700)
            if case .validatingToken = phase { ProgressView().tint(Theme.Palette.textPrimary) }
            if case .failed(let message) = phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .calloutText().foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center).frame(maxWidth: 700)
            }
            HStack(spacing: 24) {
                Button("Sign In") { onSubmitToken(tokenText) }
                    .buttonStyle(SeretActionButtonStyle(prominent: true))
                    .disabled(tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Use a code instead") { showingTokenEntry = false }
                    .buttonStyle(SeretActionButtonStyle())
            }
            .padding(.top, 8)
        }
        .padding(80)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 32) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 72)).foregroundStyle(Theme.Palette.textSecondary)
            Text(message).sectionTitle().foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center).frame(maxWidth: 800)
            HStack(spacing: 24) {
                Button("Try Again", action: onRetry)
                    .buttonStyle(SeretActionButtonStyle(prominent: true))
                Button("Use a Real‑Debrid token instead") { showingTokenEntry = true }
                    .buttonStyle(SeretActionButtonStyle())
            }
        }
        .padding(80)
    }

    /// "https://real-debrid.com/device" → "real-debrid.com/device".
    private func displayURL(_ raw: String) -> String {
        guard let comps = URLComponents(string: raw), let host = comps.host else { return raw }
        return host + comps.path + (comps.query.map { "?\($0)" } ?? "")
    }
}
