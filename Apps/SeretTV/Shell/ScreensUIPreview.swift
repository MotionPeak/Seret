#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// DEBUG harnesses for the screens outside the browse pages and the player — sign-in, splash, the
/// profile picker and editor, the whole Settings screen and the title page's watchlist toast — so
/// each can be screenshot-verified without signing the simulator out or touching real accounts.
/// Dispatched from `PlayerUIPreview`:
///   - `signin` — the device-code screen on a fixture code (QR, URL, code, the token fallback)
///   - `signintoken` — the paste-a-token form after a rejected token
///   - `signinfailed` — the device-code request failed (Try Again focused)
///   - `signin-torbox` — the signed-out screen with TorBox chosen: the Real-Debrid / TorBox choice,
///     the tor.box/link code + QR (from a scheme-less friendly URL, as TorBox can send one) and
///     "Use a TorBox API key instead". `signin-torbox-key`: the paste-a-key form after a rejected key
///   - `signin-addaccount` — Settings → Accounts' pushed sign-in page for TorBox: no provider
///     choice, "Sign in to TorBox" instead
///   - `accounts` — Settings → Accounts with both accounts signed in: TorBox's email · plan, and
///     the "Add new titles to" choice. `accountsfreeplan`: Real-Debrid signed out and a TorBox key
///     on the Free plan (the paid-plan warning, no choice)
///   - `splash` — the launch splash, held on its last frame
///   - `profiles` — Who's Watching? on a three-profile fixture roster
///   - `addprofile` — the profile editor
///   - `settingsscreen` — the Settings screen whole, on an unsigned session
///   - `watchlistchange` — the title page's watchlist toast, a success above a failure
struct ScreensUIPreview: View {
    let target: String
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()),
                                            torBox: TorBoxSession(store: InMemorySecretStore()))

    var body: some View {
        switch target {
        case "signin":
            SignInContent(phase: Self.awaiting, onSwitchProvider: { _ in }, onRetry: {}, onSubmitToken: { _ in })
        case "signintoken":
            SignInContent(phase: .failed("That token didn't work. Check it and try again."),
                          onSwitchProvider: { _ in }, showingTokenEntry: true,
                          onRetry: {}, onSubmitToken: { _ in })
        case "signinfailed":
            SignInContent(phase: .failed("Real‑Debrid is busy right now. Wait a minute, then try again."),
                          onSwitchProvider: { _ in }, onRetry: {}, onSubmitToken: { _ in })
        case "signin-torbox":
            SignInContent(phase: Self.torBoxAwaiting, provider: .torBox, onSwitchProvider: { _ in },
                          onRetry: {}, onSubmitToken: { _ in })
        case "signin-torbox-key":
            SignInContent(phase: .failed("That TorBox API key wasn't accepted."), provider: .torBox,
                          onSwitchProvider: { _ in }, showingTokenEntry: true,
                          onRetry: {}, onSubmitToken: { _ in })
        case "signin-addaccount":
            NavigationStack {
                SignInContent(phase: Self.torBoxAwaiting, provider: .torBox,
                              onRetry: {}, onSubmitToken: { _ in })
            }
        case "accounts":
            AccountsPreview(rows: [
                .init(provider: .realDebrid, isSignedIn: true),
                .init(provider: .torBox, isSignedIn: true, detail: "viewer@example.com · Pro"),
            ])
        case "accountsfreeplan":
            AccountsPreview(rows: [
                .init(provider: .realDebrid, isSignedIn: false),
                .init(provider: .torBox, isSignedIn: true, detail: "viewer@example.com · Free",
                      warning: "TorBox's API needs a paid plan."),
            ])
        case "splash":
            LaunchIntroView(onFinished: {})
        case "profiles":
            WhoIsWatchingScreen(previewRoster: Self.roster).environment(session)
        case "addprofile":
            AddProfileScreen().environment(session)
        case "settingsscreen":
            // In a stack and beside the menu's footprint, as the shell hosts it, so its rows can
            // push their pages and the columns sit where they do in the app.
            NavigationStack { SettingsView().sideMenuContentInset() }.environment(session)
        case "watchlistchange":
            ZStack(alignment: .top) {
                CanvasBackground()
                VStack(spacing: 0) {
                    WatchlistChangeBar(outcome: .init(tmdbID: 1, added: true,
                                                      message: "Added to your Letterboxd watchlist",
                                                      isFailure: false))
                    WatchlistChangeBar(outcome: .init(tmdbID: 1, added: true,
                                                      message: "Couldn't reach Letterboxd — nothing changed",
                                                      isFailure: true))
                }
            }
        default:
            EmptyView()
        }
    }

    static let targets: Set<String> = ["signin", "signintoken", "signinfailed", "signin-torbox",
                                       "signin-torbox-key", "signin-addaccount", "accounts",
                                       "accountsfreeplan", "splash", "profiles", "addprofile",
                                       "settingsscreen", "watchlistchange"]

    /// A device code as RD hands one out — decoded, because that is the type's only way in.
    private static let awaiting: SignInModel.Phase = {
        let json = Data("""
        {"device_code":"PREVIEW","user_code":"K7QX4MZP","interval":5,"expires_in":600,
         "verification_url":"https://real-debrid.com/device"}
        """.utf8)
        // swiftlint:disable:next force_try
        let code = try! JSONDecoder().decode(RDDeviceCode.self, from: json)
        return .awaitingAuthorization(code)
    }()

    /// A TorBox code as `TorBoxDeviceCode.asDeviceCode` hands it to the screen: the friendly URL
    /// with the code in its query and, as TorBox can send it, no scheme.
    private static let torBoxAwaiting: SignInModel.Phase = {
        let json = Data("""
        {"device_code":"PREVIEW","user_code":"7KQ2-X9MP","interval":5,"expires_in":600,
         "verification_url":"tor.box/link?code=7KQ2-X9MP"}
        """.utf8)
        // swiftlint:disable:next force_try
        let code = try! JSONDecoder().decode(RDDeviceCode.self, from: json)
        return .awaitingAuthorization(code)
    }()

    private static let roster: [ProfileDTO] = [
        ProfileDTO(id: "a", name: "Shahar", colorTag: Theme.Palette.defaultColorTag, avatar: avatar(0),
                   createdAt: .distantPast),
        ProfileDTO(id: "b", name: "Noga", colorTag: "purple", avatar: avatar(7), createdAt: .distantPast),
        ProfileDTO(id: "c", name: "Guest", colorTag: "green", avatar: avatar(14), createdAt: .distantPast),
    ]

    private static func avatar(_ i: Int) -> String {
        let all = ProfileAvatars.all
        return all.isEmpty ? ProfileAvatars.fallback : all[i % all.count]
    }
}

/// The Accounts page on fixture rows, in a stack as Settings pushes it. The choice is live, so a
/// press moves the check.
private struct AccountsPreview: View {
    let rows: [AccountsContent.Row]
    @State private var addTarget: DebridProvider = .realDebrid

    var body: some View {
        NavigationStack {
            AccountsContent(rows: rows, showsAddTargetPicker: rows.filter(\.isSignedIn).count > 1,
                            addTarget: $addTarget, onSignIn: { _ in }, onSignOut: { _ in })
        }
    }
}
#endif
