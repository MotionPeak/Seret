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


/// What the library says when it cannot load. Credentials are only cleared when Real-Debrid says so
/// in the one way OAuth defines, so a persistent rejection of any other shape leaves the app signed
/// in and failing — and "check your connection" is then both wrong and a dead end.
@MainActor
@Suite struct LibraryFailureMessageTests {
    private enum Transport: Error { case offline }

    @Test func aRefusalNamesItselfAndPointsAtTheWayOut() {
        for code in [401, 403] {
            let message = LibraryStore.message(for: HTTPError.status(code: code, body: ""))
            #expect(message.contains("refused"))
            #expect(message.lowercased().contains("sign out"))
        }
    }

    @Test func beingSignedOutSaysSo() {
        let message = LibraryStore.message(for: RealDebridSessionError.notSignedIn)
        #expect(message.lowercased().contains("signed out"))
    }

    /// Everything else is still the ordinary connection message — a 5xx or a dropped Wi-Fi is not
    /// an account problem and must not send anyone to Settings.
    @Test func anOrdinaryFailureStillReadsAsOne() {
        for error in [HTTPError.status(code: 503, body: ""), Transport.offline] as [any Error] {
            let message = LibraryStore.message(for: error)
            #expect(message.contains("Check your connection"))
        }
    }
}
