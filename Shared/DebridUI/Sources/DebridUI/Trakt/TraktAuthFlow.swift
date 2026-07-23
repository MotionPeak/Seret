import DebridCore

@MainActor
public protocol TraktAuthFlow {
    func begin() async throws -> TraktDeviceCode
    func awaitLink(_ code: TraktDeviceCode) async throws
}

@MainActor
public struct LiveTraktAuthFlow: TraktAuthFlow {
    let client: TraktClient
    let session: TraktSession

    public init(client: TraktClient, session: TraktSession) {
        self.client = client
        self.session = session
    }

    public func begin() async throws -> TraktDeviceCode {
        try await client.startDeviceCode()
    }

    public func awaitLink(_ code: TraktDeviceCode) async throws {
        let token = try await client.awaitToken(for: code)
        try await session.establish(token)
    }
}
