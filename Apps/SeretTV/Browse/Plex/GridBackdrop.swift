import DebridCore
import DebridUI
import SwiftUI

/// The page background of a grid screen (My Library, Watchlist, Search, a genre, a person): the
/// focused title's ultrablur wash, Plex-style — grids are grid-first, so there is no preview
/// header and no sharp art, only the blurred colour of the focused title following focus.
///
/// - Cells call `preview.focus(_:)`, which is debounced: gliding across a row never fades the
///   backdrop per cell, only the cell focus settles on.
/// - This view is the ONLY one that reads `preview.shown`. The screen that owns `preview` never
///   does, so a focus move along the grid re-renders this backdrop, never the screen and its cells.
/// - Which plate: the title's art backdrop from `TitleArtStore` (TMDB's preferred, usually
///   textless one) — the same choice `FocusBrowsePage` makes, so a title looks the same on a rail
///   and in a grid. A title whose art is not cached waits up to `backdropArtBudget` for it; past
///   that it shows the tile's own backdrop (a library item has one; a TMDB hit does not), and moves
///   to the art's when it lands. Until a plate is ready the previous one stays up, so a grid of
///   hits never flashes to the canvas between titles.
struct GridBackdrop: View {
    let preview: FocusPreviewModel
    let art: TitleArtStore?

    @State private var backdropPath: String?

    var body: some View {
        let subject = preview.shown
        // The wash alone: Plex's grid background. See `UltrablurBackdrop.showsArt`.
        FullBleedUltrablur(backdropPath: backdropPath, showsArt: false)
            .task(id: subject?.id) { await settle(subject) }
    }

    private func artFor(_ subject: PreviewSubject) -> TitleArt? {
        guard let art, let id = subject.tmdbID else { return nil }
        return art.art(for: subject.kind, tmdbID: id)
    }

    /// Superseded (cancelled) the moment a newer subject settles, so only the latest lands.
    private func settle(_ subject: PreviewSubject?) async {
        // Nothing to describe (nothing shown yet, or the owner cleared it — a new genre whose
        // titles have not landed): the canvas, never a plate from what was there before.
        guard let subject else {
            backdropPath = nil
            return
        }
        if let cached = artFor(subject) {
            backdropPath = cached.backdropPath ?? subject.backdropPath
            return
        }
        guard let store = art, let tmdbID = subject.tmdbID else {
            backdropPath = subject.backdropPath
            return
        }
        // Store-owned: runs to completion even when this settle is superseded, so the art is
        // cached for the next look.
        let kind = subject.kind
        let load = Task { await store.load(kind, tmdbID: tmdbID) }
        await FocusSettle.wait(for: load, upTo: FocusBrowseLayout.backdropArtBudget)
        guard !Task.isCancelled else { return }
        if let landed = artFor(subject) {
            backdropPath = landed.backdropPath ?? subject.backdropPath
            return
        }
        // Late art: the tile's own backdrop meanwhile, when it has one.
        if let own = subject.backdropPath { backdropPath = own }
        await FocusSettle.wait(for: load, upTo: .seconds(30))
        guard !Task.isCancelled else { return }
        backdropPath = artFor(subject)?.backdropPath ?? subject.backdropPath
    }
}

/// An `UltrablurBackdrop` out past the safe area AND past the shell's leading inset, so the art
/// runs under the side menu as it does in Plex. Put it in a page's `.background`.
struct FullBleedUltrablur: View {
    let backdropPath: String?
    var showsArt = true

    var body: some View {
        GeometryReader { geo in
            let lead = max(0, geo.frame(in: .global).minX)
            UltrablurBackdrop(backdropPath: backdropPath, showsArt: showsArt)
                .frame(width: geo.size.width + lead, height: geo.size.height)
                .offset(x: -lead)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Shows `first` on a grid's backdrop until focus picks a title — and again whenever the
    /// title on it is no longer in the grid (a Movies → TV switch, a new search, another genre).
    /// `key` changes with what the grid holds; `contains` says whether a subject id is still in it.
    func seedsGridBackdrop(_ preview: FocusPreviewModel, key: String, first: PreviewSubject?,
                           contains: @escaping (String) -> Bool) -> some View {
        onChange(of: key, initial: true) {
            if let shown = preview.shown, contains(shown.id) { return }
            if let first { preview.showImmediately(first) }
        }
    }
}

/// The grid metrics every poster grid shares: 236pt tiles (`PosterTileMetrics`), six across at
/// 1080p both on a root page (inside the side menu's 150pt footprint and the trailing safe area,
/// at `rootInset`) and on a pushed page (the full safe area at `Theme.Layout.contentMargin`).
enum PosterGridLayout {
    static let columnSpacing: CGFloat = 40
    static let rowSpacing: CGFloat = 50
    /// Cells are as wide as the row allows up to 260 — a tile is a fixed 236, pinned leading, so
    /// the first column lines up with the pills above it.
    static let columns = [GridItem(.adaptive(minimum: PosterTileMetrics.width, maximum: 260),
                                   spacing: columnSpacing, alignment: .leading)]
    /// A root page's grid and control rows start here — the Movies/Shows rails' inset.
    static let rootInset: CGFloat = FocusBrowseLayout.leadingInset
    /// Room above the first row for the focus lift.
    static let topPadding: CGFloat = 30
    /// Poster to caption. A focused poster grows ~14pt past its frame and its ring adds 4, so the
    /// caption sits clear of the ring rather than under it (as `DownloadingRailCard`'s does).
    static let captionSpacing: CGFloat = 22
}

/// A grid cell: the poster tile (`FocusCardStyle`: ring and lift) with its title BELOW it, which
/// brightens from secondary to primary while the tile has focus — so the focused cell reads as one
/// unit. A rail drops the caption (the preview header names the tile); a grid has no header.
///
/// `note`: the caption explains the tile rather than naming it ("No TMDB match") and stays
/// secondary.
struct CaptionedPoster<Tile: View>: View {
    let caption: String
    var note = false
    /// Focus arrived (true) or left (false).
    var onFocusChange: ((Bool) -> Void)?
    @ViewBuilder var tile: Tile

    @FocusState private var focused: Bool

    init(caption: String, note: Bool = false, onFocusChange: ((Bool) -> Void)? = nil,
         @ViewBuilder tile: () -> Tile) {
        self.caption = caption
        self.note = note
        self.onFocusChange = onFocusChange
        self.tile = tile()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PosterGridLayout.captionSpacing) {
            // A `.focused` on the tile stacks with any the tile applies itself.
            tile.focused($focused)
            Text(caption)
                .cardTitle()
                .lineLimit(1)
                .foregroundStyle(focused && !note ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                .frame(width: PosterTileMetrics.width, alignment: .leading)
                .animation(Theme.Anim.focus, value: focused)
                // The tile already speaks its title; a note says something it does not.
                .accessibilityHidden(!note)
        }
        .onChange(of: focused) { _, now in onFocusChange?(now) }
    }
}

extension View {
    /// Calls `action` when focus arrives at (true) or leaves (false) this view or the one focusable
    /// view inside it. Its own `@FocusState`, so it re-renders only itself.
    func reportsFocusChange(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(FocusChangeReporter(action: action))
    }
}

private struct FocusChangeReporter: ViewModifier {
    let action: (Bool) -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, now in action(now) }
    }
}
