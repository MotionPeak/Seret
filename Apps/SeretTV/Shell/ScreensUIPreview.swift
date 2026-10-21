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
///   - `splash` — the launch splash, held on its last frame
///   - `profiles` — Who's Watching? on a three-profile fixture roster
///   - `addprofile` — the profile editor
///   - `settingsscreen` — the Settings screen whole, on an unsigned session
///   - `watchlistchange` — the title page's watchlist toast, a success above a failure
struct ScreensUIPreview: View {
    let target: String
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))

    var body: some View {
        switch target {
        case "signin":
            SignInContent(phase: Self.awaiting, onRetry: {}, onSubmitToken: { _ in })
        case "signintoken":
            SignInContent(phase: .failed("That token didn't work. Check it and try again."),
                          showingTokenEntry: true, onRetry: {}, onSubmitToken: { _ in })
        case "signinfailed":
            SignInContent(phase: .failed("Real‑Debrid is busy right now. Wait a minute, then try again."),
                          onRetry: {}, onSubmitToken: { _ in })
        case "splash":
            SplashView(onFinished: {})
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

    static let targets: Set<String> = ["signin", "signintoken", "signinfailed", "splash", "profiles",
                                       "addprofile", "settingsscreen", "watchlistchange"]

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
#endif
