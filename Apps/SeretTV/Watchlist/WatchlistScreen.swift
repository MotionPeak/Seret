import DebridCore
import DebridUI
import SwiftUI

/// The owner's Letterboxd watchlist — films they mean to watch, most recently added first.
///
/// Laid out as the app's other grid screens are: no in-content page title (the side menu already
/// names the section — see `LibraryScreen`), a pinned control row above a grid that scrolls under
/// a top fade, and `PosterGrid`'s column metrics so a poster here is the same size it is on Home
/// and in My Library.
struct WatchlistScreen: View {
    @Environment(AppSession.self) private var session
    @State private var model: WatchlistModel?

    /// Opens a title page. The shell owns the navigation path, so a spin's result is pushed by
    /// handing it back up rather than by this screen registering a destination of its own — the
    /// shell already routes `MediaItem`, and registering it twice on one stack collides.
    var onOpen: (MediaItem) -> Void = { _ in }

#if DEBUG
    /// The model the `-uiPreview watchlist` harness renders instead of the session's, so the real
    /// screen can be screenshot-verified without a signed-in session or a Letterboxd account.
    var previewModel: WatchlistModel?
#endif

    /// The spin in progress. Replacing it re-runs the reel, which is how "Spin Again" works.
    @State private var spin: WatchlistRandomizer.Spin?
    /// A film awaiting removal confirmation. Removing is the one destructive thing on this screen.
    @State private var pendingRemoval: WatchlistEntry?

    /// `PosterGrid`'s metrics verbatim — six across at 1080p. The grid pads itself rather than
    /// being padded by a parent, so the focus lift has somewhere to go at the row edges instead of
    /// being clipped against them.
    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]

    var body: some View {
        ZStack {
            CanvasBackground()
            if let model {
                content(model)
            } else {
                message("Set your Letterboxd username on your iPhone, in Seret → Settings.",
                        systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(item: $spin) { current in
            WatchlistSpinScreen(
                spin: current,
                onWatch: { entry in
                    spin = nil
                    guard let item = MediaItem.watchlistMovie(entry) else { return }
                    // Pushed a beat later: navigating while the cover is still on screen races its
                    // dismissal and the push is silently dropped.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        onOpen(item)
                    }
                },
                onSpinAgain: { spin = model?.spin() },
                onClose: { spin = nil })
        }
        .confirmationDialog("Remove from watchlist?",
                            isPresented: .constant(pendingRemoval != nil),
                            titleVisibility: .visible,
                            presenting: pendingRemoval) { entry in
            Button("Remove", role: .destructive) {
                pendingRemoval = nil
                Task { await model?.remove(entry) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { entry in
            // Says plainly what it does and does not do, so nobody expects Letterboxd to change.
            Text("\(WatchlistName.stripYear(from: entry.name)) will be hidden in Seret. "
                 + "It stays on your Letterboxd watchlist.")
        }
        .task {
#if DEBUG
            if let previewModel { model = previewModel; return }
#endif
            if model == nil { model = session.makeWatchlistModel() }
            await model?.syncIfStale()
        }
    }

    @ViewBuilder
    private func content(_ model: WatchlistModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            statusRow(model)

            if model.entries.isEmpty {
                // Only genuinely empty once a sync has settled — mid-sync this is the first run,
                // and "nothing on your watchlist" would be a lie told to someone who is watching
                // it load.
                if case .syncing = model.phase {
                    SeretLoader(label: "Reading your watchlist…")
                } else {
                    message("Nothing on your watchlist yet.", systemImage: "bookmark")
                }
            } else {
                grid(model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func grid(_ model: WatchlistModel) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 50) {
                ForEach(model.entries) { entry in
                    WatchlistTile(entry: entry, owned: model.isOwned(entry),
                                  onRemove: { pendingRemoval = $0 })
                }
            }
            .padding(.horizontal, Theme.Layout.contentMargin)
            .padding(.vertical, 30)
        }
        .gridTopFade()
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    /// The sync affordance, pinned above the scroll like `GenreGridScreen`'s sort row — a control
    /// row, not a title bar. It stays put while the grid moves under it.
    @ViewBuilder
    private func statusRow(_ model: WatchlistModel) -> some View {
        HStack(spacing: 16) {
            switch model.phase {
            case .idle:
                // Offered only when a spin has something to land on, rather than shown disabled —
                // a disabled control is unreachable on tvOS, so it would be a dead spot.
                if model.canSpin {
                    Button("Surprise Me", systemImage: "dice.fill") { spin = model.spin() }
                        .buttonStyle(SeretActionButtonStyle())
                }
                Button("Sync") { Task { await model.syncNow() } }
                    .buttonStyle(SeretPillStyle(selected: false))
                if !model.entries.isEmpty {
                    Text("\(model.entries.count) films")
                        .calloutText()
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            case .syncing(let done, let total):
                ProgressView().tint(Theme.Palette.gold)
                Text(total > 0 ? "Matching \(done) of \(total)…" : "Reading your watchlist…")
                    .calloutText()
                    .foregroundStyle(Theme.Palette.textSecondary)
            case .failed(let message):
                Button("Retry") { Task { await model.syncNow() } }
                    .buttonStyle(SeretPillStyle(selected: false))
                // The palette's own error colour, not a raw `.red` — a sync failure should read
                // as a failure without shouting in a hue the app uses nowhere else.
                Text(message)
                    .calloutText()
                    .lineLimit(2)
                    .foregroundStyle(Theme.Palette.destructive)
            }
        }
        .padding(.leading, Theme.Layout.contentMargin)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    /// Centered full-canvas state, matching `LibraryScreen`'s.
    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage).font(.system(size: 64)).foregroundStyle(Theme.Palette.gold)
            Text(text).sectionTitle().multilineTextAlignment(.center).frame(maxWidth: 700)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One watchlist film — `PosterCard`'s shape, so the grid reads as the same grid it is everywhere
/// else: the poster is the `.card` (focus lift + ring), the title sits below it as plain text and
/// brightens with focus.
///
/// A film that resolved to nothing is still shown — as a plain card, not a link. Hiding it would
/// make the count disagree with Letterboxd and give no way to find out why; making it a link would
/// promise a page that does not exist.
private struct WatchlistTile: View {
    let entry: WatchlistEntry
    let owned: Bool
    /// Long-press → remove. Raised rather than handled here so the confirmation belongs to the
    /// screen: a dialog owned by a tile dies with the tile the moment the grid updates.
    var onRemove: (WatchlistEntry) -> Void = { _ in }

    private let width: CGFloat = 220
    private let height: CGFloat = 330
    @FocusState private var focused: Bool

    private var title: String { WatchlistName.stripYear(from: entry.name) }

    private var item: MediaItem? { MediaItem.watchlistMovie(entry) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item {
                NavigationLink(value: BrowseDestination.detail(item)) { poster }
                    .buttonStyle(.card)
                    .focused($focused)
                    .contextMenu { removeButton }
            } else {
                // Focusable although it goes nowhere. tvOS scrolls by MOVING FOCUS, so a tile with
                // no focus target cannot be scrolled to: a trailing row of unmatched films — and
                // the caption explaining why they are grey — sat permanently below the fold with
                // the d-pad refusing to advance. Verified in the simulator, six presses, no move.
                poster
                    .focusable()
                    .focused($focused)
                    .scaleEffect(focused ? Theme.Anim.focusScale : 1)
                    .animation(Theme.Anim.focus, value: focused)
                    // Removable too — an unmatched film is the one you are most likely to want
                    // rid of, since it is the one Seret can do nothing with.
                    .contextMenu { removeButton }
            }
            caption
        }
    }

    @ViewBuilder private var poster: some View {
        Group {
            if let url = TMDBClient.imageURL(path: entry.posterPath, size: "w500") {
                RemoteImage(url: url)
            } else {
                noPoster
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if owned {
                // The same gold ✓ a watched title carries elsewhere: on a list of things to
                // acquire, "you already have this" is the one thing worth marking.
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.Palette.gold)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .padding(12)
                    .accessibilityLabel("In your library")
            }
        }
    }

    /// No artwork — the title on a palette surface, exactly as `PosterCard` falls back.
    private var noPoster: some View {
        Theme.Palette.surface1
            .overlay {
                Text(title)
                    .cardTitle()
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(12)
            }
    }

    private var removeButton: some View {
        Button("Remove from Watchlist", systemImage: "minus.circle", role: .destructive) {
            onRemove(entry)
        }
    }

    @ViewBuilder private var caption: some View {
        if item == nil {
            // Short enough to survive one line at the caption size — "Couldn't match this on TMDB"
            // truncated to "Couldn't matc…", which explains nothing at all. The poster surface
            // above already carries the film's name, so this only has to say why it is grey.
            //
            // textSecondary, not a third step: the tvOS ramp is deliberately two steps because a
            // dimmer one does not read across a room. See Theme.Palette.
            Text("No TMDB match")
                .cardTitle()
                .lineLimit(1)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: width, alignment: .leading)
        } else {
            Text(title)
                .cardTitle()
                .lineLimit(1)
                .foregroundStyle(focused ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                .frame(width: width, alignment: .leading)
                .animation(Theme.Anim.focus, value: focused)
        }
    }
}
