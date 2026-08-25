import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// What a failed launch-time token check means. Getting this wrong signs a viewer out of a
/// perfectly good account, and on an Apple TV it can do so on every launch.
@Suite struct AppSessionResolveTests {

    private enum Transport: Error { case offline }

    @Test func noStoredCredentialsMeansSignIn() {
        #expect(AppSession.mustReauthenticate(after: RealDebridSessionError.notSignedIn))
    }

    /// The one status that genuinely says "these credentials are no good".
    @Test func aRejectedTokenMeansSignIn() {
        #expect(AppSession.mustReauthenticate(after: HTTPError.status(code: 401, body: "")))
    }

    /// Real-Debrid answers a rate limit with a bare 403 — this repo's own notes record that a tvOS
    /// client can get a PERSISTENT one. Treating it as a rejection made the viewer sign in again
    /// with nothing wrong with their account.
    @Test func beingRateLimitedDoesNotSignTheViewerOut() {
        #expect(!AppSession.mustReauthenticate(after: HTTPError.status(code: 403, body: "")))
        #expect(!AppSession.mustReauthenticate(after: HTTPError.status(code: 429, body: "")))
    }

    /// Nor does Real-Debrid being down.
    @Test func realDebridBeingDownDoesNotSignTheViewerOut() {
        for code in [500, 502, 503, 504] {
            #expect(!AppSession.mustReauthenticate(after: HTTPError.status(code: code, body: "")),
                    "status \(code) must not sign out")
        }
    }

    /// Offline with stored credentials was always meant to stay optimistically signed in.
    @Test func beingOfflineDoesNotSignTheViewerOut() {
        #expect(!AppSession.mustReauthenticate(after: Transport.offline))
        #expect(!AppSession.mustReauthenticate(after: URLError(.notConnectedToInternet)))
    }
}
