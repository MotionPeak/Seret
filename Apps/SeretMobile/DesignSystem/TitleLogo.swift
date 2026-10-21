import DebridCore
import SwiftUI

/// A title's logo art (TMDB's "logos"), or its name as type when there is none — the Apple TV's
/// `DetailTitleArt`, sized for a phone.
///
/// While the details are still loading (`settling`) the slot is held empty for at most
/// `budget`, so a name does not flash up only to be replaced by its logo a beat later. Past the
/// budget the name shows, and a late logo cross-fades in over it — an empty title block is worse
/// than a name that turns into its logo.
struct TitleLogo: View {
    let title: String
    let logoPath: String?
    let settling: Bool
    var maxWidth: CGFloat = 280
    var maxHeight: CGFloat = 96
    var alignment: Alignment = .bottom
    var font: Font = .system(size: 38, weight: .heavy)

    static let budget: Duration = .milliseconds(1_200)

    /// The last logo decoded here, kept across a `.task(id:)` re-run for the SAME url so coming
    /// back to the page does not flash the name up again.
    @State private var loaded: (url: URL, image: UIImage)?
    @State private var budgetSpent = false

    var body: some View {
        let url = TMDBClient.imageURL(path: logoPath, size: "w500")
        let image = url.flatMap { ImageMemoryCache.shared.object(forKey: $0 as NSURL) }
            ?? (loaded?.url == url ? loaded?.image : nil)
        ZStack(alignment: alignment) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: alignment)
                    // Light logos over light art: a soft shadow is what keeps them legible.
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
                    .transition(.opacity)
            } else if !budgetSpent && (settling || url != nil) {
                Color.clear
            } else {
                // Never forced left-to-right: a Hebrew title lays out right-to-left in its line.
                Text(title)
                    .font(font)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(alignment == .bottomLeading ? .leading : .center)
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
                    .frame(maxWidth: maxWidth, alignment: alignment)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: maxWidth, minHeight: maxHeight, maxHeight: maxHeight, alignment: alignment)
        .animation(Theme.Motion.fade, value: image != nil)
        .animation(Theme.Motion.fade, value: budgetSpent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
        .task(id: url) {
            guard let url, loaded?.url != url else { return }
            if let cached = ImageMemoryCache.shared.object(forKey: url as NSURL) {
                loaded = (url, cached)
                return
            }
            guard let image = await ImageMemoryCache.load(url), !Task.isCancelled else { return }
            loaded = (url, image)
        }
        .task(id: title) {
            budgetSpent = false
            try? await Task.sleep(for: Self.budget)
            guard !Task.isCancelled else { return }
            budgetSpent = true
        }
    }
}
