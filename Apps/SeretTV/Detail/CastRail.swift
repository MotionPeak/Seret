import DebridCore
import SwiftUI

/// A horizontal rail of circular cast headshots with name + character, shown at the bottom of the
/// Movie/Show Detail page.
///
/// Each card is ONE stable `NavigationLink` whose value is the person — never a branch of two
/// links. A branch swap under focus destroys the focused view and tvOS silently drops focus
/// elsewhere; that is what once made a click open the search keyboard instead of the title.
///
/// The cards being focusable is also what makes the rail scrollable at all. They used not to be,
/// so the d-pad walked straight past and the row could never move — which read as "the cast list
/// doesn't scroll" rather than "the cast list can't be reached".
///
/// The caller gates this view on a non-empty cast, so the rail never renders as an empty row that
/// collapses to ~0 height and back (the documented scroll-snap trap). Every headshot frame is held
/// by a placeholder while its image loads, so the row's height is fixed from first layout.
struct CastRail: View {
    let cast: [TMDBCastMember]

    private let headshot: CGFloat = 180
    private let itemWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cast").sectionTitle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 36) {
                    ForEach(cast) { member in
                        NavigationLink(value: BrowseDestination.person(
                            TMDBPersonRef(id: member.id, name: member.name))) {
                            card(for: member)
                        }
                        .buttonStyle(CastCardStyle())
                    }
                }
                .padding(.horizontal, Theme.Layout.contentMargin)
                .padding(.vertical, 12)   // headroom so the focus scale isn't clipped top/bottom
            }
            // Runs edge-to-edge (negating the page's 60pt inset) so nothing clips at the row edges.
            .padding(.horizontal, -Theme.Layout.contentMargin)
        }
        // Widen to the page BEFORE sectioning — a section only counts when its frame intersects
        // the direction of travel, so a narrow one leaves the columns above and below it with
        // nothing to travel into.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .task {
            ImageMemoryCache.prefetch(
                cast.compactMap { TMDBClient.imageURL(path: $0.profilePath, size: "h632") })
        }
    }

    private func card(for member: TMDBCastMember) -> some View {
        VStack(spacing: 12) {
            RemoteImage(url: TMDBClient.imageURL(path: member.profilePath, size: "h632")) {
                Theme.Palette.surface2.overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
            .frame(width: headshot, height: headshot)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1) }

            Text(member.name)
                .font(.seret(Theme.Typography.captionSize, .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            if let character = member.character, !character.isEmpty {
                Text(character)
                    .font(.seret(Theme.Typography.captionSize, .regular))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: itemWidth, alignment: .top)
    }
}

/// Focus treatment for a cast card: lift and brighten, no plate.
///
/// `.card` was the obvious choice and is wrong here — it draws a rectangular platter behind a
/// circular headshot. This follows the same shape as every other style in the design system: a
/// nested view reading `\.isFocused`, since `ButtonStyleConfiguration` does not carry focus.
private struct CastCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Card(configuration: configuration)
    }

    private struct Card: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused: Bool
        var body: some View {
            configuration.label
                .scaleEffect(focused ? 1.08 : 1)
                .brightness(focused ? 0.08 : 0)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

#Preview {
    // A NavigationStack is required: the cards are links now.
    NavigationStack {
        CastRail(cast: [
            TMDBCastMember(id: 1, name: "Timothée Chalamet", character: "Paul Atreides",
                           profilePath: nil, order: 0),
            TMDBCastMember(id: 2, name: "Zendaya", character: "Chani", profilePath: nil, order: 1),
            TMDBCastMember(id: 3, name: "Rebecca Ferguson", character: "Lady Jessica",
                           profilePath: nil, order: 2),
        ])
        .padding(60)
        .background(CanvasBackground())
    }
}
