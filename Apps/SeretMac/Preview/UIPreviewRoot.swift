#if DEBUG
import DebridCore
import DebridUI
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
            case "posters":
                PosterGalleryPreview()
            case "postersloading":
                PosterGalleryPreview(isLoading: true)
            case "library":
                libraryPreview(.items(Fixture.films + Fixture.shows))
            case "libraryshows":
                libraryPreview(.items(Fixture.films + Fixture.shows), forcedKind: .show)
            case "libraryloading":
                libraryPreview(.loadingForever)
            case "libraryempty":
                libraryPreview(.empty)
            case "libraryfailed":
                libraryPreview(.failing)
            case "titlemovie":
                titlePreview(item: Fixture.films[0])
            case "titleshow":
                titlePreview(item: Fixture.show)
            case "titleshows2":
                titlePreview(item: Fixture.show, selectSeason: 2)
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

    /// Mounts `MainShell` on `.library` with a fixture `LibraryStore` injected into the
    /// environment — the same seam `LibraryRoot` reads before falling back to the session.
    private func libraryPreview(_ mode: PreviewLibrary.Mode, forcedKind: MediaKind? = nil) -> some View {
        let suite = "seret.preview.library.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.library)
        let store = LibraryStore(library: PreviewLibrary(mode: mode), watch: PreviewWatch(Fixture.watch),
                                 profileID: { "" })
        return MainShell(model: model)
            .environment(store)
            .environment(\.previewForcedLibraryKind, forcedKind)
    }

    /// Mounts `MainShell` on `.library` with the title already pushed (the real navigation path a
    /// poster click takes) and a fixture `DetailStore` injected — the same seam `TitleRoute` reads
    /// before falling back to the session.
    private func titlePreview(item: MediaItem, selectSeason: Int? = nil) -> some View {
        let suite = "seret.preview.title.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.library)
        model.open(.title(item))
        let store = DetailStore(item: item, details: PreviewDetails(), watch: PreviewWatch(Fixture.watch), profileID: "")
        return MainShell(model: model)
            .environment(store)
            .task {
                if let selectSeason { await store.selectSeason(selectSeason) }
            }
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
