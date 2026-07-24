import SwiftUI
import DebridUI
import DebridCore

/// Settings card for linking a Trakt account. Trakt is the watch-state source of truth — watched
/// history, resume position, and personal ratings all live there — so an unlinked device shows
/// "Play" instead of "Resume" and empty Continue Watching until this is done.
struct TraktLinkSection: View {
    @Environment(AppSession.self) private var session
    @State private var model: TraktAuthModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Trakt", systemImage: "arrow.triangle.2.circlepath")
                .font(.title3.bold()).foregroundStyle(Theme.Palette.gold)

            if !session.traktConfigured {
                Text("No Trakt API app is configured in this build. Add TRAKT_CLIENT_ID and "
                     + "TRAKT_CLIENT_SECRET to Secrets.xcconfig to enable syncing.")
                    .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
            } else if session.traktLinked {
                Label("Linked — your watch history, resume points, and ratings sync with Trakt.",
                      systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
                Button("Unlink Trakt", role: .destructive) {
                    Task { await session.unlinkTrakt() }
                }
            } else if let model {
                switch model.phase {
                case .awaiting(let code):
                    deviceCode(code)
                case .failed(let message):
                    Text(message).font(.callout).foregroundStyle(Theme.Palette.textSecondary)
                    Button("Try Again") { model.retry() }
                case .linked:
                    Label("Linked!", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(Theme.Palette.gold)
                default:
                    Label("Contacting Trakt…", systemImage: "hourglass")
                        .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
                }
            } else {
                Text("Link your Trakt account to sync watched history, resume position, and ratings "
                     + "across every device.")
                    .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
                Button("Link Trakt") { model = session.makeTraktAuthModel() }
            }
        }
        .frame(maxWidth: 700)
        .padding(40)
        .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: 24))
        // `.task(id:)` restarts the poll when retry() bumps `attempt`.
        .task(id: model?.attempt) {
            guard let model else { return }
            await model.run()
        }
    }

    private func deviceCode(_ code: TraktDeviceCode) -> some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                Text("On your phone or computer, go to")
                    .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
                Text(displayURL(code.verificationURL))
                    .font(.title3.bold()).foregroundStyle(Theme.Palette.textPrimary)
                Text("and enter this code:")
                    .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
                Text(code.userCode)
                    .font(.system(size: 56, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Label("Waiting for authorization…", systemImage: "hourglass")
                    .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
            }
            if let qr = QRCode.image(from: code.verificationURL) {
                qr.resizable().interpolation(.none).scaledToFit()
                    .frame(width: 180, height: 180).padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func displayURL(_ raw: String) -> String {
        raw.replacingOccurrences(of: "https://", with: "")
           .replacingOccurrences(of: "http://", with: "")
    }
}
