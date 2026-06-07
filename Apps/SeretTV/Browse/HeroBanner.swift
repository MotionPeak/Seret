import DebridCore
import DebridUI
import SwiftUI

/// Browse tiles publish their hit up to the hero via this preference when focused.
/// The reducer keeps the last non-nil value so the hero holds steady when focus
/// moves onto a non-tile control (the segment pills, the search field).
struct FocusedHitKey: PreferenceKey {
    static let defaultValue: SearchHit? = nil
    static func reduce(value: inout SearchHit?, nextValue: () -> SearchHit?) {
        if let next = nextValue() { value = next }
    }
}

/// A full-bleed backdrop hero pinned above the Browse rails. Crossfades whenever the
/// focused title (`hit`) changes. Search results carry no TMDB backdrop, so the poster
/// art fills the frame as ambient imagery under a strong bottom gradient + gold lockup.
struct HeroBanner: View {
    let hit: SearchHit?
    var height: CGFloat = 480

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: Theme.Palette.canvas.opacity(0.55), location: 0.45),
                .init(color: Theme.Palette.canvas.opacity(0.92), location: 0.8),
                .init(color: Theme.Palette.canvas, location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            if let hit {
                VStack(alignment: .leading, spacing: 12) {
                    Text("סֶרֶט")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.Palette.gold)
                        .environment(\.layoutDirection, .rightToLeft)
                        .goldGlow(14, opacity: 0.5)
                    Text(hit.result.displayTitle)
                        .font(.system(size: 56, weight: .heavy))
                        .foregroundStyle(Theme.Palette.textPrimary).lineLimit(2)
                    if let overview = hit.result.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.title3).foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(2).frame(maxWidth: 1100, alignment: .leading)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 36)
                .transition(.opacity)
                .id(hit.id)   // drive the overlay crossfade on change
            }
        }
        .frame(height: height).frame(maxWidth: .infinity).clipped()
        .animation(.easeInOut(duration: 0.35), value: hit?.id)
    }

    @ViewBuilder private var backdrop: some View {
        AsyncImage(url: TMDBClient.imageURL(path: hit?.result.posterPath, size: "w780")) {
            $0.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(Theme.Palette.surface1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .id(hit?.id)
        .transition(.opacity)
    }
}
