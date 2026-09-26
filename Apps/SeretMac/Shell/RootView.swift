import DebridCore
import DebridUI
import SwiftUI

/// Resolves launch state, then routes between sign-in and the shell. The splash plays at launch and
/// again right after a fresh sign-in, over the first library load — as on the iPhone.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    @State private var splashAnimationDone = false
    @State private var animationEndedAt: ContinuousClock.Instant?
    @State private var shell = ShellModel()

    var body: some View {
        ZStack {
            content
            if showSplash {
                SplashView {
                    splashAnimationDone = true
                    animationEndedAt = .now
                    evaluate()
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .onChange(of: session.state) { oldValue, newValue in
            // The splash plays again right after a fresh sign-in, over the first library load —
            // both gating states reset with it, or `evaluate()` would see the PREVIOUS pass's
            // finished animation and hide the splash on the very next library update.
            if newValue == .signedIn, oldValue == .signedOut {
                showSplash = true
                splashAnimationDone = false
                animationEndedAt = nil
            }
        }
        .onChange(of: session.libraryStore?.state) { _, _ in evaluate() }
        .task(id: splashAnimationDone) {
            guard splashAnimationDone else { return }
            try? await Task.sleep(for: SplashGate.maxHold)
            evaluate()
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

    /// Hides the splash once `SplashGate` says its work is done — the animation, plus whatever the
    /// shell underneath needed (nothing if signed out, the library's first answer if signed in).
    private func evaluate() {
        guard showSplash else { return }
        let heldFor = animationEndedAt.map { ContinuousClock.now - $0 } ?? .zero
        if SplashGate.shouldHide(animationFinished: splashAnimationDone, session: session.state,
                                 library: session.libraryStore?.state, heldFor: heldFor) {
            withAnimation(Theme.Motion.fade) { showSplash = false }
        }
    }
}
