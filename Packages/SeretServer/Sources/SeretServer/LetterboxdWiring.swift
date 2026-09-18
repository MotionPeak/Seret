import Foundation
import DebridCore

/// Builds the diary writer.
///
/// Deliberately in a file that does NOT import Vapor: Vapor exports an `AsyncHTTPClient.HTTPClient`
/// that collides with `DebridCore.HTTPClient`, and the module cannot be used to disambiguate
/// because `DebridCore` is also a type inside it. Keeping the construction out of Vapor's reach is
/// simpler than fighting the name.
enum LetterboxdWiring {
    static func makeWriter() -> LetterboxdDiaryWriter {
        LetterboxdDiaryWriter(
            chrome: ChromeSession(transport: WebSocketCDPTransport()),
            resolver: LetterboxdFilmResolver(http: HTTPClient(), map: LetterboxdFilmMap()))
    }
}
