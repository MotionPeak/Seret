import SwiftUI
import DebridUI

/// Resolves launch state, then routes between sign-in and the library shell.
struct RootView: View {
    @Environment(AppSession.self) private var session

    @State private var showSplash = true

    var body: some View {
        ZStack {
            content
            if showSplash {
                SplashView { withAnimation(.easeInOut(duration: 0.3)) { showSplash = false } }
                    .transition(.opacity).zIndex(1)
            }
        }
        .tint(Theme.Palette.gold)
        .onChange(of: session.state) { oldValue, newValue in
            if newValue == .signedIn, oldValue == .signedOut { showSplash = true }
        }
    }

    @ViewBuilder private var content: some View {
        switch session.state {
        case .unknown:
            ZStack { CanvasBackground(); ProgressView().tint(Theme.Palette.gold) }
                .task { await session.resolve() }
        case .signedOut:
            if let model = session.signInModel {
                SignInView(model: model)
            }
        case .signedIn:
            LibraryShell()
        }
    }
}
