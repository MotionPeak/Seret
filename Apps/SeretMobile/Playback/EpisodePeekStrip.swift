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
                ForEach(model.seasonEpisodes) { ep in thumb(ep, height: 54) }
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
