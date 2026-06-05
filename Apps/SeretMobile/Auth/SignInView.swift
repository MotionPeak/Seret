import DebridCore
import DebridUI
import SwiftUI

/// Touch sign-in. Default: device-code — show the code and open Real‑Debrid in an in-app
/// browser (no QR, you're already on the device). Fallback: paste a personal API token
/// (real-debrid.com/apitoken), the durable path past the device-code throttle.
struct SignInView: View {
    let model: SignInModel
    @State private var showingTokenEntry = false
    @State private var tokenText = ""
    @State private var presentedURL: PresentedURL?

    var body: some View {
        NavigationStack {
            Group {
                if showingTokenEntry {
                    tokenEntry
                } else {
                    switch model.phase {
                    case .idle, .requestingCode:
                        ProgressView("Preparing sign‑in…")
                    case .awaitingAuthorization(let code):
                        deviceCode(code)
                    case .validatingToken:
                        ProgressView("Checking token…")
                    case .signedIn:
                        ProgressView("Signing in…")
                    case .failed(let message):
                        failure(message)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: model.attempt) { await model.run() }
        .sheet(item: $presentedURL) { SafariSheet(url: $0.url) }
    }

    private func deviceCode(_ code: RDDeviceCode) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "play.tv").font(.system(size: 52)).foregroundStyle(.secondary)
            Text("Sign in to Real‑Debrid").font(.title.bold())
            VStack(spacing: 8) {
                Text("Open Real‑Debrid and enter this code:")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(code.userCode)
                    .font(.system(size: 44, weight: .heavy, design: .monospaced))
                    .textSelection(.enabled)
            }
            Button {
                if let url = URL(string: code.verificationURL) { presentedURL = PresentedURL(url: url) }
            } label: {
                Label("Open Real‑Debrid", systemImage: "safari").font(.headline)
            }
            .buttonStyle(.borderedProminent)
            Label("Waiting for authorization…", systemImage: "hourglass")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Use a Real‑Debrid token instead") { showingTokenEntry = true }
                .font(.subheadline)
        }
    }

    private var tokenEntry: some View {
        VStack(spacing: 20) {
            Text("Sign in with a token").font(.title.bold())
            Text("Get your token at real‑debrid.com/apitoken, then paste it here.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            SecureField("Real‑Debrid API token", text: $tokenText)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
            if case .validatingToken = model.phase { ProgressView() }
            if case .failed(let message) = model.phase {
                Text(message).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button("Sign In") { Task { await model.signInWithToken(tokenText) } }
                .buttonStyle(.borderedProminent)
                .disabled(tokenText.isEmpty)
            Button("Back") { showingTokenEntry = false }.font(.subheadline)
        }
        .frame(maxWidth: 460)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48)).foregroundStyle(.yellow)
            Text(message).multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button("Try Again") { model.retry() }.buttonStyle(.borderedProminent)
                Button("Use a token") { showingTokenEntry = true }
            }
        }
    }
}
