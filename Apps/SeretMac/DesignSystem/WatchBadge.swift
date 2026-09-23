import DebridCore

/// What a poster's watched indicator shows, derived from `WatchState`. Pure — every grid/rail
/// reads the same rule.
enum WatchBadge: Equatable {
    case none, watched, progress(Double)

    /// `finished` → watched, regardless of the stored position (a manual mark carries one forward,
    /// but the badge only cares that it is done). A measured position → a progress fraction,
    /// clamped to 0.02…1 so even a few seconds in shows a sliver. Anything else (no state, never
    /// started, or an unknown length) → no badge.
    init(_ state: WatchState?) {
        guard let state else { self = .none; return }
        if state.finished { self = .watched; return }
        guard state.positionSeconds > 0, state.durationSeconds > 0 else { self = .none; return }
        self = .progress(min(1, max(0.02, state.positionSeconds / state.durationSeconds)))
    }
}
