import Testing
import Vapor
import DebridCore
@testable import SeretServer

/// A write that fails has to say which thing failed. "Something went wrong" costs whoever is
/// holding the outbox a blind debugging session: a signed-out browser, a Cloudflare challenge and
/// an unreachable container all need different fixes.
@Suite struct LetterboxdRouteErrorTests {
    @Test func aSignedOutBrowserIsNotAServerFault() {
        let abort = diaryAbort(for: LetterboxdError.notAuthenticated)
        #expect(abort.status == .unauthorized)
        #expect(abort.reason.contains("signed out"))
    }

    @Test func aChallengeSaysToGoSolveIt() {
        #expect(diaryAbort(for: LetterboxdError.challenged).status == .serviceUnavailable)
        #expect(diaryAbort(for: LetterboxdError.challenged).reason.contains("Cloudflare"))
    }

    @Test func anUnknownTMDBIdIsNotFound() {
        #expect(diaryAbort(for: LetterboxdError.filmNotFound).status == .notFound)
    }

    @Test func letterboxdsOwnMessageSurvives() {
        #expect(diaryAbort(for: LetterboxdError.transient("save-diary-entry returned 429"))
                    .reason.contains("429"))
    }

    /// A page that never loaded is not "something went wrong": where the browser stopped is the
    /// whole diagnosis.
    @Test func aPageThatNeverLoadedSaysWhereItStopped() {
        let abort = diaryAbort(for: ChromeError.navigationTimedOut(
            requested: "https://letterboxd.com/film/speed/",
            at: "https://letterboxd.com/sign-in/", state: "complete"))
        #expect(abort.status == .badGateway)
        #expect(abort.reason.contains("sign-in"))
    }

    /// The case that cost a blind hour: the browser was fine, the container name was not.
    @Test func anUnreachableBrowserNamesItself() {
        let error = WebSocketCDPTransport.TransportError.unresolvableHost("letterboxd-chromium")
        #expect(diaryAbort(for: error).reason.contains("letterboxd-chromium"))
    }
}
