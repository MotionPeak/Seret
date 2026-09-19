import DebridCore
import SwiftUI

/// Shows something briefly when a diary entry for this film lands.
///
/// The matching and the timing live here rather than in each player, because there are two players
/// and this is the kind of small duplicated logic that drifts. The look does not: a banner over the
/// picture is styled per platform, as `AutoSyncBar` already is.
private struct LetterboxdLoggedConfirmation<Label: View>: ViewModifier {
    let signal: LetterboxdPushSignal?
    let contentKey: String
    let alignment: Alignment
    @ViewBuilder let label: () -> Label

    @State private var isShowing = false
    /// Cancelled and replaced on each new entry, so a second film logged while the first banner is
    /// still up does not have its banner cut short by the first one's timer.
    @State private var hideTask: Task<Void, Never>?

    private var thisFilm: Int? { LetterboxdContentKey.tmdbID(fromMovieKey: contentKey) }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if isShowing {
                    label().transition(.move(edge: alignment == .bottom ? .bottom : .top)
                        .combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isShowing)
            .onChange(of: signal?.event) { _, _ in
                // Only for the film actually playing. An episode finishing elsewhere, or a queued
                // film draining minutes later, must not congratulate you about this one.
                guard let signal, let thisFilm, signal.lastLogged == thisFilm else { return }
                hideTask?.cancel()
                isShowing = true
                hideTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    isShowing = false
                }
            }
            .onDisappear { hideTask?.cancel() }
    }
}

public extension View {
    /// Confirms a landed Letterboxd diary entry for `contentKey`, for three seconds.
    ///
    /// Nothing is shown for a failed write: it is not actionable while a film is playing, and the
    /// Letterboxd settings card carries it.
    func letterboxdLoggedConfirmation<Label: View>(
        signal: LetterboxdPushSignal?,
        contentKey: String,
        alignment: Alignment = .top,
        @ViewBuilder label: @escaping () -> Label
    ) -> some View {
        modifier(LetterboxdLoggedConfirmation(signal: signal, contentKey: contentKey,
                                              alignment: alignment, label: label))
    }
}
