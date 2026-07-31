import DebridUI
import SwiftUI

/// The viewer's own history with a title: how many times, when last, and how far back it goes.
/// Renders nothing at all when the title has never been watched — no empty rows, no placeholder.
struct WatchDatesLine: View {
    let summary: WatchSummary?
    let since: Date?

    var body: some View {
        if let summary, summary.plays > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Watched \(summary.plays) time\(summary.plays == 1 ? "" : "s")")
                if let last = summary.lastWatchedAt {
                    Text("Last watched \(last.formatted(date: .abbreviated, time: .omitted))")
                }
                if let since {
                    Text("In your history since \(since.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .font(.seret(Theme.Typography.captionSize))
            .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
