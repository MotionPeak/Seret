import DebridCore
import DebridUI
import SwiftUI

/// The hero's action row: Play/Resume (+ Start Over) when the title is playable, otherwise a gold
/// acquire button that finds and adds a version through `TitleAcquirer`; Watchlist (films); the
/// ⋯ menu.
struct TitleActionsRow: View {
    let store: DetailStore
    let acquirer: TitleAcquirer?

    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?
    @Environment(LibraryStore.self) private var injectedLibrary: LibraryStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var library: LibraryStore? { injectedLibrary ?? session?.libraryStore }

    var body: some View {
        HStack(spacing: 10) {
            primary
            if let film = WatchlistFilm(item: store.item) { watchlistButton(film) }
            moreMenu
        }
        // As with the chip row above it: this can run wider than the 640 pt copy column once
        // Resume + Start Over + Watchlist + ⋯ are all present — never let a button's label wrap.
        .fixedSize(horizontal: true, vertical: false)
        .padding(.top, 4)
    }

    // MARK: - Primary

    @ViewBuilder private var primary: some View {
        if let pp = store.primaryPlay() {
            HStack(spacing: 10) {
                Button {
                    shell?.present(pp.request)
                } label: {
                    Label(primaryTitle(pp), systemImage: "play.fill")
                }
                .buttonStyle(GoldButtonStyle())
                if pp.resumeAt != nil {
                    Button {
                        shell?.present(pp.startOver)
                    } label: {
                        Label("Start Over", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
        } else {
            acquireButton
        }
    }

    /// Owned = the library has something under this item — a source (a film) or a season (a show).
    private var isOwned: Bool { !(store.item.sources.isEmpty && store.item.seasons.isEmpty) }

    @ViewBuilder private var acquireButton: some View {
        if store.richState == .failed, store.imdbID == nil {
            Button { } label: { Text(TitlePageText.unavailableTitle(isOwned: isOwned)) }
                .buttonStyle(GoldButtonStyle())
                .disabled(true)
        } else {
            let target = acquireTarget
            let busy = target.map { acquirer?.isBusy($0) ?? false } ?? false
            let disabled = busy || store.imdbID == nil || acquirer == nil || target == nil
            Button {
                guard let acquirer, let target else { return }
                Task { await runAcquire(acquirer, target) }
            } label: {
                Label {
                    Text(TitlePageText.acquireTitle(episode: episodeTuple, finding: busy))
                } icon: {
                    Image(systemName: busy ? "ellipsis" : "play.fill")
                        .symbolEffect(.pulse, isActive: busy && !reduceMotion)
                }
            }
            .buttonStyle(GoldButtonStyle())
            .disabled(disabled)
        }
    }

    private func runAcquire(_ acquirer: TitleAcquirer, _ target: AcquisitionStore.Target) async {
        switch await acquirer.play(target) {
        case .play(let request):
            shell?.present(request)
        case .noneInstant:
            shell?.showToast("No instant version \u{2014} request a download below", isFailure: false)
        case .downloadStarted:
            shell?.showToast("Downloading \(acquireDownloadLabel) to Real\u{2011}Debrid")
        case .failed(let message) where !message.isEmpty:
            shell?.showToast(message, isFailure: true)
        case .failed:
            break   // a busy target being tapped again — silent no-op
        }
    }

    private var acquireTarget: AcquisitionStore.Target? {
        switch store.item.kind {
        case .movie: return .movie
        case .show:
            guard let next = store.nextEpisodeTarget() else { return nil }
            return .episode(season: next.season, number: next.number)
        }
    }

    private var episodeTuple: (season: Int, number: Int)? {
        if case let .episode(season, number)? = acquireTarget { return (season, number) }
        return nil
    }

    private var acquireDownloadLabel: String {
        if let e = episodeTuple { return "S\(e.season)\u{00B7}E\(e.number)" }
        return store.item.title
    }

    private func primaryTitle(_ pp: DetailStore.PrimaryPlay) -> String {
        TitlePageText.primaryTitle(episode: pp.episode.map { ($0.season, $0.number) }, resumeAt: pp.resumeAt)
    }

    // MARK: - Watchlist

    @ViewBuilder private func watchlistButton(_ film: WatchlistFilm) -> some View {
        let onList = watchlist?.contains(tmdbID: film.tmdbID) ?? false
        let busy = watchlist?.isInFlight(tmdbID: film.tmdbID) ?? false
        Button {
            Task { await watchlist?.toggle(film: film) }
        } label: {
            Label(onList ? "On Watchlist" : "Watchlist", systemImage: onList ? "bookmark.fill" : "bookmark")
                .foregroundStyle(onList ? Theme.Palette.gold : Theme.Palette.textPrimary)
        }
        .buttonStyle(GlassButtonStyle())
        .disabled(busy)
    }

    // MARK: - More menu

    @ViewBuilder private var moreMenu: some View {
        Menu {
            ForEach(Array(menuGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                ForEach(group, id: \.self) { item in
                    Button {
                        perform(item)
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .help("More")
    }

    private var menuGroups: [[TitleMenuItem]] {
        TitleMenu.make(kind: store.item.kind, owned: isOwned, watched: isWatched,
                       inMyList: store.inMyList, canMyList: session?.myListStore != nil,
                       hasTrailer: false, canMagnet: false, canFindVersions: false)
    }

    private var isWatched: Bool { library?.watchState(for: store.item)?.finished ?? false }

    private func perform(_ item: TitleMenuItem) {
        switch item {
        case .markWatched(let watched), .markShowWatched(let watched):
            let toggle = TitleWatchToggle(watch: session?.watchStore, showMarker: session?.makeShowWatchMarker(),
                                          library: library, profileID: session?.activeProfileID)
            Task {
                let ok = await toggle.set(watched, title: store.item)
                if ok {
                    await store.reloadWatch()
                    shell?.showToast(watched ? "Marked \u{201C}\(store.item.title)\u{201D} watched"
                                             : "Marked \u{201C}\(store.item.title)\u{201D} unwatched")
                } else {
                    shell?.showToast("Couldn\u{2019}t mark \u{201C}\(store.item.title)\u{201D} \u{2014} your profile hasn\u{2019}t loaded yet",
                                     isFailure: true)
                }
            }
        case .myList(let adding):
            Task {
                await store.toggleMyList(contentKey: store.item.id)
                shell?.showToast(adding ? "Added to My List" : "Removed from My List")
            }
        case .removeFromLibrary:
            shell?.pendingRemoval = store.item
        case .watchTrailer, .addByMagnet, .findOtherVersions:
            break   // wired in Tasks 4–5
        }
    }
}
