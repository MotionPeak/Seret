import DebridCore
import DebridUI
import SwiftUI

/// The viewer's own 1–10 Trakt rating, as a focusable row of stars. Distinct from `RatingsRow`,
/// which shows the aggregate public scores (IMDb / Rotten Tomatoes / Metacritic). Hidden entirely
/// when Trakt isn't linked, so an unlinked Apple TV sees no dead control.
struct UserRatingRow: View {
    let store: DetailStore

    var body: some View {
        if store.canRate {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Text("YOUR RATING")
                        .font(.caption.weight(.semibold)).kerning(1.5)
                        .foregroundStyle(Theme.Palette.gold)
                    if let rating = store.userRating {
                        Text("\(rating)/10")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                // `.focusSection()` makes this row ONE wider target for the focus engine — it does
                // NOT trap focus inside the row. A section only counts if its FRAME intersects the
                // direction of travel, so the row is widened to the full page FIRST: the stars end
                // mid-screen, and without the full-width frame anything sitting to their right
                // (the "Find Other Versions" button) had nothing above it and UP was a dead press.
                HStack(spacing: 18) {
                    ForEach(1...10, id: \.self) { value in
                        Button {
                            Task { await store.rate(store.userRating == value ? nil : value) }
                        } label: {
                            Image(systemName: (store.userRating ?? 0) >= value ? "star.fill" : "star")
                                .font(.title2)
                                .padding(6)
                        }
                        .buttonStyle(StarButtonStyle(filled: (store.userRating ?? 0) >= value))
                        .accessibilityLabel("Rate \(value) out of 10")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
                Text("Select your current rating again to clear it.")
                    .font(.caption).foregroundStyle(Theme.Palette.textSecondary)
            }
            .task { await store.loadUserRating() }
        }
    }
}

/// A chrome-free star. `.card` (the old style) drew tvOS's grey rounded platter behind every star,
/// so the row read as ten grey boxes instead of a rating; a custom `ButtonStyle` is the only way to
/// suppress that platter (see `BareButtonStyle`). The star supplies its own focus cue instead —
/// gold tint, scale and glow, matching the rest of the Gold Glass controls.
private struct StarButtonStyle: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        Render(configuration: configuration, filled: filled)
    }

    private struct Render: View {
        let configuration: ButtonStyleConfiguration
        let filled: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(filled || focused
                                 ? AnyShapeStyle(Theme.Palette.gold)
                                 : AnyShapeStyle(Theme.Palette.textSecondary))
                .scaleEffect(focused ? 1.35 : 1)
                .goldGlow(focused ? 16 : 0, opacity: 0.45)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .animation(Theme.Anim.focus, value: focused)
        }
    }
}
