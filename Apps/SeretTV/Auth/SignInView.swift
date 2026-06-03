import DebridCore
import SwiftUI

/// The device-code sign-in screen. Renders `SignInModel.phase`; runs the flow via
/// `.task(id: model.attempt)` so it auto-cancels on disappear and restarts on retry.
struct SignInView: View {
    let model: SignInModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .idle, .requestingCode:
                ProgressView("Preparing sign‑in…")
                    .font(.title2)
            case .awaitingAuthorization(let code):
                deviceCode(code)
            case .signedIn:
                ProgressView("Signing in…")
                    .font(.title2)
            case .failed(let message):
                failure(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: model.attempt) { await model.run() }
    }

    private func deviceCode(_ code: RDDeviceCode) -> some View {
        VStack(spacing: 48) {
            Text("Sign in to Real‑Debrid")
                .font(.largeTitle.bold())
            HStack(alignment: .center, spacing: 80) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("On your phone or computer, go to")
                        .font(.title3).foregroundStyle(.secondary)
                    Text(displayURL(code.verificationURL))
                        .font(.title.bold())
                    Text("and enter this code:")
                        .font(.title3).foregroundStyle(.secondary)
                    Text(code.userCode)
                        .font(.system(size: 96, weight: .heavy, design: .monospaced))
                }
                if let qr = QRCode.image(from: code.verificationURL) {
                    qr.resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 300, height: 300)
                        .padding(20)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            Label("Waiting for authorization…", systemImage: "hourglass")
                .font(.title3).foregroundStyle(.secondary)
        }
        .padding(80)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 32) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 72)).foregroundStyle(.yellow)
            Text(message)
                .font(.title2).multilineTextAlignment(.center).frame(maxWidth: 800)
            Button("Try Again") { model.retry() }
                .font(.title3)
        }
        .padding(80)
    }

    /// "https://real-debrid.com/device" → "real-debrid.com/device".
    private func displayURL(_ raw: String) -> String {
        guard let comps = URLComponents(string: raw), let host = comps.host else { return raw }
        // Keep any query (RD's URL has none today, but don't render an incomplete URL if it adds one).
        return host + comps.path + (comps.query.map { "?\($0)" } ?? "")
    }
}
