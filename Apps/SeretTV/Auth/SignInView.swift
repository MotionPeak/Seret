import DebridCore
import DebridUI
import SwiftUI

/// The sign-in screen. Default: device-code. Secondary: paste a personal API token
/// (real-debrid.com/apitoken), which bypasses the throttled device-code endpoint.
struct SignInView: View {
    let model: SignInModel
    @State private var showingTokenEntry = false
    @State private var tokenText = ""

    var body: some View {
        ZStack {
            CanvasBackground()
            if showingTokenEntry {
                tokenEntry
            } else {
                switch model.phase {
                case .idle, .requestingCode:
                    ProgressView("Preparing sign‑in…").font(.title2)
                case .awaitingAuthorization(let code):
                    deviceCode(code)
                case .validatingToken:
                    ProgressView("Checking token…").font(.title2)
                case .signedIn:
                    ProgressView("Signing in…").font(.title2)
                case .failed(let message):
                    failure(message)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: model.attempt) { await model.run() }
    }

    private func deviceCode(_ code: RDDeviceCode) -> some View {
        VStack(spacing: 48) {
            Wordmark(hebrewSize: 64)
            HStack(alignment: .center, spacing: 80) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("On your phone or computer, go to")
                        .font(.title3).foregroundStyle(.secondary)
                    Text(displayURL(code.verificationURL)).font(.title.bold())
                    Text("and enter this code:").font(.title3).foregroundStyle(.secondary)
                    Text(code.userCode)
                        .font(.system(size: 96, weight: .heavy, design: .monospaced))
                }
                if let qr = QRCode.image(from: code.verificationURL) {
                    qr.resizable().interpolation(.none).scaledToFit()
                        .frame(width: 300, height: 300).padding(20)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            Label("Waiting for authorization…", systemImage: "hourglass")
                .font(.title3).foregroundStyle(.secondary)
            Button("Use a Real‑Debrid token instead") { showingTokenEntry = true }
                .font(.title3)
        }
        .padding(80)
    }

    private var tokenEntry: some View {
        VStack(spacing: 28) {
            Text("Sign in with a token").font(.largeTitle.bold())
            Text("Get your token at real‑debrid.com/apitoken, then paste it here.")
                .font(.title3).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 800)
            SecureField("Real‑Debrid API token", text: $tokenText)
                .textContentType(.password)
                .frame(maxWidth: 700)
            if case .validatingToken = model.phase { ProgressView() }
            if case .failed(let message) = model.phase {
                Text(message).font(.callout).foregroundStyle(.orange)
                    .multilineTextAlignment(.center).frame(maxWidth: 700)
            }
            HStack(spacing: 24) {
                Button("Sign In") { Task { await model.signInWithToken(tokenText) } }
                    .disabled(tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Use a code instead") { showingTokenEntry = false }
            }
            .font(.title3)
        }
        .padding(80)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 32) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 72)).foregroundStyle(Theme.Palette.gold)
            Text(message).font(.title2).multilineTextAlignment(.center).frame(maxWidth: 800)
            HStack(spacing: 24) {
                Button("Try Again") { model.retry() }
                Button("Use a Real‑Debrid token instead") { showingTokenEntry = true }
            }
            .font(.title3)
        }
        .padding(80)
    }

    /// "https://real-debrid.com/device" → "real-debrid.com/device".
    private func displayURL(_ raw: String) -> String {
        guard let comps = URLComponents(string: raw), let host = comps.host else { return raw }
        return host + comps.path + (comps.query.map { "?\($0)" } ?? "")
    }
}
