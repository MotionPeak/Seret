import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor @Suite struct TraktAuthModelTests {
    final class FakeFlow: TraktAuthFlow {
        var code = TraktDeviceCode(deviceCode: "DC", userCode: "AB12",
                                   verificationURL: "https://trakt.tv/activate", expiresIn: 600, interval: 5)
        var linked = false
        func begin() async throws -> TraktDeviceCode { code }
        func awaitLink(_ code: TraktDeviceCode) async throws { linked = true }
    }

    @Test func runReachesLinkedAndCallsBack() async throws {
        let flow = FakeFlow()
        var linkedCb = false
        let model = TraktAuthModel(flow: flow, onLinked: { linkedCb = true })
        await model.run()
        #expect(model.phase == .linked)
        #expect(linkedCb)
    }

    @Test func showsUserCodeWhileAwaiting() async throws {
        final class HangingFlow: TraktAuthFlow {
            let code = TraktDeviceCode(deviceCode: "DC", userCode: "WXYZ",
                                       verificationURL: "https://trakt.tv/activate", expiresIn: 600, interval: 5)
            func begin() async throws -> TraktDeviceCode { code }
            func awaitLink(_ code: TraktDeviceCode) async throws { try await Task.sleep(for: .seconds(60)) }
        }
        let model = TraktAuthModel(flow: HangingFlow(), onLinked: {})
        let task = Task { await model.run() }
        try await Task.sleep(for: .milliseconds(80))
        if case let .awaiting(code) = model.phase { #expect(code.userCode == "WXYZ") }
        else { Issue.record("expected awaiting phase, got \(model.phase)") }
        task.cancel()
    }

    @Test func failureSurfacesMessage() async throws {
        final class FailingFlow: TraktAuthFlow {
            func begin() async throws -> TraktDeviceCode { throw TraktAuthError.deviceCodeExpired }
            func awaitLink(_ code: TraktDeviceCode) async throws {}
        }
        let model = TraktAuthModel(flow: FailingFlow(), onLinked: {})
        await model.run()
        if case let .failed(msg) = model.phase { #expect(!msg.isEmpty) }
        else { Issue.record("expected failed phase") }
    }

    /// The regression that cost days: a deleted API app fell through to the catch-all
    /// "check your connection", which is false and points the owner at the wrong system entirely.
    @Test func aDisownedClientIDBlamesTheCredentialsNotTheNetwork() async throws {
        final class DisownedFlow: TraktAuthFlow {
            func begin() async throws -> TraktDeviceCode { throw TraktAuthError.unknownClient }
            func awaitLink(_ code: TraktDeviceCode) async throws {}
        }
        let model = TraktAuthModel(flow: DisownedFlow(), onLinked: {})
        await model.run()
        guard case let .failed(msg) = model.phase else {
            Issue.record("expected failed phase, got \(model.phase)"); return
        }
        #expect(msg.contains("no longer recognises"))
        // The whole point: it must NOT send anyone hunting a network fault.
        #expect(!msg.lowercased().contains("connection"))
    }
}

/// How a failed Trakt sync explains itself in Settings.
@MainActor @Suite struct TraktSyncMessageTests {
    private func http(_ code: Int, _ body: String = "") -> Error {
        HTTPError.status(code: code, body: body)
    }

    @Test func disownedCredentialsAreNamedOutright() {
        let msg = AppSession.syncMessage(for: TraktAuthError.unknownClient)
        #expect(msg.contains("no longer recognises"))
        #expect(!msg.lowercased().contains("wait"))
    }

    /// A bare 403 is genuinely ambiguous — a throttled network and a deleted app look identical —
    /// so it keeps the "wait, don't unlink" advice UNTIL a probe says otherwise.
    @Test func aPlain403StillReadsAsAThrottle() {
        #expect(AppSession.syncMessage(for: http(403)).contains("network"))
    }

    /// …and once the probe has confirmed the credentials are dead, the same 403 must stop telling
    /// the owner to wait. Waiting is exactly what it did for a week.
    @Test func a403IsReExplainedOnceTheProbeConfirmsDeadCredentials() {
        let msg = AppSession.syncMessage(for: http(403), credentialsRejected: true)
        #expect(msg.contains("no longer recognises"))
        #expect(!msg.lowercased().contains("wait a while"))
    }

    /// Only the ambiguous refusal is worth spending an OAuth call on.
    @Test func onlyA403WarrantsTheProbe() {
        #expect(AppSession.warrantsCredentialProbe(http(403)))
        #expect(!AppSession.warrantsCredentialProbe(http(429)))
        #expect(!AppSession.warrantsCredentialProbe(http(500)))
        #expect(!AppSession.warrantsCredentialProbe(TraktSessionError.notSignedIn))
        // Already conclusive — probing again would be a wasted call into a refusing server.
        #expect(!AppSession.warrantsCredentialProbe(TraktAuthError.unknownClient))
    }
}
