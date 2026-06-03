import DebridCore
import SwiftUI

/// Stands in for the real player (Plan 7c). Renders the resolved playback intent so the
/// drill-down is verifiable end-to-end without playback. 7c replaces this destination.
struct PlayerPlaceholderView: View {
    let request: PlaybackRequest

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "play.tv").font(.system(size: 72)).foregroundStyle(.secondary)
            Text(request.label).font(.title.bold()).multilineTextAlignment(.center)
            QualityChips(parsed: request.source.parsed)
            Text(request.resumeAt.map { "Would resume at \(Self.timecode($0))" } ?? "Would play from the start")
                .font(.title3).foregroundStyle(.secondary)
            Text("The video player arrives in Plan 7c.").font(.callout).foregroundStyle(.tertiary)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Player")
    }

    /// `h:mm:ss` (or `m:ss` under an hour).
    static func timecode(_ seconds: Double) -> String {
        let s = Int(seconds)
        let (h, m, sec) = (s / 3600, (s % 3600) / 60, s % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
