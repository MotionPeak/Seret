import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

@MainActor
@Suite struct ServerConnectionTestTests {

    private func test(_ address: String,
                      probe: @escaping @Sendable (URL) async throws -> Void)
    -> ServerConnectionTest {
        ServerConnectionTest(address: address, probe: probe)
    }

    @Test func aServerThatAnswersIsReachable() async {
        let subject = test("192.168.1.179:8080", probe: { _ in })
        await subject.run()
        #expect(subject.result == .reachable("192.168.1.179:8080"))
    }

    /// The probe must hit the address the relay would post to, not some other URL — a test that
    /// checks a different host proves nothing.
    @Test func probesTheAddressAsTyped() async {
        let seen = Probed()
        let subject = test("nas:8080", probe: { url in seen.record(url.absoluteString) })
        await subject.run()
        #expect(seen.urls == ["http://nas:8080/health"])
    }

    @Test func anEmptyAddressSaysSoRatherThanFailing() async {
        let subject = test("  ", probe: { _ in Issue.record("should not probe") })
        await subject.run()
        #expect(subject.result == .needsAddress)
    }

    /// 🚨 The failure this exists for. A refused connection means something IS at that host and
    /// nothing is listening on that port — which is a wrong port, not a dead server. Reported as
    /// "couldn't reach", it cost an evening of reinstalling the app.
    @Test func aRefusedConnectionPointsAtThePort() async {
        let subject = test("192.168.1.179:8000",
                           probe: { _ in throw HTTPError.transport(
                               String(describing: URLError(.cannotConnectToHost))) })
        await subject.run()
        guard case .failed(let message) = subject.result else {
            Issue.record("expected .failed, got \(subject.result)"); return
        }
        #expect(message.localizedCaseInsensitiveContains("port"))
    }

    @Test func aServerAnsweringBadlyIsNotAnUnreachableOne() async {
        let subject = test("nas:8080", probe: { _ in throw HTTPError.status(code: 404, body: "") })
        await subject.run()
        guard case .failed(let message) = subject.result else {
            Issue.record("expected .failed"); return
        }
        #expect(message.contains("404"))
        #expect(!message.localizedCaseInsensitiveContains("couldn't reach"))
    }

    @Test func aGenuinelyAbsentHostSaysUnreachable() async {
        let subject = test("nas:8080",
                           probe: { _ in throw HTTPError.transport(
                               String(describing: URLError(.timedOut))) })
        await subject.run()
        guard case .failed(let message) = subject.result else {
            Issue.record("expected .failed"); return
        }
        #expect(message.localizedCaseInsensitiveContains("reach"))
    }

    @Test func runningShowsItIsRunning() async {
        let subject = test("nas:8080", probe: { _ in })
        #expect(subject.result == .untested)
        await subject.run()
        #expect(subject.result != .testing)
    }
}

private final class Probed: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    func record(_ u: String) { lock.lock(); defer { lock.unlock() }; seen.append(u) }
    var urls: [String] { lock.lock(); defer { lock.unlock() }; return seen }
}
