import DebridCore
import DebridUI
import SwiftUI

/// Resolves launch state, then routes between sign-in and the main shell.
struct RootView: View {
    @Environment(AppSession.self) private var session

    @State private var showSplash = true
    @State private var router = AppRouter()

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
        .environment(router)
        // Detail (and the player nested in it) is presented HERE — above the TabView/SplitView —
        // so rotating the device doesn't dismiss it.
        .fullScreenCover(item: Binding(get: { router.detail }, set: { router.detail = $0 })) { item in
            if let details = session.detailsProvider {
                DetailScreen(item: item, details: details, watch: session.watchStore,
                             profileID: session.activeProfileID,
                             myList: session.myListStore,
                             ratings: session.ratingsProvider)
            }
        }
        // The Add flow is presented here too (above the shell) so it and its nested player
        // survive rotation, exactly like Detail.
        .fullScreenCover(item: Binding(get: { router.addHit }, set: { router.addHit = $0 })) { hit in
            AddScreen(hit: hit)
        }
        // Direct playback from a rail (Home's Resume) — same build recipe as DetailScreen's player
        // cover; presented here so it survives rotation. The closure runs once per presentation.
        .fullScreenCover(item: Binding(get: { router.playback }, set: { router.playback = $0 })) { presented in
            let engine = VLCKitVideoPlayerEngine(preferences: session.subtitleSettings.preferences)
            if let model = session.makePlayer(for: presented.request, engine: engine) {
                PlayerView(model: model, engine: engine,
                           backdropURL: TMDBClient.imageURL(path: presented.request.item.backdropPath, size: "w1280"),
                           onExit: { router.playback = nil })
            } else {
                PlayerPlaceholder(request: presented.request)
            }
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
