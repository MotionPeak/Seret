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
        // One session for both: the resolver and the write drive the same browser, and a second
        // one would fight it for the page.
        let chrome = ChromeSession(transport: WebSocketCDPTransport())
        return LetterboxdDiaryWriter(chrome: chrome, resolver: ChromeFilmResolver(chrome: chrome))
    }

    static func makeWatchlistWriter() -> LetterboxdWatchlistWriter {
        let chrome = ChromeSession(transport: WebSocketCDPTransport())
        return LetterboxdWatchlistWriter(chrome: chrome, resolver: ChromeFilmResolver(chrome: chrome))
    }
}
