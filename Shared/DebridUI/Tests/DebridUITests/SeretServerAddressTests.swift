import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

/// The address is free text typed on a phone. It has already cost an evening: `192.168.1.179:8000`
/// instead of `:8080` produced a refused connection that the app reported as "Couldn't reach your
/// Seret server", which reads as a dead NAS rather than a wrong digit.
@Suite struct SeretServerAddressTests {

    @Test func acceptsWhatSomeoneActuallyTypes() {
        #expect(SeretServerAddress.url("192.168.1.179:8080", path: "/health")?.absoluteString
                == "http://192.168.1.179:8080/health")
    }

    @Test func keepsAnExplicitScheme() {
        #expect(SeretServerAddress.url("https://nas.local:8080", path: "/health")?.absoluteString
                == "https://nas.local:8080/health")
        #expect(SeretServerAddress.url("http://nas:8080", path: "/health")?.absoluteString
                == "http://nas:8080/health")
    }

    @Test func toleratesStrayWhitespaceAndTrailingSlashes() {
        #expect(SeretServerAddress.url("  192.168.1.179:8080///  ", path: "/health")?.absoluteString
                == "http://192.168.1.179:8080/health")
    }

    @Test func anEmptyAddressIsNoURLAtAll() {
        #expect(SeretServerAddress.url("", path: "/health") == nil)
        #expect(SeretServerAddress.url("   ", path: "/health") == nil)
    }

    /// `https` must not be mangled into `httpss` or similar by a naive prefix check.
    @Test func doesNotDoubleUpTheScheme() {
        let url = SeretServerAddress.url("https://nas:8080", path: "/health")?.absoluteString ?? ""
        #expect(!url.contains("http://https"))
        #expect(url.hasPrefix("https://"))
    }

    /// A host that happens to start with "http" is a host, not a scheme — `httpbin:8080` would
    /// otherwise be left schemeless and fail to parse.
    @Test func aHostBeginningWithHttpIsStillAHost() {
        #expect(SeretServerAddress.url("httpbin:8080", path: "/health")?.absoluteString
                == "http://httpbin:8080/health")
    }
}
