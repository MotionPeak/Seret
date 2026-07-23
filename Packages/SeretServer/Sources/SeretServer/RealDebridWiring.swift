import DebridCore

/// Builds a `TorrentsClient` backed by a static Real-Debrid token (no Keychain, no refresh) —
/// the same static-Bearer path the apps use for paste-token sign-in.
func makeTorrentsClient(rdToken: String) async throws -> TorrentsClient {
    let session = RealDebridSession(store: InMemoryTokenStore())
    try await session.establishStaticToken(rdToken)
    return TorrentsClient(tokens: session)
}
