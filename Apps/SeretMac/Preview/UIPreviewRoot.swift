#if DEBUG
import DebridCore
import SwiftUI

/// DEBUG only: `-uiPreview <case>` boots straight into one screen with fixture data, so every screen
/// can be screenshot-verified without signing in or walking the UI (the tvOS lesson). Each task that
/// adds a screen adds its case here.
struct UIPreviewRoot: View {
    let target: String

    var body: some View {
        Group {
            switch target {
            case "vlcsmoke":
                VLCSmokePreview(url: VLCSmokePreview.url(from: ProcessInfo.processInfo.arguments))
            case "design":
                DesignGalleryPreview()
            case "splash":
                SplashView { }
            case "shell":
                MainShell(model: ShellModel(defaults: UserDefaults(suiteName: "seret.preview.shell")!))
            case "shellcollapsed":
                MainShell(model: {
                    let defaults = UserDefaults(suiteName: "seret.preview.shellcollapsed")!
                    defaults.set(true, forKey: "seret.mac.sidebarCollapsed")
                    return ShellModel(defaults: defaults)
                }())
            case "shellnav":
                MainShell(model: {
                    let model = ShellModel(defaults: UserDefaults(suiteName: "seret.preview.shellnav")!)
                    model.select(.library)
                    model.open(.title(MediaItem(id: "movie:tmdb:1", kind: .movie, title: "Preview Title",
                                                year: 2024, sources: [], seasons: [])))
                    return model
                }())
            case "signincode":
                signIn(.code(userCode: "W6XD2P7N", verificationURL: URL(string: "https://real-debrid.com/device"),
                             expiresIn: 600), mode: .code)
            case "signintoken":
                signIn(.token(checking: false, error: nil), mode: .token)
            case "signintokenerror":
                signIn(.token(checking: false, error: "That token wasn't accepted by Real-Debrid. Check it and try again."),
                       mode: .token)
            case "signinfailed":
                signIn(.failed("Real-Debrid is busy right now. Wait a minute and try again."), mode: .code)
            case "signinpreparing":
                signIn(.preparing("Preparing sign-in…"), mode: .code)
            default:
                Text("Unknown -uiPreview case: \(target)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .preferredColorScheme(.dark)
    }

    private func signIn(_ panel: SignInScreenState.Panel, mode: SignInMode) -> some View {
        SignInPreviewHost(state: SignInScreenState(panel: panel), mode: mode)
    }
}

/// Holds the bindings a static sign-in state needs, and loads the real poster mosaic.
private struct SignInPreviewHost: View {
    let state: SignInScreenState
    @State var mode: SignInMode
    @State private var token = ""
    @State private var posters: [URL] = []

    var body: some View {
        SignInScreen(state: state, mode: $mode, token: $token, posters: posters)
            .task { posters = await PosterMosaic.loadPopularPosters() }
    }
}
#endif
