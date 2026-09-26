import DebridCore
import Observation

/// One tested answer to the title page's three acquisition questions: play something you don't
/// own (falling back to a download when nothing is instant), track a whole season, and report
/// what each episode row is doing. tvOS held a copy of this logic inside `DetailView` and another
/// inside `MovieDownloadSection`; this is the one shared engine both platforms drive.
@MainActor
@Observable
public final class TitleAcquirer {
    public enum Outcome: Equatable {
        case play(PlaybackRequest)
        case noneInstant
        case downloadStarted
        case failed(String)
    }

    public enum SeasonPhase: Equatable {
        case idle, checking, adding, added, downloading(DownloadStatus), noFullSeason, failed(String)
    }

    public enum EpisodeAvailability: Equatable {
        case downloaded, notDownloaded, finding, downloading(Double), failed(String)
    }

    private let item: MediaItem
    /// Read lazily — the imdbID this needs lands after `DetailStore.load()` completes, not at
    /// `TitleAcquirer` construction time.
    private let makeAcquisition: @MainActor () -> AcquisitionStore?
    private let makeSeasonPack: @MainActor (Int) -> AddStore?
    private let downloads: DownloadStore?
    private let onAdded: @MainActor () -> Void

    public private(set) var finding: Set<AcquisitionStore.Target> = []
    public private(set) var requesting: Set<AcquisitionStore.Target> = []
    private var seasonPhases: [Int: SeasonPhase] = [:]

    public init(item: MediaItem,
                makeAcquisition: @escaping @MainActor () -> AcquisitionStore?,
                makeSeasonPack: @escaping @MainActor (Int) -> AddStore?,
                downloads: DownloadStore?,
                onAdded: @escaping @MainActor () -> Void) {
        self.item = item
        self.makeAcquisition = makeAcquisition
        self.makeSeasonPack = makeSeasonPack
        self.downloads = downloads
        self.onAdded = onAdded
    }

    public func isBusy(_ target: AcquisitionStore.Target) -> Bool {
        finding.contains(target) || requesting.contains(target)
    }

    /// The download key a target files under, or nil when the item has no TMDB id.
    public func downloadTarget(_ target: AcquisitionStore.Target) -> DownloadTarget? {
        switch target {
        case .movie:
            return DownloadTarget.movie(item)
        case let .episode(season, number):
            return DownloadTarget.episode(of: item, season: season, number: number)
        }
    }

    public func status(_ target: AcquisitionStore.Target) -> DownloadStatus? {
        downloadTarget(target).flatMap { downloads?.status(for: $0) }
    }

    public func cancelDownload(_ target: AcquisitionStore.Target) async {
        guard let dt = downloadTarget(target) else { return }
        await downloads?.cancel(dt)
    }

    /// Find + add the best instant version. A film with nothing instant offers a download (no
    /// download starts on its own); an episode with nothing instant starts a tracked download at
    /// once, because a show page has nowhere else to send you.
    public func play(_ target: AcquisitionStore.Target) async -> Outcome {
        guard !isBusy(target) else { return .failed("") }
        finding.insert(target)
        defer { finding.remove(target) }

        guard let acquisition = makeAcquisition() else {
            return .failed("Not signed in to Real\u{2011}Debrid.")
        }
        await acquisition.playBest(target)
        let outcome: Outcome
        switch acquisition.phase {
        case let .ready(request):
            onAdded()
            outcome = .play(request)
        case .noneCached:
            switch target {
            case .movie:
                outcome = .noneInstant
            case .episode:
                let candidates = await acquisition.uncachedCandidates(target)
                outcome = await startTrackedDownload(target, candidates: candidates)
            }
        case let .failed(message):
            outcome = .failed(message)
        default:
            outcome = .failed("")
        }
        acquisition.reset()
        return outcome
    }

    /// Request Download / Try Another Version: rank the uncached candidates and hand them to the
    /// download store. A film goes ahead even with no candidates — the store records its own
    /// failure — because that mirrors tvOS's `MovieDownloadSection`. An episode with nothing at
    /// all to download says so without filing a status, mirroring tvOS's `startEpisodeDownload`.
    public func requestDownload(_ target: AcquisitionStore.Target) async -> Outcome {
        guard !isBusy(target) else { return .failed("") }
        requesting.insert(target)
        defer { requesting.remove(target) }

        guard let acquisition = makeAcquisition() else {
            return .failed("Not signed in to Real\u{2011}Debrid.")
        }
        let candidates = await acquisition.uncachedCandidates(target)
        return await startTrackedDownload(target, candidates: candidates)
    }

    private func startTrackedDownload(_ target: AcquisitionStore.Target,
                                      candidates: [CachedStream]) async -> Outcome {
        guard let downloadTarget = downloadTarget(target) else {
            return .failed("Not signed in to Real\u{2011}Debrid.")
        }
        if case .episode = target, candidates.isEmpty {
            return .failed("No version of this episode is available to download.")
        }
        guard let downloads else { return .failed("Not signed in to Real\u{2011}Debrid.") }
        await downloads.request(downloadTarget, candidates: candidates)
        if case let .failed(message)? = downloads.status(for: downloadTarget)?.phase {
            return .failed(message)
        }
        return .downloadStarted
    }

    /// finding > the episode's own download > its season's download > owned > not downloaded.
    public func availability(of row: DetailStore.EpisodeRowInfo) -> EpisodeAvailability {
        let target = AcquisitionStore.Target.episode(season: row.season, number: row.number)
        if isBusy(target) { return .finding }
        if let status = status(target) {
            switch status.phase {
            case .queued, .downloading: return .downloading(status.fraction)
            case let .failed(message): return .failed(message)
            case .ready: break   // about to leave the store as the library refreshes
            }
        }
        if let tmdbID = item.tmdbID,
           let status = downloads?.status(forContentKey: DownloadKey.season(showTmdbID: tmdbID,
                                                                            season: row.season)) {
            switch status.phase {
            case .queued, .downloading: return .downloading(status.fraction)
            case let .failed(message): return .failed(message)
            case .ready: break
            }
        }
        return row.isDownloaded ? .downloaded : .notDownloaded
    }

    /// A tracked season download in the store wins over the stored phase — it is the one that
    /// survives a relaunch, while `seasonPhases` is only this page's memory of the last attempt.
    public func seasonPhase(_ season: Int) -> SeasonPhase {
        if let tmdbID = item.tmdbID,
           let status = downloads?.status(forContentKey: DownloadKey.season(showTmdbID: tmdbID,
                                                                            season: season)) {
            switch status.phase {
            case .queued, .downloading: return .downloading(status)
            case let .failed(message): return .failed(message)
            case .ready: break
            }
        }
        return seasonPhases[season] ?? .idle
    }

    /// checking → pack found: adding → added (`onAdded`) | no pack: uncached candidates → tracked
    /// download (downloading, via the store) | none at all: `.noFullSeason` | AddStore failure:
    /// `.failed(message)`.
    public func downloadSeason(_ season: Int) async {
        seasonPhases[season] = .checking
        guard let pack = makeSeasonPack(season) else {
            seasonPhases[season] = .failed("Not signed in to Real\u{2011}Debrid.")
            return
        }
        await pack.loadStreams()
        switch pack.state {
        case .streams:
            seasonPhases[season] = .adding
            await pack.addBest()
            switch pack.state {
            case .added:
                seasonPhases[season] = .added
                onAdded()
            case let .addFailed(message):
                seasonPhases[season] = .failed(message)
            default:
                seasonPhases[season] = .failed("")
            }
        case .noStreams:
            let candidates = await pack.uncachedCandidates()
            guard !candidates.isEmpty, let target = DownloadTarget.season(of: item, season) else {
                seasonPhases[season] = .noFullSeason
                return
            }
            await downloads?.request(target, candidates: candidates)
            if case let .failed(message)? = downloads?.status(for: target)?.phase {
                seasonPhases[season] = .failed(message)
            } else {
                // The live status (read by `seasonPhase(_:)` above) now carries `.downloading` —
                // this local phase only matters again if the download later leaves the store.
                seasonPhases[season] = .idle
            }
        case let .failed(message):
            seasonPhases[season] = .failed(message)
        default:
            break
        }
    }
}
