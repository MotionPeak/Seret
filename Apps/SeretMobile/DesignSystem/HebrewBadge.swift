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
            .labelStyle(.titleAndIcon)
            .font(.system(size: prominent ? 13 : 11, weight: .bold))
            .foregroundStyle(.black)
            .padding(.vertical, prominent ? 5 : 4)
            .padding(.horizontal, prominent ? 10 : 8)
            .background(Theme.Palette.gold.opacity(dimmed ? 0.6 : 1),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}
