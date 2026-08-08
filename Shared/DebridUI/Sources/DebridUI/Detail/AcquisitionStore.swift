import DebridCore
import Observation

/// Turns a title you do not own into something playable: find the cached releases, add the best one
/// to Real-Debrid, and hand back a `PlaybackRequest`.
///
/// This existed twice before — once inside the Add screen for movies, once inline in the tvOS
/// Detail view for episodes — and would have become four copies across the two apps. It lives here
/// so both platforms call one tested path, and so the request it builds is keyed the same way the
/// library keys it.
@MainActor
@Observable
public final class AcquisitionStore {
    /// What to acquire. A movie is the title itself; an episode is addressed by season/number,
    /// because that is all a show you do not own can tell us.
    public enum Target: Equatable, Hashable {
        case movie
        case episode(season: Int, number: Int)

        var streamKind: StreamQuery.Kind {
            switch self {
            case .movie: .movie
            case let .episode(season, number): .series(season: season, episode: number)
            }
        }
    }

    public enum Phase: Equatable {
        case idle
        case finding                    // asking the indexers what exists
        case adding                     // handing the pick to Real-Debrid
        case ready(PlaybackRequest)     // playable now
        case noneCached                 // nothing instant — the caller offers a download
        case failed(String)
    }

    public private(set) var phase: Phase = .idle

    private let item: MediaItem
    /// Builds the engine for one target. Injected because it needs the RD session and the stream
    /// source, which live on `AppSession`; nil when the app has no session (signed out).
    private let makeAdd: @MainActor (StreamQuery.Kind) -> AddStore?

    public init(item: MediaItem, makeAdd: @escaping @MainActor (StreamQuery.Kind) -> AddStore?) {
        self.item = item
        self.makeAdd = makeAdd
    }

    public func reset() { phase = .idle }

    /// Find the best instantly-available version and add it. Ends in `.ready` (play it), in
    /// `.noneCached` (offer a download), or in `.failed`.
    public func playBest(_ target: Target) async {
        phase = .finding
        guard let add = makeAdd(target.streamKind) else {
            phase = .failed("Not signed in to Real-Debrid.")
            return
        }
        await add.loadStreams()
        switch add.state {
        case .noStreams:
            phase = .noneCached
            return
        case let .failed(message):
            phase = .failed(message)
            return
        default:
            break
        }
        phase = .adding
        await add.addBest()
        switch add.state {
        case let .added(info):
            if let request = request(from: info, target: target) {
                phase = .ready(request)
            } else {
                phase = .failed("That version has no playable video file.")
            }
        case let .addFailed(message):
            phase = .failed(message)
        default:
            phase = .noneCached
        }
    }

    /// Ranked cached + uncached releases for this target — the input to a tracked download when
    /// nothing is instant. Empty when there is no engine.
    public func uncachedCandidates(_ target: Target) async -> [CachedStream] {
        guard let add = makeAdd(target.streamKind) else { return [] }
        return await add.uncachedCandidates()
    }

    /// Build the playable request from a freshly-added torrent, keyed exactly as the library keys
    /// the same title — so progress recorded now is found later.
    private func request(from info: TorrentInfo, target: Target) -> PlaybackRequest? {
        guard let (file, link) = info.primaryVideoFile() else { return nil }
        let source = MediaSource(torrentID: info.id, fileID: file.id, restrictedLink: link,
                                 parsed: FilenameParser().parse(info.filename))
        switch target {
        case .movie:
            return PlaybackRequest(item: item, source: source, resumeAt: nil, label: item.title,
                                   contentKey: WatchKey.content(forMovie: item), episode: nil,
                                   fromStart: true)
        case let .episode(season, number):
            let episode = Episode(season: season, number: number, source: source)
            return PlaybackRequest(item: item, source: source, resumeAt: nil,
                                   label: "\(item.title) — S\(season)·E\(number)",
                                   contentKey: WatchKey.content(forShow: item, season: season,
                                                                number: number),
                                   episode: episode, fromStart: true)
        }
    }
}
