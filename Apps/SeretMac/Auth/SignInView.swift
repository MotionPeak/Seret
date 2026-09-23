import DebridUI
import SwiftUI

/// Binds the shared `SignInModel` to the pure `SignInScreen`. The device-code run restarts whenever
/// the model's `attempt` changes (Try Again); a pasted token signs in directly.
struct SignInView: View {
    let model: SignInModel
    @State private var mode: SignInMode = .code
    @State private var token = ""
    @State private var posters: [URL] = []
    /// Set by Sign In on the token panel, cleared by any change of panel: only then is a failure the
    /// token's own (see `SignInScreenState.make`).
    @State private var tokenSubmitted = false

    var body: some View {
        SignInScreen(state: .make(phase: model.phase, mode: mode, tokenSubmitted: tokenSubmitted),
                     mode: $mode, token: $token,
                     posters: posters,
                     onRetry: { model.retry() },
                     onSubmitToken: {
                         // Return in the field bypasses the button's disabled state: no second check.
                         guard model.phase != .validatingToken,
                               !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                         tokenSubmitted = true
                         Task { await model.signInWithToken(token) }
                     })
            .onChange(of: mode) { tokenSubmitted = false }
            .task(id: model.attempt) { await model.run() }
            .task { posters = await PosterMosaic.loadPopularPosters() }
    }
}
