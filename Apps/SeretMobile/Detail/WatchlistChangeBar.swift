import DebridUI
import SwiftUI

/// Says what became of a watchlist change, over the top of the title page.
///
/// Carries failures as well as successes — the owner tapped a control and is waiting to hear — with
/// the glyph and its colour doing the work of saying which.
struct WatchlistChangeBar: View {
    let outcome: WatchlistMarks.Outcome

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: glyph)
                .foregroundStyle(outcome.isFailure ? .orange : Theme.Palette.gold)
            Text(outcome.message)
                .font(Theme.Typo.body())
                .foregroundStyle(.white)
                // A failure is a sentence, and a sentence that is clipped to one line is a sentence
                // the owner cannot act on.
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.md).padding(.vertical, Theme.Space.sm)
        .background(.black.opacity(0.8), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .padding(.horizontal, Theme.Space.md)
        // Clear of the toolbar this page already carries.
        .padding(.top, Theme.Space.xl)
        .shadow(radius: 12, y: 4)
    }

    private var glyph: String {
        if outcome.isFailure { return "exclamationmark.triangle.fill" }
        return outcome.added ? "bookmark.fill" : "bookmark.slash.fill"
    }
}
