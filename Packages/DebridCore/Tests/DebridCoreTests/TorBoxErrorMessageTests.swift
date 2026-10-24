import Testing
@testable import DebridCore

/// A Cloudflare 502/503 answers HTML, not TorBox's envelope, so the error has no detail — and the
/// detail used to be the whole message, which left the library error and sign-in failure blank.
@Suite struct TorBoxErrorMessageTests {
    @Test func emptyDetailOnA5xxSaysTorBoxIsNotResponding() {
        let error = TorBoxError.api(code: "HTTP_503", detail: "", status: 503)
        #expect(error.userMessage == "TorBox isn't responding right now (HTTP 503). Try again in a few minutes.")
    }

    @Test func emptyDetailUsesTheActualStatus() {
        let error = TorBoxError.api(code: "HTTP_502", detail: "  ", status: 502)
        #expect(error.userMessage == "TorBox isn't responding right now (HTTP 502). Try again in a few minutes.")
    }

    @Test func emptyDetailOnA4xxIsNeutral() {
        let error = TorBoxError.api(code: "HTTP_404", detail: "", status: 404)
        #expect(error.userMessage == "TorBox returned an error (HTTP 404).")
    }

    @Test func aDetailIsStillShown() {
        let error = TorBoxError.api(code: "DATABASE_ERROR", detail: "Database is down.", status: 200)
        #expect(error.userMessage == "Database is down.")
    }

    @Test func freePlanKeepsItsMessage() {
        let error = TorBoxError.api(code: "PLAN_RESTRICTED_FEATURE", detail: "", status: 403)
        #expect(error.userMessage == "TorBox's API needs a paid plan.")
    }
}
