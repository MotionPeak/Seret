import DebridCore
import SwiftUI

/// The hero's title artwork — TMDB's own logo when there is one, the plain text title otherwise.
/// The text IS the placeholder, so loading, a missing path and a decode failure all read the
/// same correct way rather than a blank gap.
struct TitleLogo: View {
    let path: String?
    let title: String

    var body: some View {
        RemoteImage(url: path.flatMap { TMDBClient.imageURL(path: $0, size: "w500") }, contentMode: .fit) {
            textFallback
        }
        .frame(maxWidth: 440, maxHeight: 140, alignment: .leading)
        .shadow(color: .black.opacity(0.55), radius: 10, y: 3)
    }

    private var textFallback: some View {
        Text(title)
            .font(.system(size: 38, weight: .heavy))
            .foregroundStyle(Theme.Palette.textPrimary)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
    }
}
