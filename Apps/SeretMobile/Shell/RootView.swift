import DebridCore
import DebridUI
import SwiftUI

/// Resolves launch state, then routes between sign-in and the main shell.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSplash = true
    @State private var router = AppRouter()
    /// Watched marks for every browse/search poster. Held here so all the grids share one cache.
    @State private var tileMarks: TileWatchMarks?
    /// The watchlist toggle offered by tiles and title pages. One object for the whole shell, read
    /// OPTIONALLY wherever it is used — see the comment in `FindScreen`.
    @State private var watchlistMarks: WatchlistMarks?

    var body: some View {
        ZStack {
            content
                .animation(.easeInOut(duration: 0.45), value: session.needsProfileSelection)
            if showSplash {
                SplashView { withAnimation(Theme.Motion.fade) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // Coming back is the moment the Synology is most likely reachable again after it was
        // not. Backoff still applies inside the coordinator, so this cannot become a retry storm.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await session.letterboxdPush?.drain() }
        }
        .environment(router)
        .task { if tileMarks == nil { tileMarks = session.makeTileWatchMarks() } }
        .task {
            if watchlistMarks == nil { watchlistMarks = session.makeWatchlistMarks() }
            await watchlistMarks?.load()
        }
        .environment(watchlistMarks ?? .placeholder)
        .environment(tileMarks ?? .placeholder)
        // Detail (and the player nested in it) is presented HERE — above the TabView/SplitView —
        // so rotating the device doesn't dismiss it.
        .fullScreenCover(item: Binding(get: { router.detail }, set: { router.detail = $0 })) { item in
            if let details = session.detailsProvider {
                DetailScreen(item: item, details: details, watch: session.watchStore,
                             profileID: session.activeProfileID,
                             myList: session.myListStore,
                             ratings: session.ratingsProvider,
                             versionPrefs: session.versionPreferences,
                             letterboxd: session.letterboxdRatingProvider)
            }
        }
        // Direct playback from a rail (Home's Resume) — same build recipe as DetailScreen's player
        // cover; presented here so it survives rotation. The closure runs once per presentation.
        .fullScreenCover(item: Binding(get: { router.playback }, set: { router.playback = $0 })) { presented in
            PlayerHost(request: presented.request, app: session, onExit: { router.playback = nil })
        }
        .onChange(of: session.state) { oldValue, newValue in
            // Replay the branded intro right after a fresh sign-in, over the first library load.
            if newValue == .signedIn, oldValue == .signedOut { showSplash = true }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        switch session.state {
        case .unknown:
            ProgressView()
                .task { await session.resolve() }
        case .signedOut:
            if let model = session.signInModel {
                SignInView(model: model)
            }
        case .signedIn:
            if session.needsProfileSelection {
                WhoIsWatchingScreen()
                    .transition(.opacity)
            } else {
                MainShell()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
    }
}
