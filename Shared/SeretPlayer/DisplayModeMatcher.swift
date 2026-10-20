#if os(tvOS)
import UIKit
import AVKit
import AVFoundation
import CoreMedia
import DebridCore

/// Puts the TV in the film's own display mode — its frame rate and dynamic range — the way AVPlayer
/// does for itself and libvlc never does.
///
/// Without it the Apple TV stayed in its interface mode (typically 2160p 60 Hz) for every film, and
/// its own log showed what that costs: a 23.976 fps HDR10 remux dropped two pictures every second,
/// each one frame period late, for the whole film (QA sweep 2026-10-20, §2c). The owner's "Match
/// Content" settings could never take effect for Seret.
///
/// The request is a hint the system honours only as those settings allow (`Match Content` off →
/// nothing changes). It is made BEFORE the file is loaded, from the file's own header, so the TV
/// switches once and the switch is over before the first frame — a switch blanks the screen for a
/// second or two, and mid-playback that would be a second lost from the film. Only when the header
/// gives no frame rate does it wait for libvlc's video track, which still comes before the first
/// picture. An unknown dynamic range leaves the display alone: asking for SDR on an HDR film would
/// be worse than not asking.
@MainActor
final class DisplayModeMatcher {
    private let note: @Sendable (String) -> Void
    private weak var manager: AVDisplayManager?
    /// What this player has asked the display for; nil before any request and after `reset`.
    private(set) var applied: DisplayModePlan?
    /// A plan still waiting for libvlc's frame rate.
    private var pending: DisplayModePlan?

    /// The longest the header read may take before the film loads without it.
    static let probeTimeout: Double = 2.5
    /// How long to watch for a switch starting after the request. Most requests change nothing
    /// (the mode already matches), and those must not hold the film back for long.
    static let switchStartGrace: Double = 0.3
    /// The longest a switch is waited out before the film loads anyway.
    static let switchTimeout: Double = 4

    init(note: @escaping @Sendable (String) -> Void) {
        self.note = note
    }

    /// Ask for `url`'s mode and wait out the switch it causes. Bounded by `probeTimeout` +
    /// `switchStartGrace` + `switchTimeout`, and returns at once when matching is off.
    func prepare(url: URL, window: UIWindow?) async {
        pending = nil
        guard let manager = window?.avDisplayManager ?? Self.keyWindow()?.avDisplayManager else {
            note("display: no window to ask")
            return
        }
        self.manager = manager
        guard manager.isDisplayCriteriaMatchingEnabled else {
            note("display: Match Content is off in Settings — mode left alone")
            return
        }
        let started = Date()
        let probe = await Self.probeVideoTrack(url, timeout: Self.probeTimeout)
        guard !Task.isCancelled else { return }
        let video: ContainerTrack?
        switch probe {
        case .found(let track): video = track
        case .none: video = nil
        case .timedOut:
            note("display: header read timed out after \(Self.probeTimeout)s")
            video = nil
        }
        guard let plan = DisplayModePlan.plan(video: video, fileName: url.lastPathComponent) else {
            note("display: dynamic range unknown (\(video == nil ? "no header" : "header silent")) — mode left alone")
            return
        }
        guard plan.refreshRate != nil else {
            pending = plan
            note("display: \(plan.range.rawValue), frame rate not in the header — waiting for the player's")
            return
        }
        await apply(plan, to: manager, waitForSwitch: true, since: started)
    }

    /// libvlc reported the video track: complete a plan that was waiting for its frame rate.
    func videoTrackAppeared(fps: Double?) {
        guard let plan = pending, let manager else { return }
        let full = plan.with(fps: fps)
        guard full.refreshRate != nil else { return }
        pending = nil
        Task { await apply(full, to: manager, waitForSwitch: false, since: Date()) }
    }

    /// The film is over: hand the display back to the interface's mode.
    func reset() {
        pending = nil
        guard applied != nil else { return }
        applied = nil
        manager?.preferredDisplayCriteria = nil
        note("display: back to the interface's mode")
    }

    private func apply(_ plan: DisplayModePlan, to manager: AVDisplayManager, waitForSwitch: Bool,
                       since started: Date) async {
        let label = Self.describe(plan)
        guard plan != applied else {
            note("display: already \(label)")
            return
        }
        guard let criteria = Self.criteria(for: plan) else { return }
        manager.preferredDisplayCriteria = criteria
        applied = plan
        note("display: asked for \(label) (+\(Self.ms(since: started)))")
        guard waitForSwitch else { return }
        let graceEnd = Date().addingTimeInterval(Self.switchStartGrace)
        while !manager.isDisplayModeSwitchInProgress, Date() < graceEnd, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard manager.isDisplayModeSwitchInProgress else {
            note("display: no switch started (+\(Self.ms(since: started)))")
            return
        }
        let switchStarted = Date()
        let deadline = switchStarted.addingTimeInterval(Self.switchTimeout)
        while manager.isDisplayModeSwitchInProgress, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let still = manager.isDisplayModeSwitchInProgress
        note("display: switch \(still ? "still running after" : "done in") \(Self.ms(since: switchStarted))"
             + " — loading the film (+\(Self.ms(since: started)))")
    }

    /// The criteria for a plan. The format description carries only what the display mode is
    /// chosen from — the transfer function, primaries and matrix — on an HEVC description.
    static func criteria(for plan: DisplayModePlan) -> AVDisplayCriteria? {
        guard let rate = plan.refreshRate else { return nil }
        let (primaries, transfer, matrix): (CFString, CFString, CFString)
        switch plan.range {
        case .sdr:
            (primaries, transfer, matrix) = (kCMFormatDescriptionColorPrimaries_ITU_R_709_2,
                                             kCMFormatDescriptionTransferFunction_ITU_R_709_2,
                                             kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2)
        case .hdr10:
            (primaries, transfer, matrix) = (kCMFormatDescriptionColorPrimaries_ITU_R_2020,
                                             kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ,
                                             kCMFormatDescriptionYCbCrMatrix_ITU_R_2020)
        case .hlg:
            (primaries, transfer, matrix) = (kCMFormatDescriptionColorPrimaries_ITU_R_2020,
                                             kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG,
                                             kCMFormatDescriptionYCbCrMatrix_ITU_R_2020)
        }
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_ColorPrimaries: primaries,
            kCMFormatDescriptionExtension_TransferFunction: transfer,
            kCMFormatDescriptionExtension_YCbCrMatrix: matrix,
        ]
        var description: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                    codecType: kCMVideoCodecType_HEVC,
                                                    width: 3840, height: 2160,
                                                    extensions: extensions as CFDictionary,
                                                    formatDescriptionOut: &description)
        guard status == noErr, let description else { return nil }
        return AVDisplayCriteria(refreshRate: Float(rate), formatDescription: description)
    }

    // MARK: - The header

    enum Probe: Sendable {
        case found(ContainerTrack)
        case none
        case timedOut
    }

    /// The video track from the file's header, read through the URL libvlc is about to open (the
    /// stream cache's, normally — so the bytes are then already in RAM for libvlc).
    ///
    /// Raced against `timeout` without a task group: `ContainerProbe`'s read does not stop for
    /// cancellation, and a group would wait for it anyway. A late read simply finishes unheard.
    static func probeVideoTrack(_ url: URL, timeout: Double) async -> Probe {
        let once = ProbeOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Probe, Never>) in
            once.install(continuation)
            Task.detached {
                let outcome = await ContainerProbe().tracks(at: url)
                guard case .tracks(let tracks)? = outcome,
                      let video = tracks.first(where: { $0.kind == .video }) else {
                    once.finish(.none)
                    return
                }
                once.finish(.found(video))
            }
            Task.detached {
                try? await Task.sleep(for: .seconds(timeout))
                once.finish(.timedOut)
            }
        }
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }

    static func describe(_ plan: DisplayModePlan) -> String {
        let rate = plan.refreshRate.map { String(format: "%.3f Hz", $0) } ?? "? Hz"
        return "\(rate) \(plan.range.rawValue.uppercased())"
    }

    private static func ms(since date: Date) -> String {
        "\(Int(Date().timeIntervalSince(date) * 1000))ms"
    }
}

/// Resumes a continuation once — with the probe's answer or the timeout, whichever comes first.
private final class ProbeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DisplayModeMatcher.Probe, Never>?
    private var early: DisplayModeMatcher.Probe?
    private var done = false

    func install(_ continuation: CheckedContinuation<DisplayModeMatcher.Probe, Never>) {
        lock.lock()
        if let early {
            lock.unlock()
            continuation.resume(returning: early)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func finish(_ result: DisplayModeMatcher.Probe) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil { early = result }
        lock.unlock()
        continuation?.resume(returning: result)
    }
}
#endif
