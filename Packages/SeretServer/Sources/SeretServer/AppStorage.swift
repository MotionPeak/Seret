import Vapor
import DebridCore

private struct TorrentsClientKey: StorageKey { typealias Value = TorrentsClient }

extension Application {
    var torrents: TorrentsClient {
        get {
            guard let c = storage[TorrentsClientKey.self] else {
                fatalError("TorrentsClient not configured")
            }
            return c
        }
        set { storage[TorrentsClientKey.self] = newValue }
    }
}

private struct ServerLibraryKey: StorageKey { typealias Value = ServerLibrary }

extension Application {
    var library: ServerLibrary {
        get {
            guard let l = storage[ServerLibraryKey.self] else {
                fatalError("ServerLibrary not configured")
            }
            return l
        }
        set { storage[ServerLibraryKey.self] = newValue }
    }
}

private struct TMDBClientKey: StorageKey { typealias Value = TMDBClient }

extension Application {
    /// TMDB client for on-demand detail-page enrichment (cast, credits, recommendations, runtime…).
    var tmdb: TMDBClient {
        get {
            guard let c = storage[TMDBClientKey.self] else { fatalError("TMDBClient not configured") }
            return c
        }
        set { storage[TMDBClientKey.self] = newValue }
    }
}

private struct OMDbClientKey: StorageKey { typealias Value = OMDbClient }

extension Application {
    /// Optional OMDb client for IMDb/RT/Metacritic ratings. `nil` when no OMDB_API_KEY is set —
    /// the detail route then omits the ratings row.
    var ratings: OMDbClient? {
        get { storage[OMDbClientKey.self] }
        set { storage[OMDbClientKey.self] = newValue }
    }
}

private struct TranscodeManagerKey: StorageKey { typealias Value = TranscodeManager }

extension Application {
    var transcoder: TranscodeManager {
        get {
            guard let m = storage[TranscodeManagerKey.self] else {
                fatalError("TranscodeManager not configured")
            }
            return m
        }
        set { storage[TranscodeManagerKey.self] = newValue }
    }
}
