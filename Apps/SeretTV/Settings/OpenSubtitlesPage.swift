import SwiftUI
import DebridUI

/// OpenSubtitles sign-in, with the typing moved to the viewer's phone. Pushed from Settings →
/// Subtitles → Downloads.
///
/// A QR is the primary path because entering a password on a TV remote is miserable, and
/// OpenSubtitles offers no device-code flow to lean on the way Real-Debrid does — so the Apple TV
/// serves the form itself (see `LocalPairingServer`) and the QR is just its address. The on-screen
/// fields remain as a fallback, collapsed by default so they do not compete with the QR.
struct OpenSubtitlesPage: View {
    @Bindable var model: SettingsModel
    @State private var server: LocalPairingServer?
    @State private var showingManualEntry = false

    var body: some View {
        SettingsPageLayout(title: "OpenSubtitles", clearsSideMenu: true) {
            pane
        } rows: {
            rows
        }
        .onAppear(perform: syncServer)
        // The server exists ONLY to receive a password. Starting it while already connected put a
        // credential form on the LAN that nothing on screen even offered — and it used to keep
        // running after pairing succeeded, so the window stayed open for the rest of the visit.
        .onChange(of: model.isConnected) { _, _ in syncServer() }
        .onDisappear(perform: stopServer)
    }

    // MARK: - Pane

    @ViewBuilder private var pane: some View {
        if model.isConnected {
            VStack(alignment: .leading, spacing: 26) {
                SettingsSymbol(icon: "checkmark")
                Text("Connected as \(model.username)")
                    .sectionTitle()
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Used to fetch Hebrew and English subtitles during playback.")
                    .calloutText().lineSpacing(6)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 26) {
                if case .unavailable = status {} else { qr }
                Text(headline)
                    .sectionTitle()
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(caption)
                    .calloutText().lineSpacing(6)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .ready(let address) = status {
                    Text(address)
                        .font(.seret(.callout, .semibold)).monospaced()
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
            }
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
                .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.Palette.surface2)
                .frame(width: 268, height: 268)
                .overlay { ProgressView().tint(Theme.Palette.textPrimary) }
        }
    }

    // MARK: - Rows

    @ViewBuilder private var rows: some View {
        SettingsSectionHeader(title: "Account", first: true)
        // Present in both states, so the page always has a row to land on — including the moment
        // Disconnect swaps the rows below it.
        SettingsRow(title: "OpenSubtitles", value: model.isConnected ? model.username : "Not connected") {}
        if model.isConnected {
            SettingsRow(title: "Disconnect", destructive: true) { model.remove() }
        } else if case .unavailable = status {
            manualEntry
        } else {
            // Hidden while pairing is available so it does not compete with the QR, and shown
            // outright when it is the only way in. The row stays put; only its words change.
            SettingsRow(title: showingManualEntry ? "Hide Keyboard Entry" : "Type It Here Instead") {
                showingManualEntry.toggle()
            }
            if showingManualEntry { manualEntry }
        }
    }

    @ViewBuilder private var manualEntry: some View {
        SettingsSectionHeader(title: "Sign in here")
        VStack(alignment: .leading, spacing: 12) {
            TextField("Username", text: $model.username).textContentType(.username)
            SecureField("Password", text: $model.password).textContentType(.password)
        }
        .padding(.horizontal, 6)
        SettingsRow(title: "Save") { model.save() }
            .padding(.top, 10)
    }

    // MARK: - Server

    /// Runs the pairing server exactly while it is needed: not before, and not a moment after —
    /// only while this page is on screen and the account is not connected. See `LocalPairingServer`.
    private func syncServer() {
        if model.isConnected { stopServer() } else { startServer() }
    }

    private func startServer() {
        guard server == nil else { return }
        let server = LocalPairingServer { credentials in
            model.username = credentials.username
            model.password = credentials.password
            model.save()
            stopServer()      // it has what it came for; close the door behind it
        }
        server.start()
        self.server = server
    }

    private func stopServer() {
        server?.stop()
        server = nil
    }
}
