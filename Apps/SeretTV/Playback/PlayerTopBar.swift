import SwiftUI
import DebridUI
import DebridCore

/// The player's top chrome, shown together with the scrub bar: what is playing, top-left, and the
/// time of day, top-right, over a soft gradient so both read over a bright frame.
///
/// Built from nothing focusable and never hit-testable. The remote belongs to
/// `PlayerInputSurface`, which only works because it has no focusable siblings at rest.
struct PlayerTopBar: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.seret(46, .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.seret(24, .medium))
                        .foregroundStyle(Theme.Palette.textPrimary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // Ticks once a minute, which is all a clock without seconds needs.
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.seret(30, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        .padding(.horizontal, PlayerLayout.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

/// Shared player geometry.
enum PlayerLayout {
    /// The chrome's side inset INSIDE the safe area — the bar, the top line and the control row all
    /// start here, so their left edges line up.
    static let sideInset: CGFloat = 20
    /// Where the bars that sit at the top of the picture (subtitle sync, the Letterboxd prompt and
    /// confirmation) start, measured from the top of the safe area. Below the title block of
    /// `PlayerTopBar`, so the two never overlap whichever of them comes up first.
    static let topSlotInset: CGFloat = 130
}

/// The words `PlayerTopBar` shows for what is playing.
///
/// An episode leads with its OWN name — the show is the context, not the headline — and falls back
/// to "Episode 3" when the season list has no name for it. A film leads with its title.
enum PlayerTitleLines {
    static func make(label: String, episode: Episode?, episodes: [PlayerModel.PlayerEpisode],
                     year: Int?, duration: Double) -> (title: String, subtitle: String) {
        let runtime = runtimeText(duration)
        guard let episode else {
            let parts = [year.map(String.init), runtime].compactMap { $0 }
            return (label, parts.joined(separator: " · "))
        }
        // The label is "Show — S1·E3" (`DetailStore.episodeLabel`); the show is what precedes it.
        let show = label.components(separatedBy: " — ").first ?? label
        let name = episodes.first { $0.season == episode.season && $0.number == episode.number }?
            .name.flatMap { $0.isEmpty ? nil : $0 }
        let title = name ?? "Episode \(episode.number)"
        let parts = [show, "S\(episode.season) \u{2022} E\(episode.number)", runtime].compactMap { $0 }
        return (title, parts.joined(separator: " · "))
    }

    /// "52 min" / "2 hr 8 min" from the file's own duration; nil until it is known.
    static func runtimeText(_ seconds: Double) -> String? {
        guard seconds >= 60 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}
