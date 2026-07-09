import Foundation

/// Where a Siri-remote `.select` click landed on the trackpad, as a skip intent. The native tvOS
/// player routes ±10s this way: a click in the left band rewinds, the right band skips forward, the
/// center toggles play/pause. Pure and `Double`-based so it is unit-tested host-free.
public enum RemoteSkipZone: Sendable, Equatable {
    case back
    case playPause
    case forward

    /// - Parameters:
    ///   - touchX: last known trackpad x in the view's coordinates, or `nil` if no finger was tracked.
    ///   - width: the interaction view's width. A non-positive width is treated as unknown.
    ///   - edgeFraction: the outer band on each side that counts as a skip (default 30%).
    /// A `nil` touch or unknown width is a center click (play/pause) — never an accidental skip.
    public static func classify(touchX: Double?, width: Double, edgeFraction: Double = 0.30) -> RemoteSkipZone {
        guard let x = touchX, width > 0 else { return .playPause }
        if x < width * edgeFraction { return .back }
        if x > width * (1 - edgeFraction) { return .forward }
        return .playPause
    }
}
