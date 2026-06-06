import DebridCore
import DebridUI
import SwiftUI

/// Touch sign-in, Gold Glass. Default: device-code — show the code and open Real‑Debrid in an
/// in-app browser. Fallback: paste a personal API token (the durable path past the throttle).
struct SignInView: View {
    let model: SignInModel
    @State private var showingTokenEntry = false
    @State private var tokenText = ""
    @State private var presentedURL: PresentedURL?

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(spacing: Theme.Space.lg) {
                    Wordmark(hebrewSize: 58).padding(.top, 64)
                    Text("Your debrid library, everywhere.")
                        .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                    Group {
                        if showingTokenEntry {
                            tokenEntry
                        } else {
                            switch model.phase {
                            case .idle, .requestingCode: preparing("Preparing sign‑in…")
                            case .awaitingAuthorization(let code): deviceCode(code)
                            case .validatingToken: preparing("Checking token…")
                            case .signedIn: preparing("Signing in…")
                            case .failed(let message): failure(message)
                            }
                        }
                    }
                    .padding(.top, Theme.Space.xl)
                }
                .frame(maxWidth: 460).frame(maxWidth: .infinity)
                .padding(Theme.Space.xl)
            }
        }
        .task(id: model.attempt) { await model.run() }
        .sheet(item: $presentedURL) { SafariSheet(url: $0.url) }
    }

    private func preparing(_ label: String) -> some View {
        VStack(spacing: Theme.Space.md) {
            ProgressView().tint(Theme.Palette.gold)
            Text(label).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private func deviceCode(_ code: RDDeviceCode) -> some View {
        VStack(spacing: Theme.Space.lg) {
            Text("Enter this code at Real‑Debrid")
                .font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textSecondary)
            Text(code.userCode)
                .font(.system(size: 44, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.Palette.gold).textSelection(.enabled)
                .goldGlow(12, opacity: 0.35)
            Button {
                if let url = URL(string: code.verificationURL) { presentedURL = PresentedURL(url: url) }
            } label: {
                Label("Open Real‑Debrid", systemImage: "safari").frame(maxWidth: .infinity)
            }
            .buttonStyle(GoldButtonStyle())
            Label("Waiting for authorization…", systemImage: "hourglass")
                .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textTertiary)
            Button("Use a Real‑Debrid token instead") { showingTokenEntry = true }
                .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.gold)
        }
    }

    private var tokenEntry: some View {
        VStack(spacing: Theme.Space.lg) {
            Text("Paste your token").font(Theme.Typo.title()).foregroundStyle(Theme.Palette.textPrimary)
            Text("Get it at real‑debrid.com/apitoken")
                .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
            SecureField("Real‑Debrid API token", text: $tokenText)
                .textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(Theme.Space.md)
                .background(Theme.Palette.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                .foregroundStyle(Theme.Palette.textPrimary)
            if case .validatingToken = model.phase { ProgressView().tint(Theme.Palette.gold) }
            if case .failed(let message) = model.phase {
                Text(message).font(Theme.Typo.body()).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button { Task { await model.signInWithToken(tokenText) } } label: {
                Text("Sign In").frame(maxWidth: .infinity)
            }
            .buttonStyle(GoldButtonStyle()).disabled(tokenText.isEmpty)
            Button("Back") { showingTokenEntry = false }
                .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: Theme.Space.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44)).foregroundStyle(Theme.Palette.gold)
            Text(message).multilineTextAlignment(.center)
                .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
            VStack(spacing: Theme.Space.md) {
                Button { model.retry() } label: { Text("Try Again").frame(maxWidth: .infinity) }
                    .buttonStyle(GoldButtonStyle())
                Button("Use a token") { showingTokenEntry = true }.buttonStyle(GhostButtonStyle())
            }
        }
    }
}
