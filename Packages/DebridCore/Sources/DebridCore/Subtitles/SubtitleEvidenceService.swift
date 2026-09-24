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
    /// Hebrew subtitles OpenSubtitles has for a movie or an episode. Cached for a day; when the
    /// network fails the last answer is returned whatever its age; nil when nothing is known.
    func hebrewResults(contentKey: String, query: SubtitleQuery,
                       originalLanguage: String?) async -> [SubtitleResult]?
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
/// - What the player sees while a file plays is folded in. That is the only way an MP4's tracks
///   are ever known, and it corrects any header read.
public actor SubtitleEvidenceService: SubtitleEvidenceProviding {
    public typealias Search = @Sendable (SubtitleQuery, [String]) async throws -> [SubtitleResult]
    public typealias Resolve = @Sendable (String) async throws -> ResolvedLink
    public typealias Probe = @Sendable (URL) async -> ContainerProbe.Outcome?

    public static let searchTTL: TimeInterval = 24 * 60 * 60
    /// Stands in for "forever" — a file's tracks do not change.
    static let recordTTL: TimeInterval = 10 * 365 * 24 * 60 * 60
    /// Each read is an unrestrict plus up to two ranged requests, and a title can hold a dozen.
    /// The limit is the service's: two screens (or two web requests) share the same slots.
    static let readsAtOnce = 2

    struct SearchEntry: Codable, Sendable {
        let results: [SubtitleResult]
        /// The title's language when it was asked about, so stored-only readers apply the same
        /// guards the title page does.
        let originalLanguage: String?
    }

    private let searches: TTLFileCache<SearchEntry>
    private let recordCache: TTLFileCache<VersionSubtitleRecord>
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
                                     ttl: Self.searchTTL, now: now)
        self.recordCache = TTLFileCache(directory: directory, fileName: "version-subtitles.json",
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
        if let fresh = await searches.cached(contentKey) { return fresh.results }
        if let flight = searchesInFlight[contentKey] { return await flight.value }
        guard let search else { return await searches.stored(contentKey)?.results }
        let language = LanguageCode.normalize(originalLanguage)
        let flight = Task { [searches] () -> [SubtitleResult]? in
            do {
                let results = try await search(query, ["he"])
                    .filter { LanguageCode.normalize($0.language) == "he" }
                await searches.store(SearchEntry(results: results, originalLanguage: language),
                                     key: contentKey)
                return results
            } catch {
                return await searches.stored(contentKey)?.results   // a stale answer beats none
            }
        }
        searchesInFlight[contentKey] = flight
        let results = await flight.value
        searchesInFlight[contentKey] = nil
        return results
    }

    public func records(for sources: [MediaSource]) async -> [String: VersionSubtitleRecord] {
        var known: [String: VersionSubtitleRecord] = [:]
        var flights: [(key: String, flight: Task<VersionSubtitleRecord?, Never>)] = []
        for source in sources {
            let key = WatchKey.source(source)
            if let record = await recordCache.stored(key) {
                known[key] = record
            } else {
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
        let entry = await searches.stored(contentKey)
        return .owned(sources, records: records, hebrewResults: entry?.results ?? [],
                      originalLanguage: entry?.originalLanguage)
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
                // The header is the file's own index and replaces what playback reported meanwhile;
                // a read that found nothing never erases what playback saw.
                if found.origin == .unreadable, let existing, existing.origin == .playback { return nil }
                return found
            }
        }
        // Only once the answer is stored: cleared any sooner, a caller arriving in between would
        // find neither a record nor a flight, and read the file again.
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
