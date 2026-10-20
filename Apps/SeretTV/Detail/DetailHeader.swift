import DebridCore
import DebridUI
import SwiftUI
import UIKit

/// The title page's frame, Plex-style: the title block (logo, metadata, overview, actions) on the
/// left over the backdrop, the rails below it.
enum DetailLayout {
    /// The title block's and the lists' leading inset — the page's overscan-safe margin.
    static let inset: CGFloat = Theme.Layout.contentMargin
    /// Rails sit this far in and add `FocusBrowseLayout.leadingInset` of their own, so their first
    /// tile lines up with the title block: 30 + 30 = 60.
    static let railInset: CGFloat = Theme.Layout.contentMargin - FocusBrowseLayout.leadingInset
    /// The title block starts this far below the safe area, so more of the art shows above it.
    static let topPadding: CGFloat = 70
    /// Width of the text in the title block: the overview, the logo's fallback title.
    static let textWidth: CGFloat = 1000
    /// The logo slot. Fixed, so the logo landing (or the title standing in for it) never moves the
    /// rows below — the action row focus was just placed on above all.
    static let logoHeight: CGFloat = 170
    /// How long the logo slot may stay empty while the details (and so the logo) are on their way,
    /// before the title is printed instead. A logo that lands later fades in over the title.
    static let logoBudget: Duration = .milliseconds(500)
    /// Past this much scroll the viewer is in the rails: the trailer pauses and the art dims.
    static let scrolledAwayOffset: CGFloat = 320
}

/// The title's logo art, or its name until (or unless) the logo can be drawn.
///
/// `settling` (the details are still loading) holds the slot empty for at most `logoBudget`, so a
/// title does not flash up only to be replaced by its logo a beat later. Past the budget the title
/// shows as text and a late logo cross-fades in over it — an empty title block is worse than a
/// title that turns into its logo.
struct DetailTitleArt: View {
    let title: String
    let logoPath: String?
    let settling: Bool

    @State private var loaded: UIImage?
    @State private var budgetSpent = false

    var body: some View {
        let url = TMDBClient.imageURL(path: logoPath, size: "w500")
        let image = url.flatMap { ImageMemoryCache.shared.object(forKey: $0 as NSURL) } ?? loaded
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 640, maxHeight: DetailLayout.logoHeight, alignment: .bottomLeading)
                    .transition(.opacity)
            } else if !budgetSpent && (settling || url != nil) {
                Color.clear
            } else {
                // Leading-aligned and never forced left-to-right: a Hebrew title lays out
                // right-to-left within its line, as it should.
                Text(title)
                    .screenTitle()
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                    .frame(width: DetailLayout.textWidth, alignment: .bottomLeading)
                    .transition(.opacity)
            }
        }
        .frame(height: DetailLayout.logoHeight, alignment: .bottomLeading)
        .animation(Theme.Anim.imageFade, value: image != nil)
        .animation(Theme.Anim.imageFade, value: budgetSpent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
        .task(id: url) {
            loaded = nil
            guard let url else { return }
            let image = await ImageMemoryCache.load(url)
            // A cancelled load belongs to a url this view no longer shows.
            guard !Task.isCancelled else { return }
            loaded = image
        }
        .task {
            try? await Task.sleep(for: DetailLayout.logoBudget)
            budgetSpent = true
        }
    }
}

/// The metadata row under the logo: year · runtime or seasons · ★ · language · genres, then the
/// public scores (IMDb, Rotten Tomatoes, Metacritic, Letterboxd) as chips on the same line.
///
/// It holds the chips' height from the first frame, so the scores landing a round-trip after the
/// details never push the overview and the action row down.
struct DetailMetaRow: View {
    let items: [String]
    var ratings: OMDbRatings?
    var letterboxd: LetterboxdFilmRating?

    /// A chip's height, reserved whether or not any chip has arrived yet.
    private static let height: CGFloat = 42

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Array(items.enumerated()), id: \.offset) { Text($0.element) }
            RatingsRow(ratings: ratings, letterboxd: letterboxd)
                .padding(.leading, items.isEmpty ? 0 : 6)
        }
        .font(.seret(25, .medium))
        .foregroundStyle(Theme.Palette.textPrimary.opacity(0.9))
        .lineLimit(1)
        .frame(minHeight: Self.height, alignment: .leading)
    }

    /// The row's text items, in order. Anything unknown is simply left out.
    static func items(year: Int?, runtime: Int?, seasons: Int?, vote: Double?, language: String?,
                      genres: [String]) -> [String] {
        var items: [String] = []
        if let year { items.append(String(year)) }
        if let runtime, runtime > 0 { items.append(PreviewMeta.duration(runtime)) }
        if let seasons, seasons > 0 { items.append(seasons == 1 ? "1 Season" : "\(seasons) Seasons") }
        if let vote, vote > 0 { items.append("★ " + vote.formatted(rating)) }
        if let language { items.append(language) }
        items.append(contentsOf: genres.prefix(3))
        return items
    }

    /// One decimal, always with a point ("8.4", never "8,4" under a comma-decimal region).
    private static let rating = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(1))
        .locale(Locale(identifier: "en_US_POSIX"))
}
