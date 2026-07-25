import Foundation

/// What the system Now Playing surface shows.
public struct NowPlayingInfo: Equatable, Sendable {
    public var title: String
    public var showName: String?
    public var duration: Double
    public var position: Double
    public var rate: Double
    public var artworkURL: URL?

    public init(title: String, showName: String? = nil, duration: Double,
                position: Double, rate: Double, artworkURL: URL? = nil) {
        self.title = title
        self.showName = showName
        self.duration = duration
        self.position = position
        self.rate = rate
        self.artworkURL = artworkURL
    }
}

/// Transport actions the system surface can invoke on us.
@MainActor
public struct NowPlayingHandlers {
    public var play: () -> Void
    public var pause: () -> Void
    public var togglePlayPause: () -> Void
    /// Relative jump in seconds (positive = forward).
    public var skip: (Double) -> Void
    /// Absolute seek in seconds — the remote's own scrubber.
    public var seek: (Double) -> Void
    public var setRate: (Double) -> Void
    /// Next episode, when one exists. `nil` disables the command.
    public var nextTrack: (() -> Void)?

    public init(play: @escaping () -> Void, pause: @escaping () -> Void,
                togglePlayPause: @escaping () -> Void, skip: @escaping (Double) -> Void,
                seek: @escaping (Double) -> Void, setRate: @escaping (Double) -> Void,
                nextTrack: (() -> Void)? = nil) {
        self.play = play
        self.pause = pause
        self.togglePlayPause = togglePlayPause
        self.skip = skip
        self.seek = seek
        self.setRate = setRate
        self.nextTrack = nextTrack
    }
}

/// The system Now Playing surface — the iPhone Remote app's transport row, Control Center, Siri,
/// HomePod, and HDMI-CEC TV remotes. Seamed so `PlayerModel` stays testable and so `swift test`
/// keeps running on macOS.
///
/// This is the ONLY way to reach the iPhone Remote app's transport: its touch area emits swipes,
/// not arrow presses, and its buttons are rendered from the declared command set. An app that
/// declares nothing (as Seret did) renders nothing there.
@MainActor
public protocol NowPlayingControlling: AnyObject {
    /// Register the transport handlers and enable the commands. Called once per session.
    func activate(_ handlers: NowPlayingHandlers)
    /// Push current metadata and playhead.
    func update(_ info: NowPlayingInfo)
    /// Disable the commands and clear the Now Playing entry.
    func deactivate()
}
