import Foundation

/// A link resolved for reading: its direct URL and the file name Real-Debrid gives it.
public struct ResolvedLink: Sendable, Equatable {
    public let url: URL
    public let fileName: String?
    public init(url: URL, fileName: String?) {
        self.url = url
        self.fileName = fileName
    }
}

/// Where every screen gets Hebrew-subtitle evidence. The title page and the Versions screen ask
/// with the network allowed; Home and the player ask for stored knowledge only.
public protocol SubtitleEvidenceProviding: Sendable {
    /// Hebrew subtitles OpenSubtitles has for a movie or an episode. Asked once a day: an older
    /// answer comes back at once and is refreshed behind it, and a failed search falls back to the
    /// last answer whatever its age. nil when nothing is known.
    func hebrewResults(contentKey: String, query: SubtitleQuery,
                       originalLanguage: String?) async -> [SubtitleResult]?
    /// The last search answer for a title, whatever its age, without touching the network.
    func storedHebrewResults(contentKey: String) async -> [SubtitleResult]?
    /// What each owned file carries, keyed by `WatchKey.source`. Reads the header of any file not
    /// seen before, a couple at a time.
    func records(for sources: [MediaSource]) async -> [String: VersionSubtitleRecord]
    /// Stored knowledge only, never the network. For surfaces that must not wait.
    func storedEvidence(for sources: [MediaSource], contentKey: String) async -> SubtitleEvidenceSet
    /// What the player saw while this version played.
    func recordPlayback(_ tracks: [MediaTrack], for source: MediaSource) async
}

/// Hebrew-subtitle evidence, fetched on demand and kept.
///
/// - A file's own tracks are read once, from its first bytes, and kept for good: a file never
///   changes. A transient failure is not kept, so the next visit tries again.
/// - OpenSubtitles is asked once a day per movie or episode: new subtitles appear all the time,
///   but not so fast that every visit needs to ask.
/// - What the player sees while a file plays fills in a file the header could not read — the only
///   way an MP4's tracks are ever known. A header read is final and playback never changes it.
public actor SubtitleEvidenceService: SubtitleEvidenceProviding {
    public typealias Search = @Sendable (SubtitleQuery, [String]) async throws -> [SubtitleResult]
    public typealias Resolve = @Sendable (String) async throws -> ResolvedLink
    public typealias Probe = @Sendable (URL) async -> ContainerProbe.Outcome?

    public static let searchTTL: TimeInterval = 24 * 60 * 60
    /// How long an old answer is kept as the fallback. Past it, a title not opened in a month
    /// drops out of the file, which every search rewrites whole.
    static let searchKeep: TimeInterval = 30 * 24 * 60 * 60
    /// Stands in for "forever" — a file's tracks do not change.
    static let recordTTL: TimeInterval = 10 * 365 * 24 * 60 * 60
    /// Each read is an unrestrict plus up to two ranged requests, and a title can hold a dozen.
    /// The limit is the service's: two screens (or two web requests) share the same slots.
    static let readsAtOnce = 2

    struct SearchEntry: Codable, Sendable {
        let results: [SubtitleResult]
    }

    private let searches: TTLFileCache<SearchEntry>
    private let recordCache: TTLFileCache<VersionSubtitleRecord>
    /// Each title's original language, kept apart from the search: Home and the web read it back
    /// to apply the title page's guards (a Hebrew film takes no boost; a dub that lost the film's
    /// language takes none) even when the search failed or there is no key to search with.
    private let languages: TTLFileCache<String>
    private let search: Search?
    private let resolve: Resolve
    private let probe: Probe
    private var searchesInFlight: [String: Task<[SubtitleResult]?, Never>] = [:]
    private var readsInFlight: [String: Task<VersionSubtitleRecord?, Never>] = [:]
    private var readSlotsTaken = 0
    private var readSlotQueue: [CheckedContinuation<Void, Never>] = []

    public init(directory: URL, search: Search?, resolve: @escaping Resolve,
                probe: @escaping Probe = { await ContainerProbe().tracks(at: $0) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.searches = TTLFileCache(directory: directory, fileName: "hebrew-searches.json",
                                     ttl: Self.searchTTL, keepFor: Self.searchKeep, now: now)
        self.recordCache = TTLFileCache(directory: directory, fileName: "version-subtitles.json",
                                        ttl: Self.recordTTL, now: now)
        self.languages = TTLFileCache(directory: directory, fileName: "title-languages.json",
                                      ttl: Self.recordTTL, now: now)
        self.search = search
        self.resolve = resolve
        self.probe = probe
    }

    /// Where the apps and the server keep it: Application Support where it exists, Caches on tvOS.
    public static var defaultDirectory: URL {
        WritableStorage.directory(named: "SeretSubtitleEvidence")
            ?? FileManager.default.temporaryDirectory.appending(path: "SeretSubtitleEvidence")
    }

    public func hebrewResults(contentKey: String, query: SubtitleQuery,
                              originalLanguage: String?) async -> [SubtitleResult]? {
        if let language = LanguageCode.normalize(originalLanguage) {
            await languages.update(contentKey) { $0 == language ? nil : language }
        }
        if let fresh = await searches.cached(contentKey) { return fresh.results }
        let stale = await searches.stored(contentKey)?.results
        guard let search else { return stale }
        let flight = searchFlight(for: contentKey, query: query, search: search)
        // Yesterday's answer now beats today's in a minute: new Hebrew subtitles for a title
        // appear over days, and the refresh keeps running behind this answer.
        if let stale { return stale }
        return await flight.value
    }

    public func storedHebrewResults(contentKey: String) async -> [SubtitleResult]? {
        await searches.stored(contentKey)?.results
    }

    public func records(for sources: [MediaSource]) async -> [String: VersionSubtitleRecord] {
        var known: [String: VersionSubtitleRecord] = [:]
        var flights: [(key: String, flight: Task<VersionSubtitleRecord?, Never>)] = []
        for source in sources {
            let key = WatchKey.source(source)
            // A flight first — checked before the await below, so a read that stores its answer
            // and clears its flight meanwhile cannot be started a second time from here.
            if let flight = readsInFlight[key] {
                flights.append((key, flight))
            } else if let record = await recordCache.stored(key), record.isFinal {
                known[key] = record
            } else {
                // Unknown, or only reported by the player: the header is still to be read.
                flights.append((key, readFlight(for: source)))
            }
        }
        // Every read is queued at once and takes a slot as one frees up, so a slow file holds up
        // nothing but itself.
        for (key, flight) in flights {
            if let record = await flight.value { known[key] = record }
        }
        return known
    }

    public func storedEvidence(for sources: [MediaSource], contentKey: String) async -> SubtitleEvidenceSet {
        var records: [String: VersionSubtitleRecord] = [:]
        for source in sources {
            let key = WatchKey.source(source)
            if let record = await recordCache.stored(key) { records[key] = record }
        }
        return .owned(sources, records: records,
                      hebrewResults: await searches.stored(contentKey)?.results ?? [],
                      originalLanguage: await languages.stored(contentKey))
    }

    public func recordPlayback(_ tracks: [MediaTrack], for source: MediaSource) async {
        // A downloaded subtitle is attached by the player but is not in the file.
        let observed = tracks.filter { !$0.isExternal }.map { ContainerTrack($0) }
        guard !observed.isEmpty else { return }
        await recordCache.update(WatchKey.source(source)) { existing in
            let merged = (existing ?? VersionSubtitleRecord(origin: .playback)).merging(playback: observed)
            return merged == existing ? nil : merged
        }
    }

    /// One search per title, however many screens ask: a second caller joins the first's flight.
    private func searchFlight(for contentKey: String, query: SubtitleQuery,
                              search: @escaping Search) -> Task<[SubtitleResult]?, Never> {
        if let flight = searchesInFlight[contentKey] { return flight }
        let flight = Task { await self.runSearch(contentKey, query: query, search: search) }
        searchesInFlight[contentKey] = flight
        return flight
    }

    private func runSearch(_ contentKey: String, query: SubtitleQuery,
                           search: Search) async -> [SubtitleResult]? {
        var results: [SubtitleResult]?
        do {
            let found = try await search(query, ["he"]).filter { LanguageCode.normalize($0.language) == "he" }
            await searches.store(SearchEntry(results: found), key: contentKey)
            results = found
        } catch {
            results = await searches.stored(contentKey)?.results     // a stale answer beats none
        }
        searchesInFlight[contentKey] = nil                             // once the answer is stored
        return results
    }

    /// One read per file, however many screens ask: a second caller joins the first's flight.
    private func readFlight(for source: MediaSource) -> Task<VersionSubtitleRecord?, Never> {
        let key = WatchKey.source(source)
        if let flight = readsInFlight[key] { return flight }
        let flight = Task { await self.read(source, key: key) }
        readsInFlight[key] = flight
        return flight
    }

    private func read(_ source: MediaSource, key: String) async -> VersionSubtitleRecord? {
        await takeReadSlot()
        let found = await Self.readHeader(of: source, resolve: resolve, probe: probe)
        releaseReadSlot()
        var kept: VersionSubtitleRecord?
        if let found {                                 // nil is transient: not kept, tried next visit
            kept = await recordCache.update(key) { existing in
                // The header is the file's own index and replaces what playback reported. A read
                // that found no header keeps what playback saw, and records the read as done, with
                // the name Real-Debrid gives the file: release tags (HebSubs, TS) live there.
                guard found.origin == .unreadable, let existing, existing.origin == .playback else { return found }
                return VersionSubtitleRecord(origin: .unreadable, fileName: found.fileName ?? existing.fileName,
                                             tracks: existing.tracks)
            }
        }
        // Only once the answer is stored: cleared any sooner, a caller arriving in between would
        // find neither a record nor a flight, and read the file again. (A caller already past its
        // flight check and waiting on the cache can still start a second read in that instant —
        // harmless: the same answer, written atomically.)
        readsInFlight[key] = nil
        return kept
    }

    /// Off the actor: an unrestrict and up to two ranged requests.
    private static func readHeader(of source: MediaSource, resolve: Resolve,
                                   probe: Probe) async -> VersionSubtitleRecord? {
        guard let link = try? await resolve(source.restrictedLink),
              let outcome = await probe(link.url) else { return nil }
        switch outcome {
        case .tracks(let tracks):
            return VersionSubtitleRecord(origin: .header, fileName: link.fileName, tracks: tracks)
        case .notMatroska, .unreadable:
            return VersionSubtitleRecord(origin: .unreadable, fileName: link.fileName)
        }
    }

    private func takeReadSlot() async {
        if readSlotsTaken < Self.readsAtOnce {
            readSlotsTaken += 1
            return
        }
        await withCheckedContinuation { readSlotQueue.append($0) }   // handed a slot on release
    }

    private func releaseReadSlot() {
        if readSlotQueue.isEmpty {
            readSlotsTaken -= 1
        } else {
            readSlotQueue.removeFirst().resume()
        }
    }
}
