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
///   drawn from a fixed face rather than a network.
/// - `profiles` / `addprofile` — Who's Watching and the profile editor.
struct ScreensUIPreview: View {
    let target: String
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var router = AppRouter()
    @State private var token = ""

    var body: some View {
        content
            .environment(\.uiPreviewStores, UIPreviewStores(letterboxdImport: Self.letterboxd))
            .environment(session)
            .environment(router)
            .environment(TileWatchMarks.placeholder)
            .environment(WatchlistMarks.placeholder)
            .preferredColorScheme(.dark)
            .tint(Theme.Palette.focus)
    }

    @ViewBuilder private var content: some View {
        switch target {
        case "settings":
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
            SignInCard(face: face, tokenText: $token, openVerification: { _ in }, useToken: {},
                       back: {}, submitToken: {}, retry: {})
        }
    }

    private var face: SignInCard.Face {
        switch target {
        case "signintoken": .token(checking: false, error: nil)
        case "signinfailed": .failed("Real\u{2011}Debrid is busy right now. Wait a minute and try again.")
        case "signinpreparing": .preparing("Preparing sign\u{2011}in…")
        default: .code("Q7RT2K", URL(string: "https://real-debrid.com/device"))
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
