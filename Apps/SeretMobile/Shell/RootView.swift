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
                DetailScreen(item: item, details: details, watch: session.watchStore)
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
