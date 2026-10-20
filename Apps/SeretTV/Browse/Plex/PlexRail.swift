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
    @Environment(\.focusBrowseRows) private var rows

    /// Reads nothing that changes with focus, so a move never re-runs it — and the report it hands
    /// its tiles is a value equal to the last one, so no tile re-renders for it either. (A closure
    /// here was a new value every run, and every page render re-ran every row.)
    func body(content: Content) -> some View {
        content
            .environment(\.plexRowDidFocus, PlexRowReport(id: id, rows: rows))
            // The focused row tells the page where it is, so a row inserted above it (which moves
            // it without moving focus) can be answered by scrolling it back to the top.
            .background { FocusedRowOffsetProbe(id: id, rows: rows) }
            .id(id)
    }
}

/// Reports the row's position while it is the focused one. Its own view so that only it — not the
/// row — re-renders when the focused row changes.
private struct FocusedRowOffsetProbe: View {
    let id: String
    let rows: FocusBrowseRows?

    var body: some View {
        if rows?.focused == id {
            GeometryReader { geo in
                Color.clear.preference(key: FocusedRowOffsetKey.self,
                                       value: geo.frame(in: .scrollView).minY)
            }
        }
    }
}

/// Lets a page's `initialFocus` name this view. A plain `.focused(_:equals:)` on the page's own
/// focus state, so it stacks with any other `.focused` the caller applies.
private struct PlexFocusIDModifier: ViewModifier {
    let id: String
    @Environment(\.focusBrowseFocusID) private var box

    func body(content: Content) -> some View {
        let binding = box?.binding
        if let binding {
            content.focused(binding, equals: id)
        } else {
            content
        }
    }
}

private struct PlexRailFocusReporter: ViewModifier {
    let onFocus: () -> Void
    @Environment(\.plexRowDidFocus) private var rowReport: PlexRowReport
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

/// Which row of a `FocusBrowsePage` holds focus. One object for the page's life, handed down the
/// environment: rows write into it, and only what reads `focused` (the page's scroll, the focused
/// row's offset probe) re-renders when it changes.
@MainActor @Observable
final class FocusBrowseRows {
    var focused: String?

    func report(_ id: String) {
        if focused != id { focused = id }
    }
}

/// A row's "focus entered me" call, set by `plexBrowseRow(id:)`. A VALUE, not a closure: a closure
/// is unequal to every other closure, so each time the row re-ran, every tile below it re-rendered
/// to receive the new one. With no page above (a tile outside any browse page) it does nothing.
struct PlexRowReport: Equatable {
    let id: String
    let rows: FocusBrowseRows?

    @MainActor func callAsFunction() { rows?.report(id) }

    static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.rows.map(ObjectIdentifier.init) == b.rows.map(ObjectIdentifier.init)
    }
}

private struct PlexRowDidFocusKey: EnvironmentKey {
    static let defaultValue = PlexRowReport(id: "", rows: nil)
}

private struct FocusBrowseRowsKey: EnvironmentKey {
    static let defaultValue: FocusBrowseRows? = nil
}

/// The page's focus state for `plexFocusID(_:)`, in a box that stays the same object for the
/// page's life. The binding itself is a new value every time the page's focus changes, and handing
/// it down directly re-ran every tile's modifier on every press. Nil outside a browse page.
@MainActor
final class FocusBrowseFocusBox {
    var binding: FocusState<String?>.Binding?
}

private struct FocusBrowseFocusIDKey: EnvironmentKey {
    static let defaultValue: FocusBrowseFocusBox? = nil
}

extension EnvironmentValues {
    var focusBrowseRows: FocusBrowseRows? {
        get { self[FocusBrowseRowsKey.self] }
        set { self[FocusBrowseRowsKey.self] = newValue }
    }

    var focusBrowseFocusID: FocusBrowseFocusBox? {
        get { self[FocusBrowseFocusIDKey.self] }
        set { self[FocusBrowseFocusIDKey.self] = newValue }
    }

    fileprivate var plexRowDidFocus: PlexRowReport {
        get { self[PlexRowDidFocusKey.self] }
        set { self[PlexRowDidFocusKey.self] = newValue }
    }
}
