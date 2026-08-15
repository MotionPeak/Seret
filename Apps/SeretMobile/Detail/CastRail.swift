import DebridCore
import SwiftUI

/// A horizontal rail of circular cast headshots with name + character, shown on Movie/Show Detail.
///
/// A tap opens that person's page — pushed onto the navigation stack Detail owns, so it arrives
/// with a back button rather than stacking a second cover the shell would ignore.
///
/// The caller gates the rail on a non-empty cast, and every headshot frame is held by a placeholder
/// while its image loads, so the row's height is fixed from first layout and the page never
/// re-lays-out under the reader.
struct CastRail: View {
    let cast: [TMDBCastMember]

    private let headshot: CGFloat = 72
    private let itemWidth: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("CAST").font(Theme.Typo.label()).tracking(1.5).foregroundStyle(Theme.Palette.gold)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Space.lg) {
                    ForEach(cast) { member in
                        NavigationLink {
                            PersonScreen(ref: TMDBPersonRef(id: member.id, name: member.name))
                        } label: {
                            card(for: member)
                        }
                        // Keeps the headshot and its labels rendering as themselves rather than
                        // picking up link tinting.
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task {
            ImageMemoryCache.prefetch(
                cast.compactMap { TMDBClient.imageURL(path: $0.profilePath, size: "w185") })
        }
    }

    private func card(for member: TMDBCastMember) -> some View {
        VStack(spacing: Theme.Space.xs) {
            RemoteImage(url: TMDBClient.imageURL(path: member.profilePath, size: "w185")) {
                Theme.Palette.surface2.overlay {
                    Image(systemName: "person.fill").foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .frame(width: headshot, height: headshot)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1) }

            Text(member.name)
                .font(Theme.Typo.label())
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
            if let character = member.character, !character.isEmpty {
                Text(character)
                    .font(Theme.Typo.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: itemWidth, alignment: .top)
    }
}
