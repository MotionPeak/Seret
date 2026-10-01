import SwiftUI
import DebridUI

/// Resolves launch state, then routes between sign-in and the library shell.
/// A branded splash overlays everything on first launch while `resolve()` runs,
/// then fades out — so launch never shows a bare spinner.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var splashDone = false

    /// How old the library may get before coming back to the app re-reads it. A refresh with
    /// nothing new is one paginated Real-Debrid call.
    static let libraryMaxAge: TimeInterval = 120

    var body: some View {
        ZStack {
            switch session.state {
            case .unknown:
                Color.black.ignoresSafeArea()
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
                    LibraryShell()
                        .transition(.opacity)
                }
            }
            if !splashDone {
                SplashView { splashDone = true }
                    .transition(.opacity)
            }
        }
        .animation(Theme.Anim.pageFade, value: splashDone)
        .animation(Theme.Anim.pageFade, value: session.needsProfileSelection)
        // Coming back is the moment the Synology is most likely reachable again after it was
        // not. Backoff still applies inside the coordinator, so this cannot become a retry storm.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await session.letterboxdPush?.drain() }
            // tvOS keeps a suspended app alive for days; without this, titles added from DMM, the
            // phone or the Real-Debrid site never appeared until the app was killed.
            session.libraryStore?.refreshIfStale(maxAge: Self.libraryMaxAge)
        }
    }
}
