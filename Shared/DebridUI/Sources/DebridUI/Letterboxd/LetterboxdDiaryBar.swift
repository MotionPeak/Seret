import DebridCore
import SwiftUI

/// What the diary bar is saying about this film, if anything.
public enum LetterboxdDiaryBar: Equatable, Sendable {
    /// The entry is queued and held, waiting on a rating. `current` is what the film is already
    /// rated, so a rewatch starts from that rather than blank.
    case askingRating(tmdbID: Int, current: Int?)
    /// The entry landed.
    case logged
}

/// Shows the diary bar for the film being played: first asking for a rating, then confirming.
///
/// The matching and the timing live here rather than in each player, because there are two players
/// and this is the kind of small duplicated logic that drifts. The look does not: a bar over the
/// picture is styled per platform, as `AutoSyncBar` already is.
///
/// The asking state has no timer of its own. It is up for exactly as long as the entry is held,
/// because those are the same fact — a bar that vanished early would leave the viewer looking at a
/// film whose entry was still, pointlessly, waiting on them.
private struct LetterboxdDiaryBarModifier<Label: View>: ViewModifier {
    let signal: LetterboxdPushSignal?
    let contentKey: String
    let alignment: Alignment
    @ViewBuilder let label: (LetterboxdDiaryBar) -> Label

    @State private var isConfirming = false
    /// Cancelled and replaced on each new entry, so a second film logged while the first bar is
    /// still up does not have its bar cut short by the first one's timer.
    @State private var hideTask: Task<Void, Never>?

    private var thisFilm: Int? { LetterboxdContentKey.tmdbID(fromMovieKey: contentKey) }

    /// Asking wins when both could be true. They are sequential in practice — answering takes the
    /// prompt down before the entry can land — but a slow send must not put the stars back up.
    private var state: LetterboxdDiaryBar? {
        if let prompt = signal?.ratingPrompt, let thisFilm, prompt.tmdbID == thisFilm {
            return .askingRating(tmdbID: prompt.tmdbID, current: prompt.current)
        }
        return isConfirming ? .logged : nil
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if let state {
                    label(state).transition(.move(edge: alignment == .bottom ? .bottom : .top)
                        .combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: state)
            .onChange(of: signal?.event) { _, _ in
                // Only for the film actually playing. An episode finishing elsewhere, or a queued
                // film draining minutes later, must not congratulate you about this one.
                guard let signal, let thisFilm, signal.lastLogged == thisFilm else { return }
                hideTask?.cancel()
                isConfirming = true
                hideTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    isConfirming = false
                }
            }
            .onDisappear { hideTask?.cancel() }
    }
}

public extension View {
    /// The Letterboxd diary bar for `contentKey`: asks for a rating while the entry is held, then
    /// confirms the landed entry for three seconds.
    ///
    /// Nothing is shown for a failed write: it is not actionable while a film is playing, and the
    /// Letterboxd settings card carries it.
    func letterboxdDiaryBar<Label: View>(
        signal: LetterboxdPushSignal?,
        contentKey: String,
        alignment: Alignment = .top,
        @ViewBuilder label: @escaping (LetterboxdDiaryBar) -> Label
    ) -> some View {
        modifier(LetterboxdDiaryBarModifier(signal: signal, contentKey: contentKey,
                                            alignment: alignment, label: label))
    }
}
