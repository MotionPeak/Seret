import DebridCore
import SwiftUI

/// A horizontal rail of circular cast headshots with name + character, shown at the bottom of the
/// Movie/Show Detail page.
///
/// Informational only — the cards are deliberately NOT focusable (cast isn't tappable in this
/// slice), so the d-pad travels straight past the rail instead of into it. That also means the rail
/// can't trap focus, and there's no `.focusSection()` (pointless without focusable children).
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
                        card(for: member)
                    }
                }
                .padding(.horizontal, Theme.Layout.contentMargin)
            }
            // Runs edge-to-edge (negating the page's 60pt inset) so nothing clips at the row edges.
            .padding(.horizontal, -Theme.Layout.contentMargin)
        }
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

#Preview {
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
