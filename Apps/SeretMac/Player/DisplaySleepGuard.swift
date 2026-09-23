import Foundation

/// Keeps the display awake while the film is actually playing, and lets it sleep the moment it
/// isn't (paused, buffering, failed). `begin`/`end` are injected so a test can count calls instead
/// of touching the real `ProcessInfo` activity API.
@MainActor
final class DisplaySleepGuard {
    private let begin: () -> NSObjectProtocol
    private let end: (NSObjectProtocol) -> Void
    private var activity: NSObjectProtocol?

    init(begin: @escaping () -> NSObjectProtocol = {
        ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated],
                                              reason: "Playing video")
    }, end: @escaping (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) }) {
        self.begin = begin
        self.end = end
    }

    /// Begins the activity once while playing keeps being reported true; ends it on anything else.
    func update(isPlaying: Bool) {
        if isPlaying {
            guard activity == nil else { return }
            activity = begin()
        } else {
            release()
        }
    }

    /// Idempotent: ends the held activity if there is one, else does nothing.
    func release() {
        guard let activity else { return }
        end(activity)
        self.activity = nil
    }
}
