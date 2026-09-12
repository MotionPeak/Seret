import Foundation
import VLCKit
import DebridCore
import os

/// Decodes a window of a stream's audio and reports how loud each 100ms of it was — the signal
/// `SubtitleSync` lines subtitle cues up against.
///
/// A SECOND, headless player, never the one on screen. `libvlc_audio_set_callbacks` replaces the
/// audio OUTPUT, so pointing it at the playing media would silence the film. This one decodes with
/// `--no-video`, sends its audio to us instead of to a speaker, and runs as fast as the source will
/// feed it.
///
/// It costs bandwidth: the audio is interleaved with video in the container, so reading four
/// minutes of audio pulls four minutes of the file. That is inherent to measuring the real audio
/// rather than guessing, and it is why the window is small and the whole thing is on request
/// rather than automatic.
@MainActor
final class AudioActivityProbe: AudioLoudnessProbing {

    /// One frame of the loudness signal. 100ms matches `SubtitleSync`'s default frame: fine enough
    /// to place a cue, coarse enough that a direct correlation search stays cheap.
    static let frameSeconds = 0.1
    /// 8 kHz mono. A loudness envelope needs no more, and it is eight times less to decode and
    /// sum than the 48 kHz stereo the file actually carries.
    private static let sampleRate: UInt32 = 8000
    /// The longest we will spend measuring, whatever arrives. Generous, because decoding runs at
    /// roughly download speed and the whole point is to gather as much as the connection allows —
    /// but bounded, because a dead link must end as "no estimate" rather than a spinner.
    static let measurementCeiling: Double = 240

    private let player: VLCMediaPlayer
    private let collector: Collector
    private var finished: CheckedContinuation<[Float], Never>?
    private var requestedStart: Double = 0
    private var watchdog: Task<Void, Never>?

    init() {
        // Its own libvlc instance (that is what `options:` gets you), so nothing here can disturb
        // the player the viewer is watching.
        player = VLCMediaPlayer(options: ["--no-video", "--no-osd", "--no-spu"])
        collector = Collector(frameSeconds: Self.frameSeconds)
    }

    /// Loudness per frame for roughly `seconds` of audio starting at `from`, or an empty array if
    /// nothing could be decoded.
    ///
    /// - Parameter from: where in the media to start. Sampling from the opening would measure
    ///   studio idents and silence on many releases, so callers pass a point inside the film.
    func loudness(url: URL, from startSeconds: Double, seconds: Double) async -> LoudnessWindow? {
        guard let media = VLCMedia(url: url) else { return nil }
        media.addOption(":no-video")
        media.addOption(":network-caching=1500")
        media.addOption(":input-fast-seek")
        // NO `:start-time`. It is silently ignored on a network stream — measured: asked for
        // 1427s, the player reported it had read from zero — so the audio described the opening
        // titles while the cues described minute twenty-four, and the correlation duly invented a
        // sixty-three-second correction. The window is reached by seeking and then CONFIRMING,
        // below, because the only trustworthy answer is the one the player gives back.
        //
        // NO `:stop-time` either: it is scaled by the playback rate, so asking for 300s while
        // decoding at 16x stopped the demuxer after 300/16 ≈ 19 seconds of media.
        let raw = player.libVLCMediaPlayer
        libvlc_audio_set_format(raw, "S16N", Self.sampleRate, 1)
        libvlc_audio_set_callbacks(raw, audioPlayCallback, nil, nil, nil, nil,
                                   Unmanaged.passUnretained(collector).toOpaque())
        player.media = media
        player.play()
        // Rate 1, deliberately.
        //
        // Decoding "as fast as possible" looks like the obvious win and is not. The timestamp the
        // audio callback carries is OUTPUT-clock time, which libvlc scales by the rate — so at 16x
        // every 100ms frame actually spanned 1.6 seconds of film, and the entire signal was
        // compressed sixteen-fold against the cue list it was matched against. It produced
        // confident, repeatable nonsense: three different readings agreeing on an offset that was
        // impossible on its face.
        //
        // Nothing was lost by dropping it. Measured against the same stream, throughput is bound by
        // the network — the audio is interleaved with 2160p video, so reading N seconds of it means
        // downloading N seconds of the file — and 16x delivered the same 235 seconds of audio in
        // the same four minutes that 1x does.
        player.rate = 1

        // Reach the window, then believe only what the player says about where it is.
        guard let origin = await seekAndConfirm(startSeconds) else {
            player.stop()
            return nil
        }
        // Everything decoded on the way to the window is not the window. Only now does the
        // collector start, so its first frame really is `origin`.
        collector.reset(frameBudget: Int(seconds / Self.frameSeconds))
        collector.arm()

        let frames = await withCheckedContinuation { (c: CheckedContinuation<[Float], Never>) in
            finished = c
            collector.onComplete = { [weak self] in
                Task { @MainActor in self?.finish() }
            }
            // …and give up regardless. A dead link, a refused range request or a stream that simply
            // will not decode must end as "no estimate", never as a spinner nothing clears.
            watchdog = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.measurementCeiling))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        }
        guard !frames.isEmpty else { return nil }
        return LoudnessWindow(frames: frames, startSeconds: origin)
    }

    /// Seek to `target` and wait until the player agrees it is there, returning the media time it
    /// actually reached — which is what the frames will be measured from.
    ///
    /// A seek lands on a keyframe, so "where I asked" and "where I am" differ by seconds; taking
    /// the request as truth is what made a correct subtitle look sixty-three seconds out. At rate 1
    /// the playhead advances a second per second, so polling this often bounds the error well
    /// inside one 100ms frame.
    private func seekAndConfirm(_ target: Double) async -> Double? {
        // Wait for the media to open at all — seeking a player that has not started does nothing.
        for _ in 0..<200 {
            if player.isPlaying, player.time.intValue > 0 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard player.isPlaying else { return nil }
        guard target > 0 else { return Double(player.time.intValue) / 1000 }

        player.time = VLCTime(int: Int32(target * 1000))
        for _ in 0..<400 {                                   // up to 20s to land
            let now = Double(player.time.intValue) / 1000
            if abs(now - target) < 5 { return now }          // arrived, at whatever keyframe
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil                                           // never got there — no measurement
    }

    /// Tear the probe down and hand back whatever was collected. Idempotent — the collector's
    /// completion and the watchdog race by design, and only the first one may resume.
    private func finish() {
        guard let continuation = finished else { return }
        finished = nil
        watchdog?.cancel()
        watchdog = nil
        let frames = collector.frames()
        collector.onComplete = nil
        // Where the probe ACTUALLY read from, which is the assumption the whole measurement rests
        // on: frame 0 is taken to be the media time that was asked for.
        NSLog("[probe] collected %d frames; player ended at %.1fs (asked to start at %.1fs)",
              frames.count, Double(player.time.intValue) / 1000, requestedStart)
        libvlc_audio_set_callbacks(player.libVLCMediaPlayer, nil, nil, nil, nil, nil, nil)
        player.stop()
        continuation.resume(returning: frames)
    }

    func cancel() { finish() }
}

/// Accumulates loudness per frame, written from libvlc's audio thread and read from the main actor.
///
/// A plain class behind a lock rather than an actor: the writer is a C callback with no way to
/// await anything, and it runs thousands of times a second.
private final class Collector: @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<State>
    private let frameSeconds: Double
    /// Called once the frame budget is full. Set and cleared on the main actor.
    nonisolated(unsafe) var onComplete: (() -> Void)?

    private struct State {
        var sums: [Double] = []
        var counts: [Int] = []
        var budget = 0
        var firstPTS: Int64?
        var complete = false
        /// Chunks arriving before this is set are on the way to the window, not in it.
        var armed = false
    }

    init(frameSeconds: Double) {
        self.frameSeconds = frameSeconds
        state = OSAllocatedUnfairLock(initialState: State())
    }

    func reset(frameBudget: Int) {
        state.withLock {
            $0 = State(sums: [Double](repeating: 0, count: max(frameBudget, 1)),
                       counts: [Int](repeating: 0, count: max(frameBudget, 1)),
                       budget: max(frameBudget, 1), firstPTS: nil, complete: false, armed: false)
        }
    }

    /// Begin accepting chunks. Called once the player has confirmed it is at the window, so the
    /// first chunk after this really is the window's first frame.
    func arm() { state.withLock { $0.armed = true; $0.firstPTS = nil } }

    /// Root-mean-square of one decoded chunk, added to the frame its timestamp falls in.
    ///
    /// Frames are placed by PTS relative to the FIRST chunk seen, not by arrival order: libvlc
    /// delivers chunks of varying length and a seek can reorder them, and counting arrivals would
    /// smear the signal by exactly the amount we are trying to measure.
    func add(samples: UnsafePointer<Int16>, count: Int, pts: Int64) {
        guard count > 0 else { return }
        var sum = 0.0
        for i in 0..<count {
            let v = Double(samples[i]) / 32768.0
            sum += v * v
        }
        let rms = (sum / Double(count)).squareRoot()

        let done: Bool = state.withLock { s in
            guard s.armed, !s.complete else { return false }
            let origin = s.firstPTS ?? pts
            if s.firstPTS == nil { s.firstPTS = pts }
            let offset = Double(pts - origin) / 1_000_000.0          // libvlc PTS is microseconds
            let index = Int(offset / frameSeconds)
            guard index >= 0 else { return false }
            guard index < s.budget else {
                s.complete = true
                return true
            }
            s.sums[index] += rms
            s.counts[index] += 1
            return false
        }
        if done { onComplete?() }
    }

    /// The mean loudness of each frame, TRIMMED to what actually arrived.
    ///
    /// The budget is a ceiling, not a promise: the audio is interleaved with video, so decoding it
    /// runs at roughly the speed the file can be downloaded — about real time on a 2160p release.
    /// Padding the tail with zeros would hand `SubtitleSync` minutes of fabricated silence to
    /// correlate against, which is worse than a shorter honest window. Measured on a real stream:
    /// 659 of 3000 frames in ninety seconds, and those 659 are perfectly good.
    func frames() -> [Float] {
        state.withLock { s in
            guard let last = s.counts.lastIndex(where: { $0 > 0 }) else { return [] }
            return zip(s.sums, s.counts).prefix(last + 1)
                .map { $1 > 0 ? Float($0 / Double($1)) : 0 }
        }
    }
}

/// libvlc's audio "output". Called on libvlc's own thread, thousands of times a second — it does
/// arithmetic and takes one uncontended lock, and nothing else.
private let audioPlayCallback: seret_audio_play_cb = { data, samples, count, pts in
    guard let data, let samples else { return }
    let collector = Unmanaged<Collector>.fromOpaque(data).takeUnretainedValue()
    collector.add(samples: samples.assumingMemoryBound(to: Int16.self), count: Int(count), pts: pts)
}
