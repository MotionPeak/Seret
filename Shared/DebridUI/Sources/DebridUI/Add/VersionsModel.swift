import DebridCore
import Observation

/// The Versions sheet's load-and-pick engine — every cached and uncached release for one movie or
/// one episode, drawn Instant above Download with each block split into "larger files" and
/// "recommended" (`groupedByAvailability`), plus picking one: an instant release plays right away,
/// anything else becomes a tracked download.
///
/// Lifted out of tvOS's (and the iPhone's identical) `VersionsScreen`, which held this same
/// resolve → select → loadAllVersions → split sequence, and the same instant-first pick, inline in
/// the view. Both platforms now drive this one tested engine instead.
@MainActor
@Observable
public final class VersionsModel {
    public enum Phase: Equatable { case loading, ready, empty, failed }

    public private(set) var phase: Phase = .loading
    /// The list as drawn: Instant above Download, each with its oversized releases first. Nothing
    /// is dropped, and order inside every part is the ranking's.
    public private(set) var groups: [VersionGroup] = []
    /// The infoHash currently being picked — nil once it lands (played, downloading, or failed).
    public private(set) var picking: String?

    private let hit: SearchHit
    private let target: AcquisitionStore.Target
    private let flow: AddFlowStore?
    private let downloads: DownloadStore?
    private let onAdded: @MainActor () -> Void

    public init(hit: SearchHit, target: AcquisitionStore.Target, flow: AddFlowStore?,
                downloads: DownloadStore?, onAdded: @escaping @MainActor () -> Void) {
        self.hit = hit
        self.target = target
        self.flow = flow
        self.downloads = downloads
        self.onAdded = onAdded
    }

    /// "Dune: Part Two" / "Breaking Bad — S1·E3". Falls back to the search hit's own title until
    /// the flow's TMDB details resolve.
    public var title: String {
        let base: String
        if let flowTitle = flow?.title, !flowTitle.isEmpty {
            base = flowTitle
        } else {
            base = hit.result.title ?? hit.result.name ?? ""
        }
        guard case let .episode(season, number) = target else { return base }
        return "\(base) \u{2014} S\(season)\u{00B7}E\(number)"
    }

    /// What a pick here files under — the Versions list's `DownloadTarget` form (titled with the
    /// resolved title rather than derived from a `MediaItem`). nil while signed out.
    public var downloadTarget: DownloadTarget? {
        guard let tmdbID = flow?.tmdbID else { return nil }
        return DownloadTarget.version(tmdbID: tmdbID, kind: hit.kind, title: title,
                                      posterPath: flow?.posterPath, target: target)
    }

    public var downloadStatus: DownloadStatus? {
        downloadTarget.flatMap { downloads?.status(for: $0) }
    }

    /// resolve → (an episode target also selects its season + episode, so the query is per
    /// `series(s,e)` rather than the whole show) → loadAllVersions → group.
    public func load() async {
        guard let flow else { phase = .failed; return }
        await flow.resolve()
        if case let .episode(season, number) = target {
            await flow.selectSeason(season)
            await flow.selectEpisode(number)
        }
        guard let add = flow.add else { phase = .failed; return }
        await add.loadAllVersions()
        groups = add.allVersions.groupedByAvailability(episodesInSeason: nil)
        phase = add.allVersions.isEmpty ? .empty : .ready
    }

    /// A row's Hebrew level, for its mark: the search's evidence, which the ranking already used.
    public func hebrew(for stream: CachedStream) -> HebrewSubtitles {
        flow?.add?.hebrew(for: stream) ?? .none
    }

    /// Instant → add & play, refresh the library. Anything else → a tracked download for exactly
    /// that release. A second pick while one is already running is ignored (mirrors
    /// `TitleAcquirer.play`'s busy guard).
    public func pick(_ stream: CachedStream) async -> TitleAcquirer.Outcome {
        guard picking == nil, let flow else { return .failed("") }
        picking = stream.infoHash
        defer { picking = nil }

        if let request = await flow.instantPlay(stream) {
            onAdded()
            return .play(request)
        }
        guard let downloadTarget, let downloads else {
            return .failed("Not signed in to Real\u{2011}Debrid.")
        }
        await downloads.request(downloadTarget, candidates: [stream])
        if case let .failed(message)? = downloads.status(for: downloadTarget)?.phase {
            return .failed(message)
        }
        return .downloadStarted
    }
}
