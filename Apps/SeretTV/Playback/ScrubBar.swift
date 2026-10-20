import SwiftUI
import DebridUI

/// The player's transport line: play/pause glyph · elapsed · a thin white bar with a round knob ·
/// time remaining.
///
/// The bar is 8pt while watching and 10pt while paused or scrubbing — being paused IS scrub mode,
/// so the thicker bar and the larger knob are the scrub-mode indicator, and they hold for the whole
/// pause instead of flickering on every thumb contact. While scrubbing the target time floats above
/// the knob and a tick marks the live playhead (the return point if the scrub is cancelled).
///
/// The ±skip badge also rides above the knob: a white pill that accumulates (+10s, +20s, +1:10)
/// and follows the knob along the bar, clamped so it never leaves the bar's span.
struct ScrubBar: View {
    @Bindable var model: PlayerModel
    let buffering: Bool
    /// Off while the side sheet covers the bar's right end.
    var showsRemaining: Bool = true

    /// The flanking timecodes always show the LIVE playhead — where you are, and where you return
    /// to if you cancel a scrub. The scrub TARGET is shown only in the floating time over the
    /// knob, so the two never duplicate each other.
    private var flankTime: Double { model.position }
    /// The fill and knob sit at the scrub target while scrubbing, the playhead otherwise.
    private var headTime: Double { model.isScrubbing ? model.scrubTarget : model.position }
    private var headFraction: Double {
        model.duration > 0 ? min(1, max(0, headTime / model.duration)) : 0
    }
    /// Paused or scrubbing — see the type's comment.
    private var expanded: Bool { model.isScrubbing || model.phase == .paused }

    private var trackHeight: CGFloat { expanded ? 10 : 8 }
    private var knobDiameter: CGFloat { expanded ? 30 : 22 }
    private static let laneHeight: CGFloat = 34
    /// The knob's centre travels from this far inside one end of the track to this far inside the
    /// other, so the largest knob never overhangs the track's rounded ends.
    private static let knobInset: CGFloat = 15
    private static let timeFont = Font.seret(28, .semibold)

    /// The loading hint, shown only once a wait has outlasted `hintDelay`.
    ///
    /// Every ±10s skip raises `buffering` the moment it is pressed, and nothing lowers it before the
    /// next once-a-second tick — so even a skip the stream cache answered in a tenth of a second
    /// flashed a spinner for one to two seconds. A real wait still shows it.
    @State private var showsLoadingHint = false
    private static let hintDelay: Duration = .milliseconds(600)
    /// The skip badge's measured width, for clamping it inside the bar.
    @State private var badgeWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 24) {
            stateGlyph
            Text(Timecode.format(flankTime))
                .font(Self.timeFont).monospacedDigit()
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(minWidth: 110, alignment: .leading)
            track
            Text("-" + Timecode.format(max(0, model.duration - flankTime)))
                .font(Self.timeFont).monospacedDigit()
                .foregroundStyle(Theme.Palette.textPrimary.opacity(0.8))
                .frame(minWidth: 130, alignment: .trailing)
                .opacity(showsRemaining ? 1 : 0)
                .animation(Theme.Anim.pageFade, value: showsRemaining)
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
        .task(id: buffering) {
            guard buffering else { showsLoadingHint = false; return }
            try? await Task.sleep(for: Self.hintDelay)
            if !Task.isCancelled { showsLoadingHint = true }
        }
        .animation(Theme.Anim.focus, value: expanded)
        .animation(Theme.Anim.focus, value: showsLoadingHint)
        .animation(Theme.Anim.focus, value: model.skipFeedback)
    }

    /// The STATE, as Plex draws it — ⏸ while paused, ▶ while playing — matching the paused glyph
    /// in the middle of the frame; or a spinner while a wait has outlasted the hint delay. One fixed
    /// slot, so neither swap moves the timecode.
    private var stateGlyph: some View {
        ZStack {
            Image(systemName: model.phase == .paused ? "pause.fill" : "play.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .opacity(showsLoadingHint ? 0 : 1)
            ProgressView()
                .controlSize(.small)
                .tint(Theme.Palette.textPrimary)
                .opacity(showsLoadingHint ? 1 : 0)
        }
        .frame(width: 40, height: 40)
        .accessibilityLabel(showsLoadingHint ? "Loading" : (model.phase == .paused ? "Paused" : "Playing"))
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            // One mapping from time to x for the fill's end, the knob, the tick and the badge, inset
            // so the knob stays on the track at both ends.
            let span = max(0, width - Self.knobInset * 2)
            let headX = Self.knobInset + span * headFraction
            let playheadX = Self.knobInset + span * (model.duration > 0
                ? min(1, max(0, model.position / model.duration)) : 0)
            let midY = geo.size.height / 2

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.track)
                    .frame(width: width, height: trackHeight)
                Capsule().fill(Theme.Palette.focus)
                    .frame(width: headX, height: trackHeight)
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)

            // A distinct tick at the LIVE playhead so, while scrubbing, "where you are" (and the
            // return point if you cancel) is always visible — regardless of which way you drag.
            if model.isScrubbing {
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: trackHeight + 12)
                    .position(x: playheadX, y: midY)
            }

            Circle()
                .fill(Theme.Palette.focus)
                .frame(width: knobDiameter, height: knobDiameter)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                .position(x: headX, y: midY)

            if model.isScrubbing {
                Text(Timecode.format(model.scrubTarget))
                    .font(.seret(30, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
                    .fixedSize()
                    .position(x: clamped(headX, halfWidth: 60, in: width), y: midY - 44)
            } else if let feedback = model.skipFeedback {
                SkipBadge(feedback: feedback)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { badgeWidth = $0 }
                    // Unseen until it has been measured once: its first frame would otherwise be
                    // placed with a zero width — unclamped, half off the bar at either end.
                    .opacity(badgeWidth > 0 ? 1 : 0)
                    .position(x: clamped(headX, halfWidth: badgeWidth / 2, in: width), y: midY - 42)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .frame(height: Self.laneHeight)
    }

    /// Keeps something centred on the knob inside the bar's span.
    private func clamped(_ x: CGFloat, halfWidth: CGFloat, in width: CGFloat) -> CGFloat {
        guard width > halfWidth * 2 else { return width / 2 }
        return min(width - halfWidth, max(halfWidth, x))
    }
}

/// The accumulating skip amount: a white pill, dark text, the number rolling in place. Driven by
/// the shared `PlayerModel.skipFeedback` — the same state the iPad badge uses.
private struct SkipBadge: View {
    let feedback: PlayerModel.SkipFeedback

    var body: some View {
        Text((feedback.seconds < 0 ? "\u{2212}" : "+") + feedback.label)
            .font(.seret(24, .bold))
            .monospacedDigit()
            .contentTransition(.numericText(value: feedback.seconds))
            .foregroundStyle(Theme.Palette.onFocus)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Theme.Palette.focus, in: Capsule())
            .fixedSize()
    }
}
