#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// DEBUG-only harness for the glass Settings, sign-in and profile screens — none of which an
/// unsigned simulator (the iPad) can reach, and none of which may be driven with real credentials.
///
///     xcrun simctl launch <udid> com.solomons.seret.mobile -uiPreview <target>
///
/// - `settings` — Settings with a fixture Letterboxd model (username, partner, server), so every
///   labelled field shows. Nothing is saved: the fixture store drops writes.
/// - `settingsletterboxd` — just the Letterboxd sections (below the fold of `settings`).
/// - `opensubs` — the OpenSubtitles sign-in form (empty — nothing is ever typed into it).
/// - `signincode` / `signintoken` / `signinfailed` / `signinpreparing` — the sign-in card's faces,
///   drawn from a fixed face rather than a network, with the Real‑Debrid / TorBox picker (it
///   switches the harness's copy, nothing else).
/// - `signintorbox` / `signintorboxkey` / `signintorboxfailed` — the same faces for TorBox.
/// - `accounts` — Settings with both accounts signed in (TorBox's email and plan, the add-target
///   picker). `accountsfree`: TorBox on the Free plan (the warning). `accountsone`: Real‑Debrid only,
///   TorBox offering Sign In.
/// - `profiles` / `addprofile` — Who's Watching and the profile editor.
struct ScreensUIPreview: View {
    let target: String
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()),
                                            torBox: TorBoxSession(store: InMemorySecretStore()))
    @State private var router = AppRouter()
    @State private var token = ""
    /// The picker's choice in the sign-in faces; starts on the provider the target names.
    @State private var provider: DebridProvider?

    var body: some View {
        content
            .environment(\.uiPreviewStores, UIPreviewStores(letterboxdImport: Self.letterboxd,
                                                             accounts: accountsFixture))
            .environment(session)
            .environment(router)
            .environment(TileWatchMarks.placeholder)
            .environment(WatchlistMarks.placeholder)
            .preferredColorScheme(.dark)
            .tint(Theme.Palette.focus)
    }

    @ViewBuilder private var content: some View {
        switch target {
        case "settings", "accounts", "accountsfree", "accountsone":
            NavigationStack { SettingsView() }
        case "settingsletterboxd":
            // The Letterboxd sections alone — on the iPad they sit below the fold of Settings.
            NavigationStack {
                GlassFormPage {
                    LetterboxdSettingsSection(model: Self.letterboxd, profileID: "preview", push: nil)
                }
                .navigationTitle("Settings")
            }
        case "opensubs":
            NavigationStack {
                OpenSubtitlesSignInView(model: SettingsModel(secretStore: PreviewSecrets()))
            }
        case "profiles":
            WhoIsWatchingScreen()
        case "addprofile":
            AddProfileScreen()
        default:
            SignInCard(provider: shownProvider, face: face, tokenText: $token,
                       switchProvider: { provider = $0 },
                       openVerification: { _ in }, useToken: {}, back: {}, submitToken: {}, retry: {})
        }
    }

    private var shownProvider: DebridProvider {
        provider ?? (target.hasPrefix("signintorbox") ? .torBox : .realDebrid)
    }

    private var face: SignInCard.Face {
        switch (target, shownProvider) {
        case ("signintoken", _), ("signintorboxkey", _): .token(checking: false, error: nil)
        case ("signinfailed", _): .failed("Real\u{2011}Debrid is busy right now. Wait a minute and try again.")
        case ("signintorboxfailed", _): .failed("That TorBox API key wasn't accepted.")
        case ("signinpreparing", _): .preparing("Preparing sign\u{2011}in…")
        // The friendly address as TorBox sends it — no scheme — through the view's own mapping.
        case (_, .torBox): .code("8KQ2", SignInCard.verificationURL("tor.box/link"))
        case (_, .realDebrid): .code("Q7RT2K", URL(string: "https://real-debrid.com/device"))
        }
    }

    /// The Accounts rows for `accounts…`; nil elsewhere, so Settings draws the live (signed-out) rows.
    private var accountsFixture: AccountsPreview? {
        switch target {
        case "accounts":
            AccountsPreview(rows: [
                AccountRowFace(provider: .realDebrid, signedIn: true, detail: nil, warning: nil),
                AccountRowFace(provider: .torBox, signedIn: true, detail: "viewer@example.com · Pro", warning: nil),
            ], addTarget: .torBox)
        case "accountsfree":
            AccountsPreview(rows: [
                AccountRowFace(provider: .realDebrid, signedIn: true, detail: nil, warning: nil),
                AccountRowFace(provider: .torBox, signedIn: true, detail: "viewer@example.com · Free",
                               warning: "TorBox's API needs a paid plan."),
            ])
        case "accountsone":
            AccountsPreview(rows: [
                AccountRowFace(provider: .realDebrid, signedIn: true, detail: nil, warning: nil),
                AccountRowFace(provider: .torBox, signedIn: false, detail: nil, warning: nil),
            ])
        default: nil
        }
    }

    /// A Letterboxd model over fixed settings; nothing it writes goes anywhere.
    @MainActor static let letterboxd = LetterboxdImportModel(settingsStore: PreviewLetterboxdSettings()) { _, _ in
        throw CancellationError()
    }
}

private struct PreviewLetterboxdSettings: LetterboxdSettingsStoring {
    func load() -> LetterboxdSettings {
        LetterboxdSettings(username: "preview", isEnabled: true, lastImportAt: Date().addingTimeInterval(-7_200),
                           serverURL: "192.168.1.179:8080", partnerUsername: "noga", partnerName: "Noga")
    }
    func save(_ settings: LetterboxdSettings) {}
}

/// An empty secret store, so the OpenSubtitles form opens signed out and blank.
private struct PreviewSecrets: SecretStore {
    func read() throws -> Data? { nil }
    func write(_ data: Data) throws {}
    func clear() throws {}
}
#endif
