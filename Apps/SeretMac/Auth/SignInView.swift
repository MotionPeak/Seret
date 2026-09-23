import DebridUI
import SwiftUI

/// Binds the shared `SignInModel` to the pure `SignInScreen`. The device-code run restarts whenever
/// the model's `attempt` changes (Try Again); a pasted token signs in directly.
struct SignInView: View {
    let model: SignInModel
    @State private var mode: SignInMode = .code
    @State private var token = ""
    @State private var posters: [URL] = []

    var body: some View {
        SignInScreen(state: .make(phase: model.phase, mode: mode), mode: $mode, token: $token,
                     posters: posters,
                     onRetry: { model.retry() },
                     onSubmitToken: { Task { await model.signInWithToken(token) } })
            .task(id: model.attempt) { await model.run() }
            .task { posters = await PosterMosaic.loadPopularPosters() }
    }
}
