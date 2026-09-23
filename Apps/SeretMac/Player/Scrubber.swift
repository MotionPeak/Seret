import DebridUI
import SwiftUI

/// The pure arithmetic behind a scrub gesture: where an x-offset along a track falls (0...1), and
/// what time that fraction means for a media of a given length.
enum ScrubMath {
    /// Clamped to the track — a drag that overshoots either edge still lands at 0 or 1, and a
    /// zero-width track (not yet laid out) answers 0 rather than dividing by zero.
    static func fraction(x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }

    /// An unknown (zero) duration seeks nowhere — there is nothing to be a fraction OF yet.
    static func time(fraction: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(fraction, 0), 1) * duration
    }
}

/// The transport scrubber: a thin gold-filled track that thickens and grows a knob on hover/drag,
/// and commits a seek only when the drag ends — `model.scrub(to:)` is called once, not on every
/// tick, so ticks never fight the drag.
struct Scrubber: View {
    let position: Double
    let duration: Double
    let onCommit: (Double) -> Void
    @Binding var isDragging: Bool
    /// The time under the drag, for the panel's elapsed label to show instead of the live playhead
    /// while dragging. nil outside a drag.
    @Binding var previewTime: Double?

    @State private var dragFraction: Double?
    @State private var hovering = false

    private var fraction: Double {
        if let dragFraction { return dragFraction }
        return duration > 0 ? min(max(position / duration, 0), 1) : 0
    }

    private var active: Bool { hovering || isDragging }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Theme.Palette.gold)
                    .frame(width: geo.size.width * fraction)
                    .goldGlow(active ? 8 : 0, opacity: 0.5)
                if active {
                    Circle()
                        .fill(Theme.Palette.textPrimary)
                        .frame(width: 13, height: 13)
                        .offset(x: geo.size.width * fraction - 6.5)
                }
            }
            .frame(height: active ? 7.5 : 4.5)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let f = ScrubMath.fraction(x: value.location.x, width: geo.size.width)
                        dragFraction = f
                        previewTime = ScrubMath.time(fraction: f, duration: duration)
                    }
                    .onEnded { value in
                        let landed = ScrubMath.fraction(x: value.location.x, width: geo.size.width)
                        onCommit(ScrubMath.time(fraction: landed, duration: duration))
                        dragFraction = nil
                        previewTime = nil
                        isDragging = false
                    }
            )
            .onHover { hovering = $0 }
        }
        .frame(height: 13)
        .animation(Theme.Motion.quick, value: active)
    }
}
