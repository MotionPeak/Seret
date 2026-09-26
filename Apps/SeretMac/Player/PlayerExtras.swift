import DebridCore
import DebridUI
import SwiftUI

/// The episode strip (E, or the HUD's episodes button): the season's stills, the current one
/// ringed in gold, the ones not in the library dimmed and unclickable. Sized in points.
struct EpisodeStrip: View {
    let model: PlayerModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(Theme.Typo.headline())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Close (E)")
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(model.seasonEpisodes) { episode in
                            card(episode).id(episode.id)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .frame(height: 138)
                .onAppear {
                    if let current = currentID { proxy.scrollTo(current, anchor: .center) }
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PlayerHUDMetrics.panelCorner, style: .continuous))
    }

    private var title: String {
        if let season = model.currentEpisode?.season { return season == 0 ? "Specials" : "Season \(season)" }
        return "Episodes"
    }

    private var currentID: String? {
        guard let current = model.currentEpisode else { return nil }
        return "\(current.season)x\(current.number)"
    }

    private func card(_ episode: PlayerModel.PlayerEpisode) -> some View {
        let isCurrent = episode.id == currentID
        return Button {
            guard let owned = episode.owned, !isCurrent else { return }
            model.play(owned)
            onClose()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(url: TMDBClient.imageURL(path: episode.stillPath, size: "w300"))
                    .frame(width: 176, height: 99)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isCurrent ? Theme.Palette.gold : Theme.Palette.hairline,
                                    lineWidth: isCurrent ? 2 : 1)
                    )
                Text("\(episode.number) · \(episode.name ?? "Episode \(episode.number)")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isCurrent ? Theme.Palette.gold : Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .frame(width: 176, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(!episode.isPlayable)
        .opacity(episode.isPlayable ? 1 : 0.45)
        .help(episode.isPlayable ? (episode.name ?? "") : "Not downloaded")
    }
}

/// Auto-sync reports from here while the film keeps playing: "Listening… 1:40 left" with a bar,
/// then the outcome for a few seconds.
struct AutoSyncBar: View {
    let banner: PlayerModel.AutoSyncBanner

    var body: some View {
        HStack(alignment: banner.fraction == nil ? .center : .top, spacing: 9) {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 6) {
                Text(banner.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let fraction = banner.fraction {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.22))
                            Capsule().fill(Theme.Palette.goldGradient)
                                .frame(width: max(5, geo.size.width * fraction))
                        }
                    }
                    .frame(width: 220, height: 4)
                    .animation(.easeOut(duration: 0.9), value: fraction)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassEffect(.regular, in: Capsule())
        .allowsHitTesting(false)
    }

    private var glyph: String {
        switch banner.mood {
        case .measuring: "waveform"
        case .synced: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch banner.mood {
        case .measuring: Theme.Palette.gold
        case .synced: .green
        case .failed: .orange
        }
    }
}

/// The accumulating skip badge (spec §7.3): 10 s → 20 s → 1:10, on the side it went.
struct SkipBadge: View {
    let feedback: PlayerModel.SkipFeedback

    var body: some View {
        Text(feedback.label)
            .font(.system(size: 15, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .glassEffect(.regular, in: Capsule())
            .allowsHitTesting(false)
    }
}

/// The Letterboxd prompt at the credits: ten stars (keys 1–0), and ✕ to log without a rating.
struct LetterboxdRatingBar: View {
    let current: Int?
    let onRate: (Int?) -> Void
    let onDismiss: () -> Void

    private var shown: Int { current ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            Text(shown > 0 ? "RATE IT · \(shown)/10" : "RATE IT?")
                .font(.system(size: 11, weight: .bold)).tracking(1.2)
                .foregroundStyle(Theme.Palette.gold)
            HStack(spacing: 0) {
                ForEach(1...10, id: \.self) { value in
                    Button {
                        // The current rating again clears it — the only way to undo a mis-click.
                        onRate(current == value ? nil : value)
                    } label: {
                        Image(systemName: shown >= value ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundStyle(shown >= value ? Theme.Palette.gold : .white.opacity(0.45))
                            .frame(width: 24, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(value)/10 (key \(value == 10 ? 0 : value))")
                }
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Log it without a rating")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }
}

struct LetterboxdLoggedBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Palette.gold)
            Text("Logged to Letterboxd")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassEffect(.regular, in: Capsule())
    }
}
