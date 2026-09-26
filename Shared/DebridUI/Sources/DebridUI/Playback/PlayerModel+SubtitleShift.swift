import Foundation
import DebridCore

/// Moving a downloaded subtitle by rewriting its cue times instead of through libvlc's delay.
///
/// libvlc reads a subtitle only as far ahead as it has read the film — a second or two. A line
/// asked to appear earlier than that has already ended by the time libvlc reads it, and is dropped
/// without a word. So pulling a late subtitle EARLIER, which is what a subtitle timed for another
/// release usually needs, made every line vanish. Measured on the Apple TV (The Drama: not one
/// Hebrew line drawn in 36s at −10…−17s, drawing again the instant Reset was hit) and in the
/// simulator on the same file (−3s drew 10 lines, −6s drew none).
///
/// A downloaded subtitle is a file we hold, so the offset goes into the file: a copy with every
/// cue moved is attached and selected, and libvlc is left nothing to shift. Positive offsets too,
/// so there is one mechanism rather than two that behave differently at zero.
///
/// Tracks muxed into the container have no file to rewrite. They keep libvlc's delay, and
/// `subtitleOffsetBeyondEmbeddedReach` says when an offset is further than that can reach.
extension PlayerModel {

    /// Bring the attached copy of the selected downloaded subtitle in line with `subtitleDelay`.
    ///
    /// Debounced: the re-attach happens once the offset has stayed put for
    /// `subtitleShiftDebounce`, so holding a nudge button is one attach rather than twenty. A wait
    /// already running for the same offset is left alone rather than restarted — this is called on
    /// every `.tracksChanged`, and restarting it each time could postpone the attach indefinitely.
    func reconcileSubtitleShift() {
        guard !Self.subtitleShiftDisabled,
              let attached = selectedAttachedSubtitleFile else { cancelSubtitleShift(); return }
        let target = Self.shiftTarget(subtitleDelay)
        guard target != carriedShift(of: attached) else { cancelSubtitleShift(); return }
        if subtitleShiftTask != nil, scheduledSubtitleShift == target { return }
        subtitleShiftTask?.cancel()
        scheduledSubtitleShift = target
        subtitleShiftTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.subtitleShiftDebounce ?? 0))
            guard !Task.isCancelled, let self else { return }
            self.subtitleShiftTask = nil
            self.scheduledSubtitleShift = nil
            self.applySubtitleShiftNow()
        }
    }

    /// DEBUG `-noSubtitleShift` puts back the old path — every offset through libvlc's delay — so
    /// the two can be compared on the same file, at the same point, in the same build.
    static var subtitleShiftDisabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-noSubtitleShift")
        #else
        false
        #endif
    }

    func cancelSubtitleShift() {
        subtitleShiftTask?.cancel()
        subtitleShiftTask = nil
        scheduledSubtitleShift = nil
    }

    /// Built-in (muxed) tracks still take the offset through libvlc, which cannot show a line more
    /// than a few seconds early — past that, every line is dropped. True when the viewer has
    /// dialled such an offset, so the panel can say why instead of simply going blank.
    public var subtitleOffsetBeyondEmbeddedReach: Bool {
        guard selectedSubtitleID != nil, selectedDownloadedSubtitleFile == nil else { return false }
        return subtitleDelay + subtitleDriftDelay < -Self.embeddedSubtitleEarliestShift
    }

    /// What both players' timing panels say when `subtitleOffsetBeyondEmbeddedReach` is true. One
    /// string so the two faces cannot drift apart in what they promise.
    public static let embeddedSubtitleReachNote =
        "Built-in subtitles can't be shown more than 3s early. Download one to move it further."

    /// How early libvlc can still show a line. Measured for a downloaded subtitle attached as a
    /// slave (−3s drew every line, −6s none); a muxed track is read by the same demuxer pacing, so
    /// the same bound is assumed for it.
    static let embeddedSubtitleEarliestShift: Double = 3

    /// Offsets are compared and written to the millisecond — finer than any cue is timed, and
    /// coarse enough that arithmetic noise in a sum of nudges cannot make one offset look like two.
    static func shiftTarget(_ delay: Double) -> Double { (delay * 1000).rounded() / 1000 }

    /// How far an attached file moves its subtitle's lines: 0 for a file as prepared.
    private func carriedShift(of attached: URL) -> Double {
        subtitleShiftCopies[attached]?.seconds ?? 0
    }

    /// Attach — or re-select, when it was made before — the copy carrying the offset dialled now.
    private func applySubtitleShiftNow() {
        guard let attached = selectedAttachedSubtitleFile,
              let base = selectedDownloadedSubtitleFile,
              let language = subtitleRows.first(where: { attachedTrackID($0) == selectedSubtitleID })?
                .language
        else { return }
        let target = Self.shiftTarget(subtitleDelay)
        guard target != carriedShift(of: attached) else { return }
        // One attach handshake at a time: a second would overwrite the first one's pending record
        // and leave it to time out as a failed download. Try again once this one has landed.
        guard pendingSubtitleAttach == nil else { reconcileSubtitleShift(); return }
        guard let url = target == 0 ? base : shiftedCopy(of: base, by: target) else { return }
        note("subtitle offset \(String(format: "%+.3f", target))s → \(url.lastPathComponent)")
        attach(url, language: language)
    }

    /// A copy of `base` with every cue moved by `seconds`, written once per offset.
    ///
    /// Each offset gets its own file NAME because libvlc keys a slave by URL: rewriting one file in
    /// place would be ignored as a duplicate, and the viewer would see nothing change. Written in
    /// the encoding the original was read in, for the windows-1255 Hebrew files that are not UTF-8.
    func shiftedCopy(of base: URL, by seconds: Double) -> URL? {
        if let made = subtitleShiftCopies.first(where: {
            $0.value.base == base && $0.value.seconds == seconds
        })?.key {
            return made
        }
        guard let (text, encoding) = Self.readSubtitleText(at: base) else { return nil }
        let ms = Int((seconds * 1000).rounded())
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
            "shift\(ms < 0 ? "m" : "p")\(abs(ms))-\(base.lastPathComponent)")
        guard (try? SubtitleRetimer.shift(text, by: seconds)
            .write(to: destination, atomically: true, encoding: encoding)) != nil
        else { return nil }
        subtitleShiftCopies[destination] = (base, seconds)
        return destination
    }
}
