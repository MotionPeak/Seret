import Foundation
import DebridCore

extension PlayerModel {

    // MARK: - Automatic subtitle sync
    //
    // ⚠️ BUILT, MEASURED, AND NOT OFFERED. The machinery works end to end — PCM out of libvlc, a
    // confirmed window, cue parsing, correlation, gates. What does not work is the FEATURE, and the
    // reason is the signal, not the plumbing.
    //
    // Measure a few minutes of the film's audio, line the subtitle's cues up against where the
    // speech actually is, and dial in the difference.
    //
    // Four things had to be right, and each was wrong first. They are recorded here because every
    // one of them produced a CONFIDENT wrong answer rather than an obvious failure:
    //
    // 1. `:stop-time` is scaled by the playback rate — 300s at 16x stopped the demuxer after 19
    //    seconds of media. `:start-time` is silently ignored on a network stream. The window is
    //    reached by seeking and then CONFIRMING with `player.time`.
    // 2. The audio callback's timestamp is OUTPUT-clock time, also rate-scaled, so at 16x every
    //    100ms frame spanned 1.6s of film. Rate 1, which costs nothing: throughput is bound by the
    //    network, not the decoder.
    // 3. **libvlc does not use WAVE channel order.** Its buffers follow VLC's own —
    //    `L, R, ML, MR, RL, RR, RC, C, LFE` with absent channels skipped — so 5.1 arrives as
    //    L, R, RL, RR, C, LFE and the centre is index 4. Reading index 2 correlated a SURROUND
    //    channel against dialogue cues, which is why loudness, band-limited centre and
    //    density-matched voice all produced confident nonsense that disagreed with each other.
    // 4. A single window cannot be believed. Even correct, the full-window search found +87s on a
    //    stretch where both halves said +0.1s — a lag leaving barely half the window overlapping.
    //    The search is now capped at a quarter of the window, and the answer must still hold on
    //    both halves.
    //
    // Verified on a real stream against a subtitle whose alignment was screenshot-confirmed (its
    // "מוסקבה, 1985" sits exactly on the film's own "MOSCOW, 1985" card, so the answer is zero):
    // measured +0.2s, peak 0.423, both halves agreeing, voice energy 3.4x higher under cues than
    // between them.

    /// The least audio worth correlating. Fewer lines than this and the peak is not a peak.
    static let autoSyncMinimumSeconds: Double = 60
    /// A measurement below this is a guess. `SubtitleSync` already refuses the unconvincing; this
    /// is the second gate, because dragging a correct subtitle into nonsense is the one outcome
    /// worse than doing nothing.
    static let autoSyncMinimumConfidence = 0.35

    /// How far a measurement has got, for the bar over the picture.
    public struct AutoSyncProgress: Equatable, Sendable {
        /// 0…1 of the window asked for.
        public let fraction: Double
        /// Seconds left, once there is enough history to say. Nil rather than a guess — the bar
        /// shows a plain "measuring" until it can be known.
        public let secondsRemaining: Int?

        public init(fraction: Double, secondsRemaining: Int?) {
            self.fraction = fraction
            self.secondsRemaining = secondsRemaining
        }

        /// "about 2 min left" / "about 40 sec left", or nil while it cannot be known.
        public var remainingText: String? {
            guard let secondsRemaining, secondsRemaining > 0 else { return nil }
            if secondsRemaining < 90 { return "about \(max(5, (secondsRemaining / 5) * 5)) sec left" }
            return "about \(Int((Double(secondsRemaining) / 60).rounded())) min left"
        }
    }

    /// What the strip across the top of the picture is saying, or nil when there should not be one.
    ///
    /// Derived rather than stored, so the bar cannot disagree with the measurement it describes.
    public struct AutoSyncBanner: Equatable, Sendable {
        /// Which of the three things the bar is doing, so the view picks a glyph and a tint without
        /// having to infer either from the wording.
        public enum Mood: Equatable, Sendable { case measuring, synced, failed }
        public let text: String
        public let mood: Mood
        /// 0…1 while there is something to fill, nil once the measurement is over and the bar is
        /// only reporting what happened.
        public let fraction: Double?

        public init(text: String, mood: Mood, fraction: Double?) {
            self.text = text
            self.mood = mood
            self.fraction = fraction
        }
    }

    /// The bar over the picture: progress while listening, then the outcome for a few seconds.
    public var autoSyncBanner: AutoSyncBanner? {
        if let autoSyncProgress {
            let left = autoSyncProgress.remainingText
            return AutoSyncBanner(text: left.map { "Syncing subtitles  ·  \($0)" }
                                          ?? "Syncing subtitles\u{2026}",
                                  mood: .measuring, fraction: autoSyncProgress.fraction)
        }
        return autoSyncOutcome.map {
            AutoSyncBanner(text: $0, mood: autoSyncState == .synced ? .synced : .failed,
                           fraction: nil)
        }
    }

    public enum AutoSyncState: Equatable, Sendable {
        case idle
        case measuring
        case synced
        /// Measured, and the answer was not worth acting on.
        case failed
    }

    /// Whether there is anything to sync.
    ///
    /// Only a DOWNLOADED subtitle qualifies, and that is not a shortcoming: a track muxed into the
    /// file was timed against that file by construction. Being out of step is something a subtitle
    /// fetched from somewhere else is, and for those we hold the actual cue times.
    public var canAutoSyncSubtitle: Bool { selectedDownloadedSubtitleFile != nil }

    /// The file backing the selected subtitle, if the selection is one we downloaded — the file as
    /// PREPARED, never a shifted copy of it. Everything keyed off this (the cue list a hand sync
    /// measures against, the offset remembered for the file, auto-sync's reading) describes the
    /// subtitle itself, and an offset is something applied TO it.
    var selectedDownloadedSubtitleFile: URL? {
        guard let attached = selectedAttachedSubtitleFile else { return nil }
        return subtitleShiftCopies[attached]?.base ?? attached
    }

    /// The file the selected track was actually attached from: a shifted copy while an offset is
    /// in effect, otherwise the same as `selectedDownloadedSubtitleFile`.
    var selectedAttachedSubtitleFile: URL? {
        guard let selectedSubtitleID else { return nil }
        return attachedSubtitleTracks.first { $0.value == selectedSubtitleID }?.key
    }

    /// Listen to a few minutes of the film, line the subtitle's cues up against what was said, and
    /// dial in the difference.
    ///
    /// The offset is applied as a DELAY rather than by rewriting the file: it is instant, it is
    /// undoable with the existing Reset, and it composes with a rate correction the retimer may
    /// already have applied on the way in.
    /// Begin a sync and return at once.
    ///
    /// The measurement takes minutes — reading the audio means downloading it — so it must not be
    /// something the viewer waits on. It is owned by the model rather than by the view that started
    /// it, so closing the settings panel and going back to the film leaves it running, and leaving
    /// the player stops it.
    public func startAutoSync() {
        guard autoSyncState != .measuring, canAutoSyncSubtitle else { return }
        autoSyncTask?.cancel()
        autoSyncTask = Task { @MainActor [weak self] in
            await self?.autoSyncSubtitle()
            self?.autoSyncTask = nil
        }
    }

    /// Put the outcome on the bar, and take it down again a few seconds later.
    ///
    /// Nothing is reported for a measurement the player cancelled on the way out: the viewer left,
    /// and the answer is about a film they are no longer watching.
    func reportAutoSyncOutcome(_ text: String) {
        guard !Task.isCancelled else { return }
        autoSyncOutcome = text
        autoSyncOutcomeTask?.cancel()
        autoSyncOutcomeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.autoSyncOutcomeSeconds ?? 0))
            guard !Task.isCancelled else { return }
            self?.autoSyncOutcome = nil
            self?.autoSyncOutcomeTask = nil
        }
    }

    /// Poll the probe for progress until the measurement ends.
    func trackAutoSyncProgress() {
        autoSyncProgressTask?.cancel()
        autoSyncProgressTask = Task { @MainActor [weak self] in
            while let self, self.autoSyncState == .measuring, !Task.isCancelled {
                self.pollAutoSyncProgress(now: Date())
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// One progress sample, folded into the smoothed estimate.
    ///
    /// `ETAEstimator` already exists for downloads and does the hard part — it prefers throughput
    /// observed across samples, smooths it, and returns nil rather than inventing a number when a
    /// stream stalls. A measurement that is bound by the same network has exactly the same problem.
    func pollAutoSyncProgress(now: Date) {
        guard let audioProbe else { return }
        let gathered = audioProbe.measuredSeconds
        let fraction = min(1, max(0, gathered / max(autoSyncWindow, 1)))
        let remaining = autoSyncETA.observe(fraction: fraction,
                                            totalBytes: Int(autoSyncWindow * 100),
                                            reportedSpeed: nil, at: now)
        autoSyncProgress = AutoSyncProgress(fraction: fraction,
                                            secondsRemaining: remaining.map { Int($0.rounded()) })
    }

    /// Test seam: take one sample, optionally pretending time has passed.
    func pollAutoSyncProgressForTesting(after seconds: TimeInterval = 0) async {
        pollAutoSyncProgress(now: Date().addingTimeInterval(seconds))
        await settleForTesting()
    }

    func autoSyncSubtitle() async {
        guard autoSyncState != .measuring,
              let audioProbe,
              let subtitleURL = selectedDownloadedSubtitleFile,
              let text = Self.readSubtitle(at: subtitleURL) else { return }

        autoSyncState = .measuring
        autoSyncETA = ETAEstimator()
        autoSyncProgress = AutoSyncProgress(fraction: 0, secondsRemaining: nil)
        autoSyncOutcome = nil
        trackAutoSyncProgress()
        note("auto-sync: measuring \(Int(autoSyncWindow))s of the talkiest stretch")
        // Read by the `defer`, which runs after whichever `return` the measurement takes — so the
        // bar reports the same thing on every path out, including the early refusals.
        var applied: Double?
        defer {
            if autoSyncState == .measuring { autoSyncState = .failed }
            autoSyncProgressTask?.cancel()
            autoSyncProgressTask = nil
            autoSyncProgress = nil          // the bar shows the outcome now, not the progress
            reportAutoSyncOutcome(applied.map {
                String(format: "Subtitles synced  ·  shifted %+.1fs", $0)
            } ?? "Couldn't sync the subtitles \u{2014} nudge the timing by hand")
        }

        guard let url = try? await unrestrict(currentSource.restrictedLink) else {
            note("auto-sync: could not open the media")
            return
        }
        let asked = autoSyncWindowStart(cues: SubtitleTiming.cueSpans(in: text))
        guard let window = await audioProbe.loudness(url: url, from: asked,
                                                     seconds: autoSyncWindow),
              !window.frames.isEmpty else { note("auto-sync: no audio decoded"); return }
        // Where it ACTUALLY read from, which a seek decides and we do not.
        let start = window.startSeconds
        let loudness = window.frames
        note(String(format: "auto-sync: window %.0fs (asked %.0fs)", start, asked))
        // What came back is however much the connection managed, not the window we asked for.
        let measured = Double(loudness.count) * SubtitleSync.frameSeconds
        note(String(format: "auto-sync: heard %.0fs of audio", measured))
        guard measured >= Self.autoSyncMinimumSeconds else {
            note("auto-sync: too little audio to measure")
            return
        }

        let cues = SubtitleTiming.activity(in: text, frameSeconds: SubtitleSync.frameSeconds,
                                           frames: loudness.count, startSeconds: start)

        // Voice, not volume. A loudness envelope measured NEGATIVE correlation at the true
        // alignment on a real action film — its loud passages are gunfire and score and carry no
        // subtitles, while the dialogue is quiet. So what gets correlated is the band-limited
        // CENTRE channel, weighted by how much of the mix it accounts for: a cinema mix puts
        // dialogue there and spreads everything else around it. A source with no usable centre
        // degrades to the old loudness reading rather than to nothing.
        let voice = window.centre.isEmpty
            ? loudness
            : VoiceActivity.score(centre: window.centre, mix: loudness)
        note("auto-sync: \(window.centre.isEmpty ? "no centre channel — using loudness" : "centre channel present")")

        // Thresholded at the density the SUBTITLE claims: the audio does not know how talkative
        // this stretch is, the cue list does, and matching the two makes the correlation comparable.
        let cueDensity = Double(cues.filter { $0 > 0 }.count) / Double(max(cues.count, 1))
        let matched = SpeechActivity.densest(voice, fraction: cueDensity)
        note("auto-sync: \(matched.filter { $0 > 0 }.count) voice frames, "
             + "\(cues.filter { $0 > 0 }.count) cue frames")

        // Everything below is diagnosis, not decision: three full correlation searches, a
        // frame-by-frame picture and a per-channel breakdown. It is what found the channel-order
        // bug and it must stay reachable — but a viewer pressing Sync should not pay for it, and
        // running it in the unit suite starved every sleep-based test on the machine.
        #if DEBUG
        if Self.subtitleProbeEnabled {
            let readings = [("voice", matched), ("voice-raw", voice),
                            ("loudness", loudness)].compactMap { name, signal in
                SubtitleSync.measure(speech: signal, cues: cues,
                                     frameSeconds: SubtitleSync.frameSeconds,
                                     maxLagSeconds: autoSyncMaxLag)
                    .map { (name, $0) }
            }
            for (name, m) in readings { note("auto-sync: \(name) → \(m.summary)") }
            // What the CORRECT answer would have scored, when there is reason to think it is zero.
            // Without this a rejection cannot be told from a signal carrying no information at all.
            let atZero = SubtitleSync.correlation(speech: matched, cues: cues, lag: 0)
            note(String(format: "auto-sync: score at no-shift %.3f", atZero))
            // The single number that separates "the feature is wrong" from "the frames are in the wrong
            // place". If the centre channel really carries dialogue AND the frames line up with media
            // time, centre energy during cue frames must clearly exceed centre energy between them.
            // Equal or inverted means the two signals are not describing the same instants, whatever
            // the correlation search then makes of them.
            // The two signals side by side, one character per frame, so where the energy actually sits
            // relative to the cues can be SEEN rather than inferred from a summary statistic. Every
            // number so far has been an average, and an average cannot tell "shifted" from "unrelated".
            if let centre = window.perChannel.dropFirst(4).first, centre.count == cues.count {
                // Scale to a high PERCENTILE, not the maximum: one door-slam in the centre channel
                // flattens every line of dialogue to the bottom bucket and the picture shows nothing.
                let sorted = centre.sorted()
                let peak = sorted[Int(Double(sorted.count - 1) * 0.9)]
                func strip(_ range: Range<Int>) -> (String, String) {
                    let c = range.map { cues[$0] > 0 ? "#" : "." }.joined()
                    let e = range.map { i -> String in
                        let level = Int((centre[i] / max(peak, 1e-9)) * 9)
                        return level <= 0 ? " " : String(level)
                    }.joined()
                    return (c, e)
                }
                for block in 0..<3 {
                    let lo = block * 120, hi = min(lo + 120, cues.count)
                    guard lo < hi else { break }
                    let (c, e) = strip(lo..<hi)
                    note("auto-sync: cues \(Int(start) + lo / 10)s |\(c)|")
                    note("auto-sync: C    \(Int(start) + lo / 10)s |\(e)|")
                }
            }

            // The correlation profile around no-shift. The search reports only its winner; this shows
            // whether there is a bump near zero at all — a real signal beaten by noise elsewhere looks
            // quite different from no signal.
            let profile = stride(from: -30.0, through: 30.0, by: 3.0).map { lagSeconds -> String in
                let score = SubtitleSync.correlation(speech: voice, cues: cues,
                                                     lag: Int(lagSeconds / SubtitleSync.frameSeconds))
                return String(format: "%+.0f:%+.2f", lagSeconds, score)
            }
            note("auto-sync: profile \(profile.joined(separator: " "))")

            // Which channel, if any, is louder when a subtitle is on screen? A ratio above 1 means that
            // channel tracks the dialogue; all of them below 1 means the frames are not where we think
            // they are, and no choice of channel can rescue it.
            // VLC's own order for 5.1, not WAVE order — see `AudioActivityProbe.centreChannel`.
            let names = ["L", "R", "RL", "RR", "C", "LFE"]
            for (i, ch) in window.perChannel.enumerated() where ch.count == cues.count {
                let on = zip(ch, cues).filter { $0.1 > 0 }.map { Double($0.0) }
                let off = zip(ch, cues).filter { $0.1 == 0 }.map { Double($0.0) }
                guard !on.isEmpty, !off.isEmpty else { continue }
                let a = on.reduce(0, +) / Double(on.count), b = off.reduce(0, +) / Double(off.count)
                note(String(format: "auto-sync: channel %@ during/between = %.2f",
                            i < names.count ? names[i] : "\(i)", a / Swift.max(b, 1e-9)))
            }
            let during = zip(voice, cues).filter { $0.1 > 0 }.map { Double($0.0) }
            let between = zip(voice, cues).filter { $0.1 == 0 }.map { Double($0.0) }
            if !during.isEmpty, !between.isEmpty {
                let a = during.reduce(0, +) / Double(during.count)
                let b = between.reduce(0, +) / Double(between.count)
                note(String(format: "auto-sync: voice during cues %.5f vs between %.5f (ratio %.2f)",
                            a, b, a / Swift.max(b, 1e-9)))
            }

            // What each half says on its own, so a refusal can be read rather than guessed at.
            let halfLen = min(voice.count, cues.count) / 2
            for (name, r) in [("half 1", 0..<halfLen), ("half 2", halfLen..<min(voice.count, cues.count))] {
                if let m = SubtitleSync.measure(speech: Array(voice[r]), cues: Array(cues[r]),
                                                frameSeconds: SubtitleSync.frameSeconds,
                                                maxLagSeconds: autoSyncMaxLag) {
                    note("auto-sync: \(name) → \(m.summary)")
                } else {
                    note("auto-sync: \(name) → no measurement")
                }
            }
        }
        #endif

        // …and it has to hold on both halves of the window. A single measurement cannot tell a real
        // alignment from a peak that a self-similar stretch happens to support: with everything
        // else working, one window measured this subtitle exactly and another, later in the same
        // film, confidently measured +87 seconds. Splitting costs no extra audio.
        guard let best = SubtitleSync.corroboratedEstimate(
                speech: voice, cues: cues, frameSeconds: SubtitleSync.frameSeconds,
                maxLagSeconds: autoSyncMaxLag, minimumHalfSeconds: autoSyncMinimumHalf),
              best.confidence >= Self.autoSyncMinimumConfidence else {
            note("auto-sync: no answer the two halves agree on — leaving the subtitle alone")
            return
        }

        // A cancelled measurement has been superseded — by a hand sync, or by the player leaving.
        // Cancellation is cooperative, so the result is already in hand by the time the await
        // returns, and applying it would move a subtitle the viewer has just dialled in
        // themselves — minutes after they stopped looking at it.
        guard !Task.isCancelled else {
            note("auto-sync: cancelled before applying — leaving the subtitle as it is")
            return
        }

        note(String(format: "auto-sync: applying %+.1fs (confidence %.2f)",
                    best.offsetSeconds, best.confidence))
        applySubtitleDelay(best.offsetSeconds)
        applied = best.offsetSeconds
        autoSyncState = .synced
    }

    /// Where in the film to listen.
    ///
    /// Not the opening: a release's first minutes are idents, black and a theme, which is both the
    /// least dialogue in the film and the part most likely to differ between releases — exactly
    /// the stretch that makes a subtitle wrong in the first place. A fifth of the way in is
    /// ordinary talking. Short media fall back to the start rather than past the end.
    func autoSyncWindowStart(cues: [(start: Double, end: Double)]) -> Double {
        #if DEBUG
        // `-autoSyncFrom <seconds>` pins the window, so one variable can be held still while
        // another is measured.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-autoSyncFrom"), i + 1 < args.count,
           let pinned = Double(args[i + 1]) { return pinned }
        #endif
        guard duration > autoSyncWindow * 2 else { return 0 }
        let latest = duration - autoSyncWindow
        // The TALKIEST window, chosen from the subtitle's own cue list.
        //
        // A fixed fraction of the way in is a guess about where the dialogue is, and on a real
        // action film it guessed wrong: the default window landed on a stretch whose correlation
        // peak was 0.12 and was refused, while a window over an ordinary conversation measured the
        // offset exactly. The cue list already says where the talking is, and consulting it costs
        // nothing — the audio has not been fetched yet.
        guard !cues.isEmpty else { return min(duration * 0.2, latest) }
        var best = min(duration * 0.2, latest)
        var bestCoverage = -1.0
        // Skip the opening: a release's first minutes are idents and titles, and are the part most
        // likely to differ between releases — exactly what makes a subtitle wrong to begin with.
        var start = min(120, latest)
        while start <= latest {
            let end = start + autoSyncWindow
            let coverage = cues.reduce(0.0) { sum, cue in
                sum + max(0, min(cue.end, end) - max(cue.start, start))
            }
            if coverage > bestCoverage { bestCoverage = coverage; best = start }
            start += 60
        }
        return best
    }

    /// Read a subtitle file as text, tolerating the encodings these files actually use.
    ///
    /// The same order `prepareSubtitle` uses, and for the same reason: a Hebrew file is often
    /// windows-1255, which is not valid UTF-8, and `isoLatin1` decodes any byte without failing.
    /// Only the timestamps are read here and those are ASCII either way.
    static func readSubtitle(at url: URL) -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        return try? String(contentsOf: url, encoding: .isoLatin1)
    }
}
