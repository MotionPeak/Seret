import Vapor
import DebridCore

private struct LetterboxdWriterKey: StorageKey { typealias Value = LetterboxdDiaryWriter }
private struct LetterboxdWatchlistWriterKey: StorageKey { typealias Value = LetterboxdWatchlistWriter }

extension Application {
    /// Built lazily: the browser is only contacted when something is actually written, so a
    /// Chromium container that is down does not stop the rest of the server starting.
    var letterboxdWriter: LetterboxdDiaryWriter {
        get {
            if let existing = storage[LetterboxdWriterKey.self] { return existing }
            let writer = LetterboxdWiring.makeWriter()
            storage[LetterboxdWriterKey.self] = writer
            return writer
        }
        set { storage[LetterboxdWriterKey.self] = newValue }
    }

    var letterboxdWatchlistWriter: LetterboxdWatchlistWriter {
        get {
            if let existing = storage[LetterboxdWatchlistWriterKey.self] { return existing }
            let writer = LetterboxdWiring.makeWatchlistWriter()
            storage[LetterboxdWatchlistWriterKey.self] = writer
            return writer
        }
        set { storage[LetterboxdWatchlistWriterKey.self] = newValue }
    }
}

struct WatchlistChangeRequest: Content {
    let tmdbID: Int
    /// False removes, true adds. Named for the wire property the API actually validates.
    let inWatchlist: Bool
}

struct DiaryEntryRequest: Content {
    let tmdbID: Int
    var rating: Int?
    var watchedAt: Date?
    var rewatch: Bool?
}

/// Turns a write failure into a response that names the cause.
///
/// The three failures in practice need three different fixes — sign the browser back in, go solve
/// a Cloudflare challenge, or repair the route to the browser container — and Vapor's default for
/// an unrecognised error is a 500 reading "Something went wrong", which points at none of them.
func diaryAbort(for error: any Error) -> Abort {
    switch error {
    case LetterboxdError.notAuthenticated:
        return Abort(.unauthorized, reason: "the browser's Letterboxd session is signed out")
    case LetterboxdError.challenged:
        return Abort(.serviceUnavailable, reason: "Cloudflare is challenging the browser")
    case LetterboxdError.filmNotFound:
        return Abort(.notFound, reason: "Letterboxd has no film for that TMDB id")
    case LetterboxdError.structureChanged:
        return Abort(.badGateway, reason: "the film page carries no film uid any more")
    case LetterboxdError.transient(let message):
        return Abort(.badGateway, reason: message)
    case ChromeError.navigationTimedOut(let requested, let at, let state):
        return Abort(.badGateway,
                     reason: "the browser never reached \(requested) - it is at \(at) (\(state))")
    default:
        // Anything else is the browser being undrivable rather than Letterboxd refusing, and the
        // error's own description is the only thing that says which.
        return Abort(.badGateway, reason: "could not drive the browser: \(error)")
    }
}

/// `POST /api/letterboxd/diary` — append one diary entry.
///
/// Deliberately a plain endpoint with no queue: Plan A exists to prove the captured form contract
/// against the real site with one considered write. The outbox drain and the app relay are Plan B.
func registerLetterboxdRoutes(_ app: Application) {
    app.post("api", "letterboxd", "diary") { req async throws -> HTTPStatus in
        let body = try req.content.decode(DiaryEntryRequest.self)
        let write = LetterboxdWrite(tmdbID: body.tmdbID,
                                    rating: body.rating,
                                    watchedAt: body.watchedAt,
                                    rewatch: body.rewatch ?? false)
        do {
            try await req.application.letterboxdWriter.write(write)
        } catch {
            throw diaryAbort(for: error)
        }
        return .ok
    }

    /// `PATCH /api/v0/me/watchlist/{lid}`, by another name.
    ///
    /// A POST rather than a DELETE because it carries both directions: the same call adds a film
    /// back, and an endpoint that can only remove would need a sibling to undo a mistake.
    app.post("api", "letterboxd", "watchlist") { req async throws -> HTTPStatus in
        let body = try req.content.decode(WatchlistChangeRequest.self)
        let write = LetterboxdWrite(tmdbID: body.tmdbID,
                                    operation: .watchlist,
                                    inWatchlist: body.inWatchlist)
        do {
            try await req.application.letterboxdWatchlistWriter.write(write)
        } catch {
            throw diaryAbort(for: error)
        }
        return .ok
    }
}
