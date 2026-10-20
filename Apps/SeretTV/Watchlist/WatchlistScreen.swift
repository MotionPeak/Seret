import DebridCore
import DebridUI
import SwiftUI

/// The owner's Letterboxd watchlist — films they mean to watch, most recently added first.
///
/// Laid out as the app's other grid screens are: no in-content page title (the side menu already
/// names the section — see `LibraryScreen`), a pinned control row above a grid that scrolls under
/// a top fade, `PosterGridLayout`'s metrics so a poster here is the same size it is on Home and in
/// My Library, and the focused film's ultrablur behind it all (`GridBackdrop`).
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
    /// The harness's art store (the unsigned preview session has none).
    var previewArt: TitleArtStore?
    private var art: TitleArtStore? { previewArt ?? session.titleArt }
#else
    private var art: TitleArtStore? { session.titleArt }
#endif

    /// The backdrop's subject: tiles report focus, it publishes the one focus settles on. Only the
    /// backdrop reads it, so a move across the grid never re-renders this screen.
    @State private var preview = FocusPreviewModel()

    /// The spin in progress. Replacing it re-runs the reel, which is how "Spin Again" works.
    @State private var spin: WatchlistRandomizer.Spin?
    /// A film awaiting removal confirmation. Removing is the one destructive thing on this screen.
    @State private var pendingRemoval: WatchlistEntry?

    var body: some View {
        ZStack {
            if let model {
                content(model)
            } else {
                message("Set your Letterboxd username on your iPhone, in Seret → Settings.",
                        systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { GridBackdrop(preview: preview, art: art) }
        .fullScreenCover(item: $spin) { current in
            WatchlistSpinScreen(
                spin: current,
                details: session.detailsProvider,
                onWatch: { entry in
                    spin = nil
                    guard let item = MediaItem.watchlistTitle(entry, library: session.libraryStore)
                    else { return }
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
            // Worded by whose list the film is on: only the owner's Letterboxd can be written,
            // so a partner's film is hidden here and stays on theirs.
            Text(model?.removalMessage(for: entry)
                 ?? "\(WatchlistName.stripYear(from: entry.name)) will be removed from your Letterboxd watchlist.")
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

    /// The grid pads itself rather than being padded by a parent, so the focus lift has somewhere
    /// to go at the row edges instead of being clipped against them.
    private func grid(_ model: WatchlistModel) -> some View {
        let preview = preview
        // The films with a page: the backdrop's possible subjects. An unmatched film has no art.
        let matched = model.entries.compactMap { MediaItem.watchlistTitle($0, library: session.libraryStore) }
        let matchedIDs = Set(matched.map(\.id))
        return ScrollView {
            LazyVGrid(columns: PosterGridLayout.columns, spacing: PosterGridLayout.rowSpacing) {
                ForEach(model.entries) { entry in
                    WatchlistTile(entry: entry, owned: model.isOwned(entry),
                                  onRemove: { pendingRemoval = $0 },
                                  onFocus: { preview.focus(PreviewSubject(item: $0)) })
                }
            }
            .padding(.horizontal, PosterGridLayout.rootInset)
            .padding(.vertical, PosterGridLayout.topPadding)
        }
        .gridTopFade()
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        // The newest matched film until focus picks one — and again when the film on the backdrop
        // leaves the list (removed here, or gone after a sync). Ids are the films' page ids.
        .seedsGridBackdrop(preview, key: matched.map(\.id).joined(separator: "|"),
                           first: matched.first.map(PreviewSubject.init(item:)),
                           contains: { matchedIDs.contains($0) })
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
                // A removal that could not reach Letterboxd is still gone from here, so this is
                // the only place the owner would ever learn it is half-done.
                if let message = model.relayMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .calloutText()
                        .lineLimit(1)
                        .foregroundStyle(Theme.Palette.destructive)
                }
                // The other person's list could not be read. Secondary, not red: the owner's own
                // list is fine and nothing they asked for failed.
                if let message = model.partnerMessage {
                    Text(message)
                        .calloutText()
                        .lineLimit(1)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            case .syncing(let done, let total):
                ProgressView().tint(Theme.Palette.textPrimary)
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
        .padding(.leading, PosterGridLayout.rootInset)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    /// Centered full-canvas state, matching `LibraryScreen`'s.
    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage).font(.system(size: 64)).foregroundStyle(Theme.Palette.textSecondary)
            Text(text).sectionTitle().multilineTextAlignment(.center).frame(maxWidth: 700)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One watchlist film — the grid cell every grid uses (`CaptionedPoster` over a `PosterTile`), so
/// the grid reads as the same grid it is everywhere else: the poster lifts with a ring, the title
/// sits below it and brightens with focus, and a film already in the library carries the grey
/// "in library" ✓.
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
    /// Focus landed on a matched film — the page's backdrop follows it.
    var onFocus: (MediaItem) -> Void = { _ in }

    private var title: String { WatchlistName.stripYear(from: entry.name) }

    @Environment(AppSession.self) private var session
    /// The library's own item when the film is owned — see `watchlistTitle`.
    private var item: MediaItem? { MediaItem.watchlistTitle(entry, library: session.libraryStore) }

    var body: some View {
        let item = item
        // Short enough to survive one line at the caption size — "Couldn't match this on TMDB"
        // truncated to "Couldn't matc…", which explains nothing at all. The poster surface above
        // already carries the film's name, so this only has to say why it is grey.
        CaptionedPoster(caption: item == nil ? "No TMDB match" : title, note: item == nil) {
            if let item {
                PosterTile(posterPath: entry.posterPath, title: title, owned: owned,
                           onFocus: { onFocus(item) }, value: BrowseDestination.detail(item))
                    .contextMenu { removeButton }
            } else {
                // Focusable although it goes nowhere (a button with no action). tvOS scrolls by
                // MOVING FOCUS, so a tile with no focus target cannot be scrolled to: a trailing
                // row of unmatched films — and the caption explaining why they are grey — sat
                // permanently below the fold with the d-pad refusing to advance.
                PosterTile(posterPath: entry.posterPath, title: title, owned: owned, action: {})
                    // Removable too — an unmatched film is the one you are most likely to want
                    // rid of, since it is the one Seret can do nothing with.
                    .contextMenu { removeButton }
            }
        }
    }

    private var removeButton: some View {
        Button("Remove from Watchlist", systemImage: "minus.circle", role: .destructive) {
            onRemove(entry)
        }
    }
}
