import DebridCore
import DebridUI
import SwiftUI

/// Resolves launch state, then routes between sign-in and the shell. The splash plays at launch and
/// again right after a fresh sign-in, over the first library load — as on the iPhone.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    @State private var shell = ShellModel()

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
            if newValue == .signedIn, oldValue == .signedOut { showSplash = true }
        }
        // Coming back is when the Seret server is most likely reachable again; the coordinator's own
        // backoff means this cannot become a retry storm.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await session.letterboxdPush?.drain() }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        switch session.state {
        case .unknown:
            CanvasBackground()
                .frame(minWidth: 1000, minHeight: 650)
                .task { await session.resolve() }
        case .signedOut:
            if let model = session.signInModel {
                SignInView(model: model)
            }
        case .signedIn:
            MainShell(model: shell)
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
        }
    }
}
