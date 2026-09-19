import SwiftUI

/// Shows something briefly when a watchlist change for this film settles.
///
/// The matching and the timing live here rather than on each title page, because there are two of
/// them and this is the kind of small duplicated logic that drifts. The look does not: the label is
/// the caller's, styled per platform, exactly as `LetterboxdLoggedConfirmation` is.
///
/// Unlike the diary confirmation this shows failures too. A diary entry fails while a film is
/// playing, where interrupting is worse than silence; a watchlist change is something the owner just
/// asked for and is waiting on, and "nothing happened" is the one answer a button must never give.
private struct WatchlistChangeConfirmation<Label: View>: ViewModifier {
    let outcome: WatchlistMarks.Outcome?
    /// The film this page is about. Nil on a show, where there is nothing to announce.
    let tmdbID: Int?
    let alignment: Alignment
    @ViewBuilder let label: (WatchlistMarks.Outcome) -> Label

    @State private var shown: WatchlistMarks.Outcome?
    /// Cancelled and replaced on each change, so a second change while the first banner is still up
    /// does not have its banner cut short by the first one's timer.
    @State private var hideTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if let shown {
                    label(shown)
                        .transition(.move(edge: alignment == .bottom ? .bottom : .top)
                            .combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: shown)
            .onChange(of: outcome?.event) { _, _ in
                // Only for the film this page is about. A tile's change elsewhere, or a queued push
                // draining minutes later, must not report itself here.
                guard let outcome, let tmdbID, outcome.tmdbID == tmdbID else { return }
                hideTask?.cancel()
                shown = outcome
                hideTask = Task {
                    // A failure is a sentence to read, not a tick to notice.
                    try? await Task.sleep(for: .seconds(outcome.isFailure ? 5 : 3))
                    guard !Task.isCancelled else { return }
                    shown = nil
                }
            }
            .onDisappear { hideTask?.cancel() }
    }
}

public extension View {
    /// Reports a settled watchlist change for `tmdbID`, briefly.
    ///
    /// Shows failures as well as successes: the owner pressed a button and is waiting to hear.
    func watchlistChangeConfirmation<Label: View>(
        marks: WatchlistMarks?,
        tmdbID: Int?,
        alignment: Alignment = .top,
        @ViewBuilder label: @escaping (WatchlistMarks.Outcome) -> Label
    ) -> some View {
        modifier(WatchlistChangeConfirmation(outcome: marks?.lastOutcome, tmdbID: tmdbID,
                                             alignment: alignment, label: label))
    }
}
