import Testing
import Foundation
@testable import SeretServer

/// Chrome's DevTools HTTP endpoint answers "Host header is specified and is not an IP address or
/// localhost" to anything else, and a docker service name is exactly that — measured against the
/// NAS browser, which refused `Host: letterboxd-chromium:9223` while accepting `Host: 172.18.0.7`.
@Suite struct WebSocketCDPTransportTests {
    @Test func containerNameHasToBecomeAnAddress() {
        #expect(WebSocketCDPTransport.hostNeedsResolving("letterboxd-chromium"))
    }

    @Test func addressesAndLocalhostAreLeftAlone() {
        #expect(!WebSocketCDPTransport.hostNeedsResolving("localhost"))
        #expect(!WebSocketCDPTransport.hostNeedsResolving("127.0.0.1"))
        #expect(!WebSocketCDPTransport.hostNeedsResolving("172.18.0.7"))
        #expect(!WebSocketCDPTransport.hostNeedsResolving("::1"))
    }

    @Test func swappingTheHostKeepsSchemeAndPort() {
        #expect(WebSocketCDPTransport.base("http://letterboxd-chromium:9223", host: "172.18.0.7")
                == "http://172.18.0.7:9223")
    }

    @Test func aBaseWithoutAPortSurvives() {
        #expect(WebSocketCDPTransport.base("http://letterboxd-chromium", host: "172.18.0.7")
                == "http://172.18.0.7")
    }
}
