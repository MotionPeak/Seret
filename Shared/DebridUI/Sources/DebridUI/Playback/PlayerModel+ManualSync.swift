import Foundation
import DebridCore

/// Syncing a subtitle to a line the viewer can hear.
///
/// Auto-sync answers this automatically when it can, but it needs minutes of audio downloaded and
/// it refuses on dialogue-poor material. A person watching already holds the measurement: they know
/// when a line was spoken. One press is a complete answer, provided it can be timestamped (see
/// `preciseNow`) and attributed to the right cue.
///
/// The session is a captured moment plus a movable selection, and the offset is derived from the
/// pair. That is what lets the viewer press FIRST and decide which line it was afterwards —
/// reacting to a line you have heard is accurate, anticipating one you have not is not, and a
/// subtitle that is out of step is exactly when you cannot anticipate.
public extension PlayerModel {

    struct ManualSyncSession: Equatable, Sendable {
        var selectedIndex: Int
        /// Media time of the press. Nil until the viewer has pressed.
        var capturedMoment: Double?
        /// `subtitleDriftDelay` as it stood at the press. Held rather than recomputed: the drift
        /// correction grows with the playhead, so re-reading it when the viewer moves the line
        /// would shift an answer that was already right.
        var driftAtCapture: Double = 0
    }

    /// What the panel draws. Derived from the session rather than stored alongside it, so the two
    /// cannot disagree — the same reason `autoSyncBanner` is derived.
    struct ManualSyncReadout: Equatable, Sendable {
        /// The selected line with its neighbours, for context.
        public let lines: [SubtitleCue]
        public let selected: SubtitleCue
        /// The offset the press implies, or nil before the viewer has pressed.
        public let offset: Double?
    }

    var manualSyncReadout: ManualSyncReadout? {
        guard let session = manualSync else { return nil }
        let cues = manualSyncCues
        guard cues.indices.contains(session.selectedIndex) else { return nil }
        return ManualSyncReadout(
            lines: SubtitleCues.slice(around: session.selectedIndex, radius: 2, in: cues),
            selected: cues[session.selectedIndex],
            offset: session.capturedMoment == nil ? nil : subtitleDelay)
    }

    /// Open a session on the line nearest the playhead — which, when the panel is opened mid-line,
    /// is the line on screen. That is what makes the common case a single press.
    func beginManualSync() {
        let cues = manualSyncCues
        guard !cues.isEmpty else { return }
        // A measurement already running would land minutes from now and overwrite the answer the
        // viewer is about to give by hand.
        autoSyncTask?.cancel()
        autoSyncTask = nil
        manualSync = ManualSyncSession(selectedIndex: SubtitleCues.nearest(to: position, in: cues) ?? 0,
                                       capturedMoment: nil)
    }

    /// "That line started NOW." Pressing again replaces the moment, so a fumbled press costs one
    /// more line rather than a restart.
    func markSyncMoment() {
        guard manualSync != nil else { return }
        manualSync?.capturedMoment = preciseNow
        manualSync?.driftAtCapture = subtitleDriftDelay
        applyManualSyncOffset()
    }

    /// Move through the lines. After a press this re-measures from the same moment; before one it
    /// only moves the selection, because there is nothing yet to measure.
    func moveSyncLine(by delta: Int) {
        guard var session = manualSync else { return }
        let cues = manualSyncCues
        guard !cues.isEmpty else { return }
        session.selectedIndex = min(max(session.selectedIndex + delta, 0), cues.count - 1)
        manualSync = session
        applyManualSyncOffset()
    }

    /// The fine adjustment, on the existing offset — deliberately the same field the ±0.5s chips
    /// and auto-sync write, so every readout of it agrees.
    func nudgeSyncOffset(by delta: Double) { adjustSubtitleDelay(by: delta) }

    /// Close the panel. The offset stays: closing is not undoing.
    func endManualSync() { manualSync = nil }

    /// `capturedMoment = cue.start + delay + drift` is what the viewer just asserted; solve it.
    ///
    /// The drift term matters whenever the PAL correction is armed, because the engine is pushed
    /// `subtitleDelay + subtitleDriftDelay` — measure without subtracting it and the sync lands
    /// wrong by however far the correction has grown.
    private func applyManualSyncOffset() {
        guard let session = manualSync, let moment = session.capturedMoment else { return }
        let cues = manualSyncCues
        guard cues.indices.contains(session.selectedIndex) else { return }
        applySubtitleDelay(moment - cues[session.selectedIndex].start - session.driftAtCapture)
    }
}
