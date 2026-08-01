import SwiftUI
import DebridUI

/// The player's transport bar.
///
/// At rest it is a 3pt hairline that does not compete with the picture. The moment the viewer
/// touches the remote it lifts into a gold-outlined glass slab, the track triples in thickness,
/// the handle becomes the Seret play mark and the target timecode floats above it. That state
/// change IS the scrub-mode indicator — the old bar looked identical whether you were scrubbing or
/// watching, which is what made scrubbing feel like nothing was happening.
struct ScrubBar: View {
    @Bindable var model: PlayerModel
    let buffering: Bool

    /// The flanking timecodes always show the LIVE playhead — where you are, and where you return
    /// to if you cancel a scrub. The scrub TARGET is shown only in the floating bubble over the
    /// handle, so the two never duplicate each other.
    private var flankTime: Double { model.position }
    /// The fill and handle sit at the scrub target while scrubbing, the playhead otherwise.
    private var headTime: Double { model.isScrubbing ? model.scrubTarget : model.position }
    private var headFraction: Double {
        model.duration > 0 ? min(1, max(0, headTime / model.duration)) : 0
    }
    /// The bar has two presentations, and PAUSE — not thumb-contact — decides which.
    ///
    /// Being paused IS scrub mode now, so the expanded slab stays up for the whole pause instead of
    /// snapping open on touch-down and collapsing on lift. Tying it to `isScrubbing` alone made it
    /// flicker between the two looks on every contact while aiming, which is what "it pops back off
    /// and on" described. It returns to the thin resting bar when playback resumes.
    private var expanded: Bool { model.isScrubbing || model.phase == .paused }

    private var trackHeight: CGFloat { expanded ? 8 : 3 }
    private var timeFont: Font {
        .seret(expanded ? 24 : 20, .semibold)
    }
    private var timeColor: Color {
        expanded ? Theme.Palette.textPrimary : Theme.Palette.textSecondary
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                Text(Timecode.format(flankTime))
                    .font(timeFont).monospacedDigit().foregroundStyle(timeColor)
                track
                Text("-" + Timecode.format(max(0, model.duration - flankTime)))
                    .font(timeFont).monospacedDigit().foregroundStyle(timeColor)
            }
            if buffering {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(Theme.Palette.gold)
                    Text("Loading…").font(.seretCaption).foregroundStyle(Theme.Palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }
        }
        .padding(expanded ? 20 : 0)
        .background {
            // The slab is the scrub-mode surface: up for the whole pause, gone while playing.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.Palette.gold.opacity(0.35), lineWidth: 1)
                )
                .opacity(expanded ? 1 : 0)
        }
        .animation(Theme.Anim.heroSpring, value: expanded)
        .animation(Theme.Anim.focus, value: buffering)
    }

    private var track: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.16)).frame(height: trackHeight)
            GeometryReader { geo in
                let headX = min(geo.size.width, max(0, geo.size.width * headFraction))
                let playheadX = model.duration > 0
                    ? geo.size.width * min(1, max(0, model.position / model.duration))
                    : 0

                Capsule()
                    .fill(Theme.Palette.gold)
                    .frame(width: headX, height: trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)

                // A distinct tick at the LIVE playhead so, while scrubbing, "where you are" (and the
                // return point if you cancel) is always visible — regardless of which way you drag.
                // The old dimmed band was max(origin, target), so scrubbing FORWARD it coincided
                // with the fill and vanished.
                if model.isScrubbing {
                    Capsule()
                        .fill(.white)
                        .frame(width: 3, height: trackHeight + 8)
                        .position(x: min(geo.size.width - 2, max(2, playheadX)),
                                  y: geo.size.height / 2)
                }
                handle
                    .position(x: min(geo.size.width - 10, max(10, headX)), y: geo.size.height / 2)
            }
        }
        .frame(height: 28)
    }

    @ViewBuilder private var handle: some View {
        if model.isScrubbing {
            PlayTriangle()
                .fill(Theme.Palette.goldBright)
                .frame(width: 26, height: 26)
                .overlay(alignment: .bottom) {
                    Text(Timecode.format(model.scrubTarget))
                        .font(.seret(30, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.goldBright)
                        .fixedSize()
                        .offset(y: -38)
                }
        } else if model.phase == .paused {
            // A paused bar used to just stop advancing — with the transport buttons gone there was
            // no pause affordance at rest at all.
            Image(systemName: "pause.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Palette.canvas)
                .frame(width: 22, height: 22)
                .background(Theme.Palette.gold, in: Circle())
        } else {
            Circle().fill(Theme.Palette.gold).frame(width: 14, height: 14)
        }
    }
}
