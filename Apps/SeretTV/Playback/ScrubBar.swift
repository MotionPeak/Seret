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

    private var shownTime: Double { model.isScrubbing ? model.scrubTarget : model.position }
    private var fraction: Double {
        model.duration > 0 ? min(1, max(0, shownTime / model.duration)) : 0
    }
    private var trackHeight: CGFloat { model.isScrubbing ? 8 : 3 }
    private var timeFont: Font {
        .system(size: model.isScrubbing ? 24 : 20, weight: .semibold)
    }
    private var timeColor: Color {
        model.isScrubbing ? Theme.Palette.textPrimary : Theme.Palette.textSecondary
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                Text(Timecode.format(shownTime))
                    .font(timeFont).monospacedDigit().foregroundStyle(timeColor)
                track
                Text("-" + Timecode.format(max(0, model.duration - shownTime)))
                    .font(timeFont).monospacedDigit().foregroundStyle(timeColor)
            }
            if buffering {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(Theme.Palette.gold)
                    Text("Loading…").font(.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }
        }
        .padding(model.isScrubbing ? 20 : 0)
        .background {
            // The slab exists only while scrubbing — at rest the bar floats on the picture.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.Palette.gold.opacity(0.35), lineWidth: 1)
                )
                .opacity(model.isScrubbing ? 1 : 0)
        }
        .animation(Theme.Anim.heroSpring, value: model.isScrubbing)
        .animation(Theme.Anim.focus, value: buffering)
    }

    private var track: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.16)).frame(height: trackHeight)
            GeometryReader { geo in
                let headX = min(geo.size.width, max(0, geo.size.width * fraction))
                let originX = model.duration > 0
                    ? geo.size.width * min(1, max(0, model.position / model.duration))
                    : 0

                // Where the playhead was when the scrub started — so the viewer can see how far
                // they have travelled, and Menu-to-cancel has a visible meaning.
                if model.isScrubbing {
                    Capsule()
                        .fill(Theme.Palette.gold.opacity(0.30))
                        .frame(width: max(originX, headX), height: trackHeight)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                Capsule()
                    .fill(Theme.Palette.gold)
                    .frame(width: headX, height: trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)
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
                        .font(.system(size: 30, weight: .semibold))
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
