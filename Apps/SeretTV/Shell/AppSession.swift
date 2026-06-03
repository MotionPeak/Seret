import DebridCore
import Observation

/// Owns the one shared `RealDebridSession` and the app's coarse auth state. It is the
/// `AccessTokenProviding` source that 7b's library + 7c's playback will consume.
@MainActor
@Observable
final class AppSession {
    enum State: Equatable { case unknown, signedIn, signedOut }

    private(set) var state: State = .unknown

    /// The sign-in model for the current signed-out episode (nil while signed in or
    /// unresolved). Built when *entering* `.signedOut` so the view never creates it
    /// during `body` evaluation.
    private(set) var signInModel: SignInModel?

    let realDebrid: RealDebridSession

    init(realDebrid: RealDebridSession) {
        self.realDebrid = realDebrid
    }

    /// Resolve launch state from persisted credentials. `validAccessToken()` throws
    /// `.notSignedIn` ONLY when there are no stored credentials, which lets us treat
    /// offline-with-credentials as optimistically signed in (spec §143) while a server
    /// rejection of the refresh token routes back to sign-in (spec §165).
    func resolve() async {
        do {
            _ = try await realDebrid.validAccessToken()
            state = .signedIn
        } catch RealDebridSessionError.notSignedIn {
            enterSignedOut()
        } catch HTTPError.status(_, _) {
            // RD actively rejected the stored/refresh token → must re-authenticate.
            enterSignedOut()
        } catch {
            // Transport/offline but credentials exist: stay signed in; later calls retry.
            // (A genuine decoding bug would also land here as optimistic-signedIn; the
            // first real library call in 7b surfaces it — acceptable for this slice.)
            state = .signedIn
        }
    }

    func markSignedIn() {
        state = .signedIn
        signInModel = nil
    }

    func signOut() async {
        try? await realDebrid.signOut()
        enterSignedOut()
    }

    /// Enter `.signedOut` with a fresh sign-in model for the new episode.
    private func enterSignedOut() {
        signInModel = SignInModel(
            flow: LiveAuthFlow(auth: RealDebridAuthClient(), session: realDebrid),
            onSignedIn: { [weak self] in self?.markSignedIn() })
        state = .signedOut
    }
}
