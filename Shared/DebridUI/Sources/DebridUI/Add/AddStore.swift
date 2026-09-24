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
    /// Hebrew-subtitle evidence for this store's versions, by info hash. Drives the badges and the
    /// Hebrew term of the ranking.
    public private(set) var subtitles: SubtitleEvidenceSet = .empty

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
    /// How many ranked candidates "Get best" will try before giving up. ElfCache "cached" isn't
    /// a guarantee a torrent is instant for THIS account, so the top pick sometimes isn't
    /// instantly available — fall through to the next best instead of failing outright.
    private let maxAddAttempts: Int
    private let subtitleEvidence: SubtitleEvidenceProviding?
    private let subtitleTarget: SubtitleTarget?
    /// How long the list waits for the Hebrew search once the versions are in. Past it, the list
    /// shows; a late answer adds badges but moves nothing.
    private let hebrewWait: Duration
    /// One search per store, shared by the list and "Get best".
    private var hebrewSearch: Task<[SubtitleResult]?, Never>?

    public init(imdbID: String, kind: StreamQuery.Kind, originalLanguage: String?,
                streamSource: StreamSource, add: AddProviding, seasonPack: Int? = nil,
                title: String = "", year: Int? = nil, maxAddAttempts: Int = 6,
                subtitleEvidence: SubtitleEvidenceProviding? = nil,
                subtitleTarget: SubtitleTarget? = nil,
                hebrewWait: Duration = .seconds(3)) {
        self.imdbID = imdbID; self.kind = kind; self.originalLanguage = originalLanguage
        self.streamSource = streamSource; self.addService = add; self.seasonPack = seasonPack
        self.title = title; self.year = year; self.maxAddAttempts = maxAddAttempts
        self.subtitleEvidence = subtitleEvidence; self.subtitleTarget = subtitleTarget
        self.hebrewWait = hebrewWait
    }

    public func loadStreams() async {
        state = .loadingStreams
        let hebrew = startHebrewSearch()
        do {
            let query = StreamQuery(imdbID: imdbID, kind: kind, originalLanguage: originalLanguage,
                                    title: title, year: year)
            let found = try await streamSource.streams(for: query)
            // Season-pack mode narrows the results to full-season releases before ranking; the
            // normal episode/movie path ranks everything.
            let candidates = seasonPack.map { found.seasonPacks(forSeason: $0) } ?? found
            ranked = await rank(candidates, hebrew: hebrew)
            if let first = ranked.first {
                best = first
                isFallback = first.audioTier(relativeTo: originalLanguage) == 2
                state = .streams
            } else {
                best = nil; isFallback = false; state = .noStreams
            }
        } catch {
            state = .failed("Couldn't find sources. Check your connection and try again.")
        }
    }

    /// Adds the best available version, automatically falling back to the next-ranked one if a
    /// pick turns out not to be instantly available (each failed attempt self-cleans in RD).
    ///
    /// A version Real-Debrid refuses as copyright-flagged (HTTP 451) does not spend an attempt:
    /// that is one request that creates nothing, and the blocklist says nothing about the next
    /// candidate, which is a different torrent. Refusals are bounded separately so a title whose
    /// whole top of the list is flagged still cannot turn into a request storm.
    public func addBest() async {
        guard !ranked.isEmpty else { return }
        state = .adding
        var attempts = 0
        var probes = 0
        for stream in ranked {
            guard attempts < maxAddAttempts, probes < maxAddAttempts * 2 else { break }
            do {
                let info = try await addService.add(infoHash: stream.infoHash)
                best = stream            // the version that actually landed
                state = .added(info)
                return
            } catch RDAddError.blocked {
                probes += 1
                continue
            } catch {
                attempts += 1
                continue                 // not instant for this account → try the next
            }
        }
        state = .addFailed("None of the cached versions were instantly available. Try again later.")
    }

    /// Ranked, title/year-gated candidates INCLUDING uncached torrents — the input to a
    /// "request download" when nothing is instantly cached. Returns [] on error so the caller
    /// surfaces "no version available." The download lifecycle itself lives in `DownloadStore`.
    public func uncachedCandidates() async -> [CachedStream] {
        let hebrew = startHebrewSearch()
        let query = StreamQuery(imdbID: imdbID, kind: kind, originalLanguage: originalLanguage,
                                title: title, year: year)
        guard let found = try? await streamSource.streams(for: query, includeUncached: true) else { return [] }
        let candidates = seasonPack.map { found.seasonPacks(forSeason: $0) } ?? found
        return await rank(candidates, hebrew: hebrew)
    }

    /// Populate `allVersions` with the ranked cached+uncached list for the "Show all versions"
    /// browse UI (one uncached-inclusive query returns both, each tagged `isCached`).
    public func loadAllVersions() async {
        allVersions = await uncachedCandidates()
    }

    /// The Hebrew level of one version, for its row's badge.
    public func hebrew(for stream: CachedStream) -> HebrewSubtitles {
        subtitles.hebrew(forVersion: stream.infoHash)
    }

    private func startHebrewSearch() -> Task<[SubtitleResult]?, Never>? {
        if let hebrewSearch { return hebrewSearch }
        guard let provider = subtitleEvidence, let target = subtitleTarget else { return nil }
        let language = originalLanguage
        let search = Task {
            await provider.hebrewResults(contentKey: target.contentKey, query: target.query,
                                         originalLanguage: language)
        }
        hebrewSearch = search
        return search
    }

    /// Rank with whatever Hebrew evidence is in by the deadline. Release-name tags need no search
    /// and always count. A search answering after the deadline adds its badges but moves nothing:
    /// a list that re-sorts under the viewer's focus is worse than one that is a moment behind.
    private func rank(_ candidates: [CachedStream],
                      hebrew: Task<[SubtitleResult]?, Never>?) async -> [CachedStream] {
        var results: [SubtitleResult] = []
        if let hebrew {
            if let arrived = await valueIfReady(of: hebrew, within: hebrewWait) {
                results = arrived ?? []
            } else {
                Task { [weak self] in
                    let late = await hebrew.value
                    self?.addLateBadges(for: candidates, results: late ?? [])
                }
            }
        }
        let evidence = SubtitleEvidenceSet.candidates(candidates, hebrewResults: results,
                                                      originalLanguage: originalLanguage)
        subtitles = subtitles.merging(evidence)
        return candidates.rankedFor(originalLanguage: originalLanguage, subtitles: evidence)
    }

    private func addLateBadges(for candidates: [CachedStream], results: [SubtitleResult]) {
        subtitles = subtitles.merging(.candidates(candidates, hebrewResults: results,
                                                  originalLanguage: originalLanguage))
    }

    /// Try to add a specific version as an INSTANT (already-cached) torrent and return its info if
    /// RD has it ready — otherwise nil (the instant add self-cleans the non-instant torrent). Used
    /// to play a picked version immediately when possible, falling back to a download when not.
    /// Does not touch `state` (it's a side query, not the main add flow).
    public func tryInstantAdd(_ stream: CachedStream) async -> TorrentInfo? {
        try? await addService.add(infoHash: stream.infoHash)
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
