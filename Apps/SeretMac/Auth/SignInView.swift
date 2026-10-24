import DebridCore
import DebridUI
import SwiftUI

/// Binds the shared `SignInModel` to the pure `SignInScreen`. The device-code run restarts whenever
/// the model's `taskKey` changes (Try Again, or a different model); a pasted token / key signs in
/// directly.
///
/// The same view serves the signed-out window (with the Real-Debrid / TorBox choice, via
/// `switchProvider`) and Settings → Accounts' sheet for one more account (`style: .sheet`, no choice).
struct SignInView: View {
    let model: SignInModel
    var style: SignInScreen.Style = .window
    /// The signed-out screen's provider choice (`AppSession.switchSignIn(to:)`). Nil when the
    /// provider is fixed — adding a second account from Settings.
    var switchProvider: ((DebridProvider) -> Void)?
    var onCancel: () -> Void = {}

    /// What the viewer typed and chose, for THIS model. Dropped whole when the model changes.
    @State private var entry: SignInScreenState.Entry
    @State private var posters: [URL] = []

    init(model: SignInModel, style: SignInScreen.Style = .window,
         switchProvider: ((DebridProvider) -> Void)? = nil, onCancel: @escaping () -> Void = {}) {
        self.model = model
        self.style = style
        self.switchProvider = switchProvider
        self.onCancel = onCancel
        _entry = State(initialValue: SignInScreenState.Entry(provider: model.provider))
    }

    var body: some View {
        SignInScreen(state: .make(phase: model.phase, mode: entry.mode, tokenSubmitted: entry.tokenSubmitted,
                                  provider: model.provider),
                     mode: $entry.mode, token: $entry.token,
                     posters: posters,
                     style: style,
                     switchProvider: switchProvider,
                     onRetry: { model.retry() },
                     onSubmitToken: {
                         guard let token = entry.submit(phase: model.phase) else { return }
                         Task { await model.signInWithToken(token) }
                     },
                     onCancel: onCancel)
            .onChange(of: entry.mode) { entry.tokenSubmitted = false }
            // A different model is a different sign-in (the picker switched provider): nothing typed
            // for one provider may carry over to the other — least of all a pasted key.
            .onChange(of: ObjectIdentifier(model)) { entry.switchProvider(to: model.provider) }
            .task(id: model.taskKey) { await model.run() }
            .task {
                guard style == .window else { return }
                posters = await PosterMosaic.loadPopularPosters()
            }
    }
}
