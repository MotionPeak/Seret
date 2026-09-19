import DebridUI
import SwiftUI

/// Says what became of a watchlist change, over the top of the title page.
///
/// The same capsule as `LetterboxdLoggedBar`, because they are the same kind of statement — except
/// this one also carries failures, so the glyph and its colour do the work of saying which.
struct WatchlistChangeBar: View {
    let outcome: WatchlistMarks.Outcome

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: glyph)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(outcome.isFailure ? .orange : Theme.Palette.gold)
            Text(outcome.message)
                .font(.seret(24, .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 34).padding(.vertical, 20)
        .background(.black.opacity(0.66), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        // The same inset AutoSyncBar uses, so this clears the edge a real television overscans.
        .padding(.top, 50)
    }

    private var glyph: String {
        if outcome.isFailure { return "exclamationmark.triangle.fill" }
        return outcome.added ? "bookmark.fill" : "bookmark.slash.fill"
    }
}
