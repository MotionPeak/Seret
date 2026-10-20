import Foundation

/// Which view in a scrolling page (a grid under a Downloading strip) has focus, and the strip's
/// cards as last shown — so the strip never changes SHAPE (appears or disappears) under the
/// viewer. A plain reference, written on every focus move and never observed: following focus
/// must not re-render the page.
///
/// Why: the strip sits ABOVE the grid in the same scroll. Appearing or disappearing grows or
/// shrinks everything above the focused cell by ~480pt, and tvOS does not re-scroll when focus did
/// not move — the focused cell jumped under the page's header or off screen (and scrolling it back
/// while it is off screen makes tvOS hand focus to another cell). So while focus is inside the
/// scroll the strip keeps its shape, and takes its new one once focus leaves.
@MainActor
public final class ScrollFocusTracker {
    /// The focused view's id (a grid item's id, or `stripID(_:)` of a strip card); nil while focus
    /// is anywhere else.
    public var focusedID: String?
    /// The owner's settle before "focus has left" counts — kept here so a new focus can cancel it.
    public var leaving: Task<Void, Never>?
    /// The strip's cards as last shown.
    public private(set) var shown: [DownloadTile] = []
    /// The strip is showing a shape other than the live one.
    public private(set) var holding = false

    public init() {}

    /// A strip card's focus id. Prefixed: a card and the library title it becomes share an id.
    public static func stripID(_ tile: DownloadTile) -> String { "strip/\(tile.id)" }

    /// The cards the strip shows for the live `downloads`: those, unless focus is inside the scroll
    /// and they would make the strip appear or disappear — then the strip keeps its last cards
    /// (which the page draws settled, never frozen mid-progress).
    ///
    /// A focused view that is REMOVED never reports losing focus — a focused card whose download
    /// finished while another one carries on (same shape, so the card just goes), a grid title
    /// removed from the library. Left set, `focusedID` would hold every later change forever while
    /// focus sat on the header. So a focus id that names nothing on the page any more is dropped
    /// here, and the decision made again; wherever focus goes next reports itself.
    ///
    /// Call it from the body, not an `onChange`: an `onChange` runs after the body has laid the new
    /// shape out once, and that one layout is enough to push the focused cell off screen.
    public func tiles(for downloads: [DownloadTile],
                      gridContains: (String) -> Bool) -> [DownloadTile] {
        let result = decide(downloads)
        guard let id = focusedID else { return result }
        let present = id.hasPrefix("strip/")
            ? result.contains { Self.stripID($0) == id }
            : gridContains(id)
        guard !present else { return result }
        focusedID = nil
        return decide(downloads)
    }

    private func decide(_ downloads: [DownloadTile]) -> [DownloadTile] {
        if focusedID == nil || shown.isEmpty == downloads.isEmpty {
            shown = downloads
            holding = false
        } else {
            holding = true
        }
        return shown
    }
}
