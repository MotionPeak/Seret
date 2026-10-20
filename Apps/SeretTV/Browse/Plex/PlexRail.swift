import SwiftUI

/// One horizontal rail of a `FocusBrowsePage`: a 34pt title at the page's leading inset over a
/// lazy row of tiles.
///
/// - The row scrolls edge to edge with clipping off, so a focused tile's 1.08 lift and ring are
///   never cut at the row's ends; the vertical padding is the room for that lift.
/// - Full-width frame FIRST, then `.focusSection()` — a section only catches a directional move
///   when its frame intersects the direction of travel, so a shrink-wrapped row would leave the
///   outer tiles of the rail above with nothing below them (CLAUDE.md, `.focusSection()`).
///   The section is the TILE BAND only, not the title and paddings: measured in `plexrails`, a
///   section reaching up over the title caught Down from the rail above while this rail's tiles
///   were still just off-screen, and handed focus to the tile nearest the screen centre — Down
///   from the first poster landed on the third. Bounded to the tiles, Down keeps its column.
/// - `id` is the rail's stable identity: the page scrolls to it when focus enters the rail.
///   Never branch skeleton ↔ real INSIDE `content` with overlapping ids — branch around the rail.
struct PlexRail<Content: View>: View {
    let title: String
    let id: String
    /// Quiet words after the title, on its baseline ("ready to play").
    var subtitle: String?
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, id: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.id = id
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FocusBrowseLayout.railTitleSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title)
                    .sectionTitle()
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.seret(24, .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .lineLimit(1)
            .padding(.leading, FocusBrowseLayout.leadingInset)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 28) { content }
                    .padding(.horizontal, FocusBrowseLayout.leadingInset)
            }
            .scrollClipDisabled()
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
        }
        .padding(.vertical, FocusBrowseLayout.railVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plexBrowseRow(id: id)
    }
}

// MARK: - Rail focus reporting

extension View {
    /// Marks this view as one row of a `FocusBrowsePage` (a `PlexRail` does it for itself): the
    /// page scrolls the row to the top of the rail area whenever focus enters it. Use it on a
    /// row that is not a `PlexRail` — a pill strip, a genre strip — so moving back into it still
    /// moves the page.
    func plexBrowseRow(id: String) -> some View {
        modifier(PlexBrowseRowModifier(id: id))
    }

    /// Names this focusable view for its page's `FocusBrowsePage(initialFocus:)`. Outside a
    /// browse page it does nothing.
    func plexFocusID(_ id: String) -> some View {
        modifier(PlexFocusIDModifier(id: id))
    }

    /// Reports focus entering this tile to its row (see `plexBrowseRow(id:)`), and calls
    /// `onFocus`. `PosterTile` does this itself; any other focusable tile in a rail must too.
    func reportsPlexRailFocus(_ onFocus: @escaping () -> Void = {}) -> some View {
        modifier(PlexRailFocusReporter(onFocus: onFocus))
    }
}

private struct PlexBrowseRowModifier: ViewModifier {
    let id: String
    @Environment(\.focusBrowseRowFocused) private var pageReport
    @Environment(\.focusBrowseFocusedRow) private var focusedRow

    func body(content: Content) -> some View {
        let id = id
        let pageReport = pageReport
        content
            .environment(\.plexRowDidFocus, { pageReport(id) })
            // The focused row tells the page where it is, so a row inserted above it (which moves
            // it without moving focus) can be answered by scrolling it back to the top.
            .background {
                if focusedRow == id {
                    GeometryReader { geo in
                        Color.clear.preference(key: FocusedRowOffsetKey.self,
                                               value: geo.frame(in: .scrollView).minY)
                    }
                }
            }
            .id(id)
    }
}

/// Lets a page's `initialFocus` name this view. A plain `.focused(_:equals:)` on the page's own
/// focus state, so it stacks with any other `.focused` the caller applies.
private struct PlexFocusIDModifier: ViewModifier {
    let id: String
    @Environment(\.focusBrowseFocusID) private var binding

    func body(content: Content) -> some View {
        if let binding {
            content.focused(binding, equals: id)
        } else {
            content
        }
    }
}

private struct PlexRailFocusReporter: ViewModifier {
    let onFocus: () -> Void
    @Environment(\.plexRowDidFocus) private var rowReport
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, now in
                guard now else { return }
                onFocus()
                rowReport()
            }
    }
}

/// A row's "focus entered me" call, set by `plexBrowseRow(id:)`. A no-op default, so a tile
/// outside any browse page does nothing rather than trapping.
private struct PlexRowDidFocusKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

/// The page's "focus entered row `id`" call, set by `FocusBrowsePage`.
private struct FocusBrowseRowFocusedKey: EnvironmentKey {
    static let defaultValue: @MainActor (String) -> Void = { _ in }
}

/// Which row the page considers focused, so that row (only) reports its position.
private struct FocusBrowseFocusedRowKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

/// The page's focus state for `plexFocusID(_:)`. Nil outside a browse page.
private struct FocusBrowseFocusIDKey: EnvironmentKey {
    static var defaultValue: FocusState<String?>.Binding? { nil }
}

extension EnvironmentValues {
    var focusBrowseFocusedRow: String? {
        get { self[FocusBrowseFocusedRowKey.self] }
        set { self[FocusBrowseFocusedRowKey.self] = newValue }
    }

    var focusBrowseFocusID: FocusState<String?>.Binding? {
        get { self[FocusBrowseFocusIDKey.self] }
        set { self[FocusBrowseFocusIDKey.self] = newValue }
    }

    fileprivate var plexRowDidFocus: @MainActor () -> Void {
        get { self[PlexRowDidFocusKey.self] }
        set { self[PlexRowDidFocusKey.self] = newValue }
    }

    var focusBrowseRowFocused: @MainActor (String) -> Void {
        get { self[FocusBrowseRowFocusedKey.self] }
        set { self[FocusBrowseRowFocusedKey.self] = newValue }
    }
}
