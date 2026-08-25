import DebridCore
import DebridUI
import SwiftUI

/// Episode strip for the touch player. Collapsed = a dimmed, vertically-cropped "peek" of the
/// season's stills under the scrub bar (a hint). Tap or swipe up expands it into a scrollable,
/// selectable card strip; tapping a DOWNLOADED episode switches playback in place. Not-downloaded
/// episodes are shown dimmed with a ⬇︎ glyph and aren't selectable. Hidden for movies.
struct EpisodePeekStrip: View {
    let model: PlayerModel
    @State private var expanded = false

    var body: some View {
        if model.isEpisode && !model.seasonEpisodes.isEmpty {
            Group {
                if expanded { fullStrip } else { peek }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: expanded)
        }
    }

    // MARK: Collapsed peek

    private var peek: some View {
        VStack(spacing: 2) {
            Image(systemName: "chevron.compact.up").font(.caption2).foregroundStyle(.white.opacity(0.45))
            HStack(spacing: 6) {
                ForEach(peekEpisodes) { ep in thumb(ep, height: 54) }
            }
            .frame(height: 26, alignment: .top)     // crop to a sliver: only the top of each still shows
            .clipped()
            .opacity(0.55)
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .contentShape(Rectangle())
        .onTapGesture { expanded = true }
        .highPriorityGesture(DragGesture(minimumDistance: 14).onEnded { v in
            if v.translation.height < -18 { expanded = true }     // swipe up → expand
        })
        .padding(.top, 8)
    }

    /// The handful of episodes the collapsed peek actually shows.
    ///
    /// That peek is a 26pt sliver at 55% opacity behind a gradient mask — a hint that the strip is
    /// there, not a browsing surface. It rendered the WHOLE season in a plain HStack, which is not
    /// lazy, so a 22-episode season downloaded and decoded 22 stills for pixels almost none of
    /// which are visible, on the main screen of a player that has just started streaming. A window
    /// around the episode playing is the same hint for a fraction of it.
    private var peekEpisodes: [PlayerModel.PlayerEpisode] {
        let all = model.seasonEpisodes
        guard all.count > Self.peekCount else { return all }
        let current = all.firstIndex { $0.season == model.currentEpisode?.season
                                    && $0.number == model.currentEpisode?.number } ?? 0
        let start = min(max(0, current - 1), all.count - Self.peekCount)
        return Array(all[start..<(start + Self.peekCount)])
    }

    private static let peekCount = 8

    // MARK: Expanded selectable strip

    private var fullStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Episodes").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Button { expanded = false } label: {
                    Image(systemName: "chevron.compact.down").font(.title3).foregroundStyle(.white.opacity(0.7))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(model.seasonEpisodes) { ep in card(ep) }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 124)      // pin the row's height — a horizontal ScrollView is otherwise
                                     // vertically greedy and would eat the transport's Spacers
        }
        .padding(.top, 6)
        .highPriorityGesture(DragGesture(minimumDistance: 14).onEnded { v in
            if v.translation.height > 18 { expanded = false }      // swipe down → collapse
        })
    }

    private func card(_ ep: PlayerModel.PlayerEpisode) -> some View {
        Button {
            if let owned = ep.owned { model.play(owned); model.showControls(); expanded = false }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                thumb(ep, height: 92)
                Text("\(ep.number) · \(ep.name ?? "Episode \(ep.number)")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(1).frame(width: 164, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(!ep.isPlayable)
        .opacity(ep.isPlayable ? 1 : 0.5)
    }

    private func thumb(_ ep: PlayerModel.PlayerEpisode, height: CGFloat) -> some View {
        let isCurrent = ep.season == model.currentEpisode?.season && ep.number == model.currentEpisode?.number
        return RemoteImage(url: TMDBClient.imageURL(path: ep.stillPath, size: "w300")) {
            ZStack { Color.white.opacity(0.08); Image(systemName: "tv").foregroundStyle(.white.opacity(0.25)) }
        }
        .frame(width: height * 16 / 9, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if isCurrent { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.Palette.gold, lineWidth: 2) }
        }
        .overlay(alignment: .center) {
            if !ep.isPlayable {
                Image(systemName: "arrow.down.circle.fill").font(.title3).foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}
