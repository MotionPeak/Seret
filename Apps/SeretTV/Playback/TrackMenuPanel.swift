import SwiftUI
import DebridCore

struct TrackMenuPanel: View {
    @Bindable var model: PlayerModel
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.35).onTapGesture { onClose() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Subtitles").font(.title3.bold())
                    Button("Off") { model.selectSubtitleOff() }
                    ForEach(model.subtitleTracks) { track in
                        Button(track.name) { model.selectSubtitle(id: track.id) }
                    }
                    Text("Download from OpenSubtitles").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.subtitleRows) { row in
                        SubtitleRowButton(row: row) { Task { await model.requestSubtitle(language: row.language) } }
                    }
                    Divider()
                    Text("Audio").font(.title3.bold())
                    ForEach(model.audioTracks) { track in
                        Button(track.name) { model.selectAudio(id: track.id) }
                    }
                }
                .padding(28)
            }
            .frame(width: 600)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea()
    }
}

private struct SubtitleRowButton: View {
    let row: PlayerModel.SubtitleRow
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(displayName)
                Spacer()
                trailing
            }
        }
        .disabled(isDisabled)
    }
    private var displayName: String { row.language == "he" ? "Hebrew" : "English" }
    @ViewBuilder private var trailing: some View {
        switch row.state {
        case .idle: Image(systemName: "arrow.down.circle")
        case .downloading: ProgressView()
        case .attached: Image(systemName: "checkmark")
        case .capReached(let reset): Text(reset == nil ? "Daily limit" : "Resets \(reset!.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
        case .error: Text("Retry").foregroundStyle(.orange)
        case .noAccount: Text("Add account in Settings").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var isDisabled: Bool { if case .capReached = row.state { return true }; if case .noAccount = row.state { return true }; if case .downloading = row.state { return true }; return false }
}
