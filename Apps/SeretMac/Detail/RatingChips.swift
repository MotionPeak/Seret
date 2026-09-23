import DebridUI
import SwiftUI

/// The hero's public-score chips: IMDb, Rotten Tomatoes and Metacritic (from OMDb, both kinds),
/// then Letterboxd (films only). Each source shimmers independently while its own load is in
/// flight, so a slow Letterboxd page never holds the OMDb chips off screen.
struct RatingChips: View {
    let store: DetailStore

    var body: some View {
        HStack(spacing: 6) {
            omdbChips
            if store.item.kind == .movie { letterboxdChip }
        }
    }

    @ViewBuilder private var omdbChips: some View {
        if store.ratingsState == .loading {
            ShimmerView(cornerRadius: 8).frame(width: 58, height: 22)
            ShimmerView(cornerRadius: 8).frame(width: 58, height: 22)
            ShimmerView(cornerRadius: 8).frame(width: 58, height: 22)
        } else {
            if let v = store.ratings?.imdb { ImdbChip(text: TitlePageText.imdb(v)) }
            if let v = store.ratings?.rottenTomatoes { RottenTomatoesChip(text: TitlePageText.rottenTomatoes(v)) }
            if let v = store.ratings?.metacritic { MetacriticChip(score: v) }
        }
    }

    @ViewBuilder private var letterboxdChip: some View {
        if store.letterboxdState == .loading {
            ShimmerView(cornerRadius: 8).frame(width: 50, height: 22)
        } else if let rating = store.letterboxdRating {
            RatingChipShell {
                LetterboxdMark(diameter: 12)
                Text(TitlePageText.letterboxd(rating.score))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
    }
}

/// The chip frame every rating pill shares: 8 pt corners, the standard chip fill.
private struct RatingChipShell<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 4) { content() }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.Palette.chipFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ImdbChip: View {
    let text: String

    var body: some View {
        RatingChipShell {
            Text("IMDb")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.black)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color(hex: 0xF5C518), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }
}

private struct RottenTomatoesChip: View {
    let text: String

    var body: some View {
        RatingChipShell {
            Text("\u{1F345}")
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }
}

private struct MetacriticChip: View {
    let score: Int

    private var band: TitlePageText.MetacriticBand { TitlePageText.metacriticBand(score) }
    private var colour: Color {
        switch band {
        case .good: Theme.Palette.ratingGood
        case .mixed: Theme.Palette.ratingMid
        case .bad: Theme.Palette.ratingBad
        }
    }

    var body: some View {
        RatingChipShell {
            Text("\(score)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: 18, height: 18)
                .background(colour, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text("Metacritic")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }
}
