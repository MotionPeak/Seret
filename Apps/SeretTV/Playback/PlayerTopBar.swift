import SwiftUI
import DebridUI

/// The player's top chrome, shown together with the scrub bar: what is playing, top-left, and the
/// time of day, top-right, over a soft gradient so both read over a bright frame.
///
/// Built from nothing focusable and never hit-testable. The remote belongs to
/// `PlayerInputSurface`, which only works because it has no focusable siblings at rest.
struct PlayerTopBar: View {
    let title: String
    let subtitle: String
    /// Off while the side sheet covers the top-right corner — the clock would show through it.
    var showsClock: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.seret(46, .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.seret(24, .medium))
                        .foregroundStyle(Theme.Palette.textPrimary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // Ticks once a minute, which is all a clock without seconds needs.
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.seret(30, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .opacity(showsClock ? 1 : 0)
            .animation(Theme.Anim.pageFade, value: showsClock)
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        .padding(.horizontal, PlayerLayout.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

/// Shared player geometry.
enum PlayerLayout {
    /// The chrome's side inset INSIDE the safe area — the bar, the top line and the control row all
    /// start here, so their left edges line up.
    static let sideInset: CGFloat = 20
    /// Where the bars that sit at the top of the picture (subtitle sync, the Letterboxd prompt and
    /// confirmation) start, measured from the top of the safe area. Below the title block of
    /// `PlayerTopBar`, so the two never overlap whichever of them comes up first.
    static let topSlotInset: CGFloat = 130
}
