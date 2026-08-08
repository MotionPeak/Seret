import SwiftUI
import DebridUI

/// OpenSubtitles sign-in, with the typing moved to the viewer's phone.
///
/// A QR is the primary path because entering a password on a TV remote is miserable, and
/// OpenSubtitles offers no device-code flow to lean on the way Real-Debrid does — so the Apple TV
/// serves the form itself (see `LocalPairingServer`) and the QR is just its address. The on-screen
/// fields remain as a fallback, collapsed by default so they do not compete with the QR.
struct OpenSubtitlesSection: View {
    @Bindable var model: SettingsModel
    @State private var server: LocalPairingServer?
    @State private var showingManualEntry = false

    var body: some View {
        SettingsCard(title: "Subtitle downloads", icon: "captions.bubble.fill") {
            if model.isConnected {
                connected
            } else {
                pairing
            }
        }
        .onAppear(perform: startServer)
        .onDisappear { server?.stop(); server = nil }
    }

    // MARK: - States

    private var connected: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsStatus(text: "Connected as \(model.username)", good: true)
            Text("Used to fetch Hebrew and English subtitles during playback.")
                .settingsCaption()
            Button("Disconnect", role: .destructive) { model.remove() }
        }
    }

    private var pairing: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 14) {
                Text(headline)
                    .font(.seret(.headline, .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(caption).settingsCaption()
                if case .ready(let address) = status {
                    Text(address)
                        .font(.seret(.callout, .semibold)).monospaced()
                        .foregroundStyle(Theme.Palette.gold)
                }
                // Hidden while pairing is available so it does not compete with the QR, and shown
                // outright when it is the only way in.
                if case .unavailable = status {
                    manualEntry
                } else {
                    Button(showingManualEntry ? "Hide keyboard entry" : "Type it here instead") {
                        showingManualEntry.toggle()
                    }
                    .padding(.top, 4)
                    if showingManualEntry { manualEntry }
                }
            }
            Spacer(minLength: 0)
            if case .unavailable = status {} else { qr }
        }
    }

    private var status: LocalPairingServer.Status { server?.status ?? .starting }

    private var headline: String {
        if case .unavailable = status { return "Sign in to OpenSubtitles" }
        return "Scan to sign in with your phone"
    }

    private var caption: String {
        switch status {
        case .starting:
            return "Preparing…"
        case .ready:
            return "The page is served by this Apple TV on your own network — your password is never sent anywhere else."
        case .unavailable(let reason):
            return "Phone sign-in is unavailable: \(reason) Enter your account here instead."
        }
    }

    @ViewBuilder private var qr: some View {
        if case .ready(let address) = status, let code = QRCode.image(from: address) {
            code.interpolation(.none).resizable()
                .frame(width: 240, height: 240)
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.Palette.surface2)
                .frame(width: 268, height: 268)
                .overlay { ProgressView() }
        }
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Username", text: $model.username).textContentType(.username)
            SecureField("Password", text: $model.password).textContentType(.password)
            Button("Save") { model.save() }
        }
        .frame(maxWidth: 520)
        .padding(.top, 6)
    }

    // MARK: - Server

    /// The listener runs only while this section is on screen — see `LocalPairingServer`.
    private func startServer() {
        guard server == nil else { return }
        let server = LocalPairingServer { credentials in
            model.username = credentials.username
            model.password = credentials.password
            model.save()
        }
        server.start()
        self.server = server
    }
}
