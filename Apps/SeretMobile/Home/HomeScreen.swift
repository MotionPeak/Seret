import DebridCore
import DebridUI
import SwiftUI

/// Home tab: a featured hero (most recent Continue item) + Continue Watching and
/// Recently Added rails, composed on `session.home`. Taps open Detail full-screen.
struct HomeScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(AppRouter.self) private var router

    private var isRegular: Bool { hSize == .regular }
    private var posterW: CGFloat { isRegular ? 150 : 112 }
    private var landW: CGFloat { isRegular ? 280 : 178 }
    private var heroH: CGFloat { isRegular ? 380 : 250 }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                content
            }
            .navigationTitle("Home")
        }
        .task {
            await session.libraryStore?.load()
            await rebuild()
        }
        .onChange(of: session.libraryStore?.movies) { _, _ in Task { await rebuild() } }
        .onChange(of: session.libraryStore?.shows) { _, _ in Task { await rebuild() } }
    }

    @ViewBuilder private var content: some View {
        if let home = session.home {
            if home.continueWatching.isEmpty && home.recentlyAdded.isEmpty {
                if session.libraryStore?.state == .loading { loading } else { empty }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.xxl) {
                        hero(home)
                        if !home.continueWatching.isEmpty {
                            Rail(title: "Continue Watching") {
                                ForEach(home.continueWatching) { hi in
                                    Button { router.detail = hi.item } label: {
                                        LandscapeProgressCard(title: hi.item.title, subtitle: hi.subtitle,
                                                              imageURL: backdropURL(hi.item),
                                                              fraction: hi.fraction, width: landW)
                                    }.pressable()
                                }
                            }
                        }
                        if !home.recentlyAdded.isEmpty {
                            Rail(title: "Recently Added") {
                                ForEach(home.recentlyAdded) { item in
                                    Button { router.detail = item } label: {
                                        PosterCard(title: item.title,
                                                   posterURL: posterURL(item), width: posterW)
                                    }.pressable()
                                }
                            }
                        }
                    }
                    .padding(.vertical, Theme.Space.lg)
                }
            }
        } else {
            ProgressView().tint(Theme.Palette.gold)
        }
    }

    @ViewBuilder private func hero(_ home: HomeStore) -> some View {
        if let f = home.featured {
            Button { router.detail = f.item } label: {
                HeroBackdrop(imageURL: backdropURL(f.item), height: heroH) {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Text(f.subtitle.isEmpty ? "Continue Watching" : "Continue · \(f.subtitle)")
                            .font(Theme.Typo.label()).tracking(1.5).foregroundStyle(Theme.Palette.gold)
                        Text(f.item.title).font(Theme.Typo.titleXL())
                            .foregroundStyle(Theme.Palette.textPrimary).lineLimit(2)
                        HStack(spacing: 6) { Image(systemName: "play.fill"); Text("Resume") }
                            .font(Theme.Typo.headline()).foregroundStyle(Color(hex: 0x1A1400))
                            .padding(.vertical, 9).padding(.horizontal, Theme.Space.xl)
                            .background(Theme.Palette.goldGradient, in: Capsule())
                            .goldGlow(12, opacity: 0.4).padding(.top, 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Space.lg)
        }
    }

    private var loading: some View {
        VStack(spacing: Theme.Space.lg) {
            ShimmerView().frame(height: heroH).padding(.horizontal, Theme.Space.lg)
            ShimmerView().frame(height: 120).padding(.horizontal, Theme.Space.lg)
        }.padding(.top, Theme.Space.lg).frame(maxHeight: .infinity, alignment: .top)
    }

    private var empty: some View {
        VStack(spacing: Theme.Space.md) {
            SeretMark(glow: false).frame(width: 54).opacity(0.5)
            Text("Nothing here yet").font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textSecondary)
            Text("Play something and it'll show up here.").font(Theme.Typo.body())
                .foregroundStyle(Theme.Palette.textTertiary)
        }.frame(maxWidth: .infinity).padding(.top, 100)
    }

    private func rebuild() async {
        guard let library = session.libraryStore, let home = session.home else { return }
        await home.rebuild(movies: library.movies, shows: library.shows)
    }

    private func posterURL(_ i: MediaItem) -> URL? { TMDBClient.imageURL(path: i.posterPath, size: "w500") }
    private func backdropURL(_ i: MediaItem) -> URL? {
        TMDBClient.imageURL(path: i.backdropPath ?? i.posterPath, size: "w780")
    }
}
