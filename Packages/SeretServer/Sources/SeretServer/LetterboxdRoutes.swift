import Vapor
import DebridCore

private struct LetterboxdWriterKey: StorageKey { typealias Value = LetterboxdDiaryWriter }

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
}

struct DiaryEntryRequest: Content {
    let tmdbID: Int
    var rating: Int?
    var watchedAt: Date?
    var rewatch: Bool?
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
        try await req.application.letterboxdWriter.write(write)
        return .ok
    }
}
