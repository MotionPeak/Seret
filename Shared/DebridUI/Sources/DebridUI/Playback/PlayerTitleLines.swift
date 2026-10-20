import Foundation
import DebridCore

/// The two lines a player's top chrome shows for what is playing.
///
/// An episode leads with its OWN name — the show is the context, not the headline — and falls back
/// to "Episode 3" when no name is known; beneath it, "Show · S1 • E3 · 52 min". Anything else leads
/// with the play site's label, and a film adds its year: "2024 · 2 hr 8 min". The runtime is the
/// playing file's own duration, and is left out until it is known.
public struct PlayerTitleLines: Equatable, Sendable {
    public let title: String
    public let subtitle: String

    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    /// - Parameters:
    ///   - label: the play site's label — what a non-episode leads with.
    ///   - itemTitle: the item's own title; for an episode, the show's.
    ///   - episode: the episode playing, nil for a film (or a play with no series context).
    ///   - episodeName: that episode's name, when one is known.
    public static func make(label: String, itemTitle: String, kind: MediaKind, year: Int?,
                            episode: Episode?, episodeName: String?,
                            duration: Double) -> PlayerTitleLines {
        let runtime = runtimeText(duration)
        guard let episode else {
            let parts = [kind == .movie ? year.map(String.init) : nil, runtime].compactMap { $0 }
            return PlayerTitleLines(title: label, subtitle: parts.joined(separator: " · "))
        }
        let name = episodeName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let parts = [itemTitle, "S\(episode.season) \u{2022} E\(episode.number)", runtime]
            .compactMap { $0 }
        return PlayerTitleLines(title: name ?? "Episode \(episode.number)",
                                subtitle: parts.joined(separator: " · "))
    }

    /// "52 min" / "2 hr" / "2 hr 8 min"; nil under a minute (an unknown duration reads as 0).
    public static func runtimeText(_ seconds: Double) -> String? {
        guard seconds >= 60 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}

public extension PlayerModel {
    /// The top chrome's lines for the file playing now — they follow an in-place episode swap.
    var titleLines: PlayerTitleLines {
        let name = currentEpisode.flatMap { ep in
            seasonEpisodes.first { $0.season == ep.season && $0.number == ep.number }?.name
        }
        return PlayerTitleLines.make(label: label, itemTitle: item.title, kind: item.kind,
                                     year: item.year, episode: currentEpisode, episodeName: name,
                                     duration: duration)
    }
}
