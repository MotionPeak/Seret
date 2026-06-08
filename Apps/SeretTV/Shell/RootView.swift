import SwiftUI
import DebridUI

/// Resolves launch state, then routes between sign-in and the library shell.
/// A branded splash overlays everything on first launch while `resolve()` runs,
/// then fades out — so launch never shows a bare spinner.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @State private var splashDone = false

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
                } else {
                    LibraryShell()
                }
            }
            if !splashDone {
                SplashView { splashDone = true }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: splashDone)
    }
}
