import DebridCore
import DebridUI
import SwiftUI

/// Home tab: a featured hero (most recent Continue item) + Continue Watching and
/// Recently Added rails, composed on the shared `session.home`. Cards push library Detail.
struct HomeScreen: View {
    @Environment(AppSession.self) private var session

    /// True once there's anything to show.
    private var homeReady: Bool {
        guard let h = session.home else { return false }
        return !(h.continueWatching.isEmpty && h.recentlyAdded.isEmpty)
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .task { await rebuild() }
        .onChange(of: session.libraryStore?.movies) { _, _ in Task { await rebuild() } }
        .onChange(of: session.libraryStore?.shows) { _, _ in Task { await rebuild() } }
        // The active profile resolves asynchronously after sign-in; rebuild once it's known so
        // Continue Watching isn't stuck on the empty (no-profile) state.
        .onChange(of: session.activeProfileID) { _, _ in Task { await rebuild() } }
    }

    @ViewBuilder private var content: some View {
        if let home = session.home, homeReady {
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
                                let isWatched = item.kind == .movie
                                    && session.libraryStore?.watchState(for: item)?.finished == true
                                NavigationLink(value: item) { posterCard(item, watched: isWatched) }
                                    .buttonStyle(.card)
                                    .contextMenu {
                                        // Press-and-hold a recently-added MOVIE to mark it watched
                                        // (reuses LibraryStore — recentlyAdded movies are library movies).
                                        if item.kind == .movie, let store = session.libraryStore {
                                            Button(isWatched ? "Mark Unwatched" : "Mark Watched",
                                                   systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle") {
                                                Task { await store.setWatched(!isWatched, for: item) }
                                            }
                                        }
                                    }
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
                    RemoteImage(url: backdropURL(f.item))
                        .frame(height: 620).frame(maxWidth: .infinity).clipped()
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Theme.Palette.canvas.opacity(0.7), location: 0.6),
                        .init(color: Theme.Palette.canvas, location: 1.0),
                    ], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(f.subtitle.isEmpty ? "Continue Watching" : "Continue · \(f.subtitle)")
                            .eyebrow().foregroundStyle(Theme.Palette.gold)
                        Text(f.item.title).heroTitle()
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

    private func posterCard(_ item: MediaItem, watched: Bool = false) -> some View {
        // No title label — posters already carry their title in the artwork.
        RemoteImage(url: TMDBClient.imageURL(path: item.posterPath, size: "w500"))
            .frame(width: 220, height: 330)
            .overlay { if watched { Color.black.opacity(0.45) } }   // dim a watched movie
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if watched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34)).foregroundStyle(Theme.Palette.gold)
                        .background(Circle().fill(.black.opacity(0.55))).padding(12)
                        .accessibilityLabel("Watched")
                }
            }
    }

    private var empty: some View {
        VStack(spacing: 18) {
            SeretMark(glow: false).frame(width: 90).opacity(0.5)
            Text("Nothing here yet").sectionTitle().foregroundStyle(Theme.Palette.textSecondary)
            Text("Play something and it'll show up here.").bodyText()
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
