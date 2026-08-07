import SwiftUI
import DebridUI
import DebridCore

/// Settings card for linking a Trakt account. Trakt is a MIRROR, not the source of truth: watched
/// history, resume position and ratings live on-device and sync between devices over CloudKit, so
/// Continue Watching and Resume work fully with Trakt unlinked, throttled, or gone. Linking only
/// pushes that state outward to trakt.tv as well.
struct TraktLinkSection: View {
    @Environment(AppSession.self) private var session
    @State private var model: TraktAuthModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Trakt", systemImage: "arrow.triangle.2.circlepath")
                .font(.seret(.title3, .bold)).foregroundStyle(Theme.Palette.gold)

            if !session.traktConfigured {
                Text("No Trakt API app is configured in this build. Add TRAKT_CLIENT_ID and "
                     + "TRAKT_CLIENT_SECRET to Secrets.xcconfig to enable syncing.")
                    .font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
            } else if session.traktLinked {
                Label("Linked — what you watch and rate here is mirrored to Trakt as well.",
                      systemImage: "checkmark.circle.fill")
                    .font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
                // Reads fetch once per launch, so anything changed on Trakt since (rated on the
                // web, watched on another device) needs an explicit re-read.
                HStack(spacing: 20) {
                    Button(syncing ? "Syncing…" : "Sync Now") {
                        Task { await session.syncTraktNow() }
                    }
                    .disabled(syncing)
                    Button("Unlink Trakt", role: .destructive) {
                        Task { await session.unlinkTrakt() }
                    }
                }
                syncStatus
            } else if let model {
                switch model.phase {
                case .awaiting(let code):
                    deviceCode(code)
                case .failed(let message):
                    Text(message).font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
                    Button("Try Again") { model.retry() }
                case .linked:
                    Label("Linked!", systemImage: "checkmark.circle.fill")
                        .font(.seretCallout).foregroundStyle(Theme.Palette.gold)
                default:
                    Label("Contacting Trakt…", systemImage: "hourglass")
                        .font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
                }
            } else {
                Text("Your watch history, resume points and ratings are already kept on this device "
                     + "and synced across your devices. Link Trakt to mirror them to trakt.tv too.")
                    .font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
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

    private var syncing: Bool { session.traktSyncState == .syncing }

    /// The counts distinguish "Trakt returned nothing" from "it returned plenty but a screen still
    /// looks empty" — otherwise that's pure guesswork from the couch.
    @ViewBuilder private var syncStatus: some View {
        switch session.traktSyncState {
        case .idle, .syncing:
            EmptyView()
        case let .succeeded(ratings, watched):
            Label("\(ratings) ratings · \(watched) watched", systemImage: "checkmark.circle")
                .font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private func deviceCode(_ code: TraktDeviceCode) -> some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                Text("On your phone or computer, go to")
                    .font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
                Text(displayURL(code.verificationURL))
                    .font(.seret(.title3, .bold)).foregroundStyle(Theme.Palette.textPrimary)
                Text("and enter this code:")
                    .font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
                Text(code.userCode)
                    .font(.system(size: 56, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Label("Waiting for authorization…", systemImage: "hourglass")
                    .font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
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
