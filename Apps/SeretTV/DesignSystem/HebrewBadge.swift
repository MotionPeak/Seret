import SwiftUI

/// The gold Hebrew-subtitles mark: on a version row, and larger in a title's hero.
///
/// Gold and filled so it reads before the grey chips around it: whether a version can be watched
/// with Hebrew subtitles is the first thing this household asks of it.
struct HebrewBadge: View {
    let text: String
    /// For "Available": Hebrew exists for the film, but not made for this version.
    var dimmed = false
    var prominent = false

    var body: some View {
        Label(text, systemImage: "captions.bubble.fill")
            .font(.seret(prominent ? .callout : .caption1, .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, prominent ? 16 : 12)
            .padding(.vertical, prominent ? 8 : 5)
            .background(Theme.Palette.gold.opacity(dimmed ? 0.6 : 1), in: Capsule())
    }
}
