import DebridCore
import DebridUI
import SwiftUI

/// Home tab: a featured hero (most recent Continue item) + Continue Watching and
/// Recently Added rails, composed on the shared `session.home`. Cards push library Detail.
struct HomeScreen: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .task { await rebuild() }
        .onChange(of: session.libraryStore?.movies) { _, _ in Task { await rebuild() } }
        .onChange(of: session.libraryStore?.shows) { _, _ in Task { await rebuild() } }
    }

    @ViewBuilder private var content: some View {
        if let home = session.home, !(home.continueWatching.isEmpty && home.recentlyAdded.isEmpty) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 50) {
                    hero(home)
                    if !home.continueWatching.isEmpty {
                        HomeRail(title: "Continue Watching") {
                            ForEach(home.continueWatching) { hi in
                                NavigationLink(value: hi.item) {
                                    LandscapeProgressCard(title: hi.item.title, subtitle: hi.subtitle,
                                                          imageURL: backdropURL(hi.item), fraction: hi.fraction)
                                }.buttonStyle(.card)
                            }
                        }
                    }
                    if !home.recentlyAdded.isEmpty {
                        HomeRail(title: "Recently Added") {
                            ForEach(home.recentlyAdded) { item in
                                NavigationLink(value: item) { posterCard(item) }
                                    .buttonStyle(.card)
                            }
                        }
                    }
                }
                .padding(.vertical, 40)
            }
        } else {
            empty
        }
    }

    @ViewBuilder private func hero(_ home: HomeStore) -> some View {
        if let f = home.featured {
            NavigationLink(value: f.item) {
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: backdropURL(f.item)) { $0.resizable().aspectRatio(contentMode: .fill) }
                        placeholder: { Rectangle().fill(Theme.Palette.surface1) }
                        .frame(height: 620).frame(maxWidth: .infinity).clipped()
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Theme.Palette.canvas.opacity(0.7), location: 0.6),
                        .init(color: Theme.Palette.canvas, location: 1.0),
                    ], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(f.subtitle.isEmpty ? "Continue Watching" : "Continue · \(f.subtitle)")
                            .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Theme.Palette.gold)
                        Text(f.item.title).font(.system(size: 52, weight: .heavy))
                            .foregroundStyle(Theme.Palette.textPrimary).lineLimit(2)
                        HStack(spacing: 10) { Image(systemName: "play.fill"); Text("Resume") }
                            .font(.title3.weight(.semibold)).foregroundStyle(.black)
                            .padding(.vertical, 14).padding(.horizontal, 40)
                            .background(Theme.Palette.goldGradient, in: Capsule())
                            .goldGlow(16, opacity: 0.4)
                    }
                    .padding(60)
                }
            }
            .buttonStyle(.card)
        }
    }

    private func posterCard(_ item: MediaItem) -> some View {
        // No title label — posters already carry their title in the artwork.
        AsyncImage(url: TMDBClient.imageURL(path: item.posterPath, size: "w500")) {
            $0.resizable().aspectRatio(contentMode: .fill)
        } placeholder: { Rectangle().fill(Theme.Palette.surface2) }
            .frame(width: 220, height: 330).clipped()
    }

    private var empty: some View {
        VStack(spacing: 18) {
            SeretMark(glow: false).frame(width: 90).opacity(0.5)
            Text("Nothing here yet").font(.title2).foregroundStyle(Theme.Palette.textSecondary)
            Text("Play something and it'll show up here.").font(.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rebuild() async {
        guard let library = session.libraryStore, let home = session.home else { return }
        await home.rebuild(movies: library.movies, shows: library.shows)
    }

    private func backdropURL(_ i: MediaItem) -> URL? {
        TMDBClient.imageURL(path: i.backdropPath ?? i.posterPath, size: "w1280")
    }
}
