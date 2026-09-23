import DebridCore
import Foundation

/// What the title's main button starts, lifted out of the iPhone/tvOS Detail views so the Mac does
/// not become a third copy of "what does Play play" (Decision 1 in the Mac watch-slice plan).
extension DetailStore {
    /// What the title's main button starts. `resumeAt != nil` → the button reads
    /// "Resume · h:mm:ss" (film) / "Resume S1·E3" (show) and Start Over is offered.
    public struct PrimaryPlay: Equatable {
        public let request: PlaybackRequest      // resumes (fromStart == false)
        public let startOver: PlaybackRequest    // same file, fromStart == true, resumeAt == nil
        public let episode: Episode?             // nil for a film
        public let resumeAt: Double?
    }

    /// Film → the best (preferred) owned source. Show → `nextEpisode()`. nil when nothing is owned.
    public func primaryPlay() -> PrimaryPlay? {
        switch item.kind {
        case .movie:
            guard let source = bestSource else { return nil }
            let request = playRequest(source: source, episode: nil, label: item.title)
            let startOver = playRequest(source: source, episode: nil, label: item.title, fromStart: true)
            return PrimaryPlay(request: request, startOver: startOver, episode: nil, resumeAt: request.resumeAt)
        case .show:
            guard let episode = nextEpisode() else { return nil }
            let label = Self.episodeLabel(showTitle: item.title, season: episode.season, number: episode.number)
            let request = playRequest(source: episode.source, episode: episode, label: label)
            let startOver = playRequest(source: episode.source, episode: episode, label: label, fromStart: true)
            return PrimaryPlay(request: request, startOver: startOver, episode: episode, resumeAt: request.resumeAt)
        }
    }

    /// An episode row's play request; nil when the episode is not downloaded.
    public func episodePlayRequest(for row: EpisodeRowInfo, fromStart: Bool = false) -> PlaybackRequest? {
        guard let episode = row.ownedEpisode, let source = row.ownedSource else { return nil }
        let label = Self.episodeLabel(showTitle: item.title, season: row.season, number: row.number)
        return playRequest(source: source, episode: episode, label: label, fromStart: fromStart)
    }

    /// The shared player label for an episode.
    public static func episodeLabel(showTitle: String, season: Int, number: Int) -> String {
        "\(showTitle) — S\(season)·E\(number)"
    }
}
