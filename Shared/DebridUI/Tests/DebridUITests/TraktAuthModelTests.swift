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
}
