import DebridCore
import Observation

/// Drives the Add flow for one chosen title: fetch cached streams, rank by
/// original-language+quality, and add the pick to RD.
@MainActor
@Observable
public final class AddStore {
    public enum State: Equatable {
        case idle, loadingStreams, streams, noStreams, failed(String)
        case adding, added(TorrentInfo), addFailed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var ranked: [CachedStream] = []
    public private(set) var best: CachedStream?
    public private(set) var isFallback = false
    /// All matching versions — cached AND uncached — for the "Show all versions" browse list.
    /// Empty until `loadAllVersions()` runs.
    public private(set) var allVersions: [CachedStream] = []

    private let imdbID: String
    private let kind: StreamQuery.Kind
    private let originalLanguage: String?
    private let title: String
    private let year: Int?
    private let streamSource: StreamSource
    private let addService: AddProviding
    /// When set, this store grabs the whole-season pack for that season: it queries an episode
    /// (packs come back alongside single episodes) but ranks only full-season releases. Adding one
    /// caches every episode at once — RD selects all the pack's files and the library expands it.
    private let seasonPack: Int?

    public init(imdbID: String, kind: StreamQuery.Kind, originalLanguage: String?,
                streamSource: StreamSource, add: AddProviding, seasonPack: Int? = nil,
                title: String = "", year: Int? = nil) {
        self.imdbID = imdbID; self.kind = kind; self.originalLanguage = originalLanguage
        self.streamSource = streamSource; self.addService = add; self.seasonPack = seasonPack
        self.title = title; self.year = year
    }

    public func loadStreams() async {
        state = .loadingStreams
        do {
            let query = StreamQuery(imdbID: imdbID, kind: kind, originalLanguage: originalLanguage,
                                    title: title, year: year)
            let found = try await streamSource.streams(for: query)
            // Season-pack mode narrows the results to full-season releases before ranking; the
            // normal episode/movie path ranks everything.
            let candidates = seasonPack.map { found.seasonPacks(forSeason: $0) } ?? found
            ranked = candidates.rankedFor(originalLanguage: originalLanguage)
            if let match = candidates.bestMatch(originalLanguage: originalLanguage) {
                best = match.stream; isFallback = match.isFallback; state = .streams
            } else {
                best = nil; isFallback = false; state = .noStreams
            }
        } catch {
            state = .failed("Couldn't find sources. Check your connection and try again.")
        }
    }

    /// How many ranked candidates "Get best" will try before giving up. ElfCache "cached" isn't
    /// a guarantee a torrent is instant for THIS account, so the top pick sometimes isn't
    /// instantly available — fall through to the next best instead of failing outright.
    private static let maxAddAttempts = 6

    /// Adds the best available version, automatically falling back to the next-ranked one if a
    /// pick turns out not to be instantly available (each failed attempt self-cleans in RD).
    public func addBest() async {
        guard !ranked.isEmpty else { return }
        state = .adding
        for stream in ranked.prefix(Self.maxAddAttempts) {
            do {
                let info = try await addService.add(infoHash: stream.infoHash)
                best = stream            // the version that actually landed
                state = .added(info)
                return
            } catch {
                continue                 // not instant for this account → try the next
            }
        }
        state = .addFailed("None of the cached versions were instantly available. Try again later.")
    }

    /// Ranked, title/year-gated candidates INCLUDING uncached torrents — the input to a
    /// "request download" when nothing is instantly cached. Returns [] on error so the caller
    /// surfaces "no version available." The download lifecycle itself lives in `DownloadStore`.
    public func uncachedCandidates() async -> [CachedStream] {
        let query = StreamQuery(imdbID: imdbID, kind: kind, originalLanguage: originalLanguage,
                                title: title, year: year)
        guard let found = try? await streamSource.streams(for: query, includeUncached: true) else { return [] }
        let candidates = seasonPack.map { found.seasonPacks(forSeason: $0) } ?? found
        return candidates.rankedFor(originalLanguage: originalLanguage)
    }

    /// Populate `allVersions` with the ranked cached+uncached list for the "Show all versions"
    /// browse UI (one uncached-inclusive query returns both, each tagged `isCached`).
    public func loadAllVersions() async {
        allVersions = await uncachedCandidates()
    }

    public func add(stream: CachedStream) async {
        state = .adding
        do {
            let info = try await addService.add(infoHash: stream.infoHash)
            state = .added(info)
        } catch let RDAddError.notInstant(torrentID) {
            state = .addFailed("That version isn't instantly available (RD id \(torrentID)).")
        } catch {
            state = .addFailed("Couldn't add this to Real-Debrid. Try another version.")
        }
    }
}
