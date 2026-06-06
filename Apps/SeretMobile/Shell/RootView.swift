import DebridUI
import SwiftUI

/// Resolves launch state, then routes between sign-in and the main shell.
struct RootView: View {
    @Environment(AppSession.self) private var session

    @State private var showSplash = true

    var body: some View {
        ZStack {
            content
            if showSplash {
                SplashView { withAnimation(Theme.Motion.fade) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(1)
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
            MainShell()
        }
    }
}
