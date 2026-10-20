import DebridUI
import SwiftUI

/// Says what became of a watchlist change, over the top of the title page.
///
/// The same capsule as `LetterboxdLoggedBar`, because they are the same kind of statement — except
/// this one also carries failures: a warning triangle in place of the bookmark, and the palette's
/// error red, as the Watchlist page and the Letterboxd card already say a sync failure. A change
/// that went through stays white.
struct WatchlistChangeBar: View {
    let outcome: WatchlistMarks.Outcome

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: glyph)
                .font(.system(size: 26, weight: .semibold))
            Text(outcome.message)
                .font(.seret(24, .semibold))
        }
        .foregroundStyle(outcome.isFailure ? Theme.Palette.destructive : Theme.Palette.textPrimary)
        .padding(.horizontal, 34).padding(.vertical, 20)
        .playerOverlaySurface(Capsule())
        // The same inset AutoSyncBar uses, so this clears the edge a real television overscans.
        .padding(.top, 50)
    }

    private var glyph: String {
        if outcome.isFailure { return "exclamationmark.triangle.fill" }
        return outcome.added ? "bookmark.fill" : "bookmark.slash.fill"
    }
}
