#if DEBUG
import SwiftUI

/// Every design-system style on one page, for screenshot verification: posters in
/// `FocusCardStyle`, a row of `ExpandingIconButtonStyle` actions after a primary pill, the pills,
/// `ProgressLine`, the Hebrew marks and the brand mark. `-uiPreview styles` lands focus on the
/// Trailer button (so one expanded button sits among resting circles); `-uiPreview stylescard`
/// lands it on the second poster.
struct StyleGalleryPreview: View {
    enum Spot: Hashable { case play, trailer, watchlist, watched, more, poster(Int), pill(Int) }

    let initialFocus: Spot
    @FocusState private var focus: Spot?

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(alignment: .leading, spacing: 44) {
                Text("Style gallery").sectionTitle().foregroundStyle(Theme.Palette.textPrimary)
                actionRow
                HStack(spacing: 18) {
                    ForEach(0..<4, id: \.self) { i in
                        Button(["All", "Drama", "Comedy", "Thriller"][i]) {}
                            .buttonStyle(SeretPillStyle(selected: i == 1))
                            .focused($focus, equals: .pill(i))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
                posters
                HStack(spacing: 30) {
                    HebrewBadge(.inFile, prominent: true)
                    HebrewBadge(.matched)
                    HebrewBadge(.available)
                    SeretMark().frame(width: 60)
                    AvatarCircle(token: "🍿", diameter: 60, colorTag: Theme.Palette.defaultColorTag)
                    AvatarCircle(token: "🦊", diameter: 60, colorTag: "blue")
                    ProgressView().tint(Theme.Palette.textPrimary)
                }
            }
            .padding(80)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .defaultFocus($focus, initialFocus)
    }

    private var actionRow: some View {
        HStack(spacing: 22) {
            Button {} label: { Label("Resume", systemImage: "play.fill") }
                .buttonStyle(PrimaryPillButtonStyle())
                .focused($focus, equals: .play)
            Button {} label: { Label("Trailer", systemImage: "play.rectangle") }
                .buttonStyle(ExpandingIconButtonStyle())
                .focused($focus, equals: .trailer)
            Button {} label: { Label("Watchlist", systemImage: "bookmark") }
                .buttonStyle(ExpandingIconButtonStyle())
                .focused($focus, equals: .watchlist)
            Button {} label: { Label("Mark Watched", systemImage: "checkmark") }
                .buttonStyle(ExpandingIconButtonStyle())
                .focused($focus, equals: .watched)
            Button {} label: { Label("More", systemImage: "ellipsis") }
                .buttonStyle(ExpandingIconButtonStyle())
                .focused($focus, equals: .more)
            Button("Remove", role: .destructive) {}
                .buttonStyle(SeretActionButtonStyle(destructive: true))
            Button("Versions") {}
                .buttonStyle(SeretActionButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private var posters: some View {
        HStack(spacing: 40) {
            ForEach(0..<4, id: \.self) { i in
                Button {} label: {
                    ZStack(alignment: .bottom) {
                        LinearGradient(colors: [Theme.Palette.surface2, Theme.Palette.surface1],
                                       startPoint: .top, endPoint: .bottom)
                        Text("Poster \(i + 1)").cardTitle()
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(maxHeight: .infinity)
                        ProgressLine(fraction: [0.2, 0.55, 0.9, 1][i])
                            .padding(.horizontal, 12).padding(.bottom, 12)
                    }
                    .frame(width: 160, height: 240)
                }
                .buttonStyle(FocusCardStyle())
                .focused($focus, equals: .poster(i))
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}
#endif
