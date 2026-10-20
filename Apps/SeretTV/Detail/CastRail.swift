import DebridCore
import DebridUI
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
    @Environment(\.displayScale) private var displayScale

    private let headshot: CGFloat = 180
    private let itemWidth: CGFloat = 220

    var body: some View {
        // Lazy, like every rail in the app (`PlexRail`). Uniform tiles and no skeleton/real branch
        // inside, so it cannot hit the id-collision trap that leaves stale unfocusable cells behind.
        PlexRail(title: "Cast", id: "detail-cast") {
            ForEach(cast) { member in
                NavigationLink(value: BrowseDestination.person(
                    TMDBPersonRef(id: member.id, name: member.name))) {
                    CastCard(member: member, headshot: headshot, width: itemWidth)
                }
                .buttonStyle(BareButtonStyle())
            }
        }
        .task {
            // At the size the cards decode for — see `CastCard`.
            ImageMemoryCache.prefetch(
                cast.compactMap { TMDBClient.imageURL(path: $0.profilePath, size: "h632") },
                target: ImageDownsampling.targetPixels(points: CastCard.decodeSize(headshot), scale: displayScale))
        }
    }
}

/// One cast member: a circular headshot that takes the card focus look (a white ring just outside
/// the circle, the 1.08 lift, the soft shadow) while the card has focus, with the name and the
/// character under it.
///
/// `FocusCardStyle` itself would draw a rounded-rectangle ring around the whole card, words and
/// all; this keeps the ring circular and on the face. Focus is read from the enclosing link, as
/// `\.isFocused` reports for any view inside the focused one.
private struct CastCard: View {
    let member: TMDBCastMember
    let headshot: CGFloat
    let width: CGFloat

    @Environment(\.isFocused) private var focused

    /// The headshot's decoded size: the focused (lifted) circle.
    static func decodeSize(_ headshot: CGFloat) -> CGSize {
        CGSize(width: headshot * Theme.Anim.focusScale, height: headshot * Theme.Anim.focusScale)
    }

    /// Ring width, drawn entirely outside the circle — as `FocusCardStyle` draws it.
    private let ring: CGFloat = 4

    var body: some View {
        VStack(spacing: 14) {
            // The glyph is right whether the headshot is still loading or never arrives.
            RemoteImage(url: TMDBClient.imageURL(path: member.profilePath, size: "h632"),
                        decodeSize: Self.decodeSize(headshot)) { _ in
                Theme.Palette.surface2.overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Theme.Palette.textSecondary.opacity(0.45))
                }
            }
            .frame(width: headshot, height: headshot)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
            .overlay {
                Circle()
                    .strokeBorder(Theme.Palette.focus, lineWidth: ring)
                    .padding(-ring)
                    .opacity(focused ? 1 : 0)
            }
            .liftShadow(focused)
            .scaleEffect(focused ? Theme.Anim.focusScale : 1, anchor: .bottom)

            VStack(spacing: 4) {
                Text(member.name)
                    .font(.seret(Theme.Typography.captionSize, .semibold))
                    .foregroundStyle(focused ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                // Always laid out — a space when there is no character, since an empty string
                // reserves no line — so every card is the same height and the row lines up.
                Text(member.character.flatMap { $0.isEmpty ? nil : $0 } ?? " ")
                    .font(.seret(Theme.Typography.captionSize, .regular))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1, reservesSpace: true)
            }
            .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .frame(width: width, alignment: .top)
        .animation(Theme.Anim.focus, value: focused)
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
