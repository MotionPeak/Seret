#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// DEBUG-only visual harness for the magnet paste form, mirroring SeretTV's `PlayerUIPreview`.
/// Reaching the real sheet means navigating to an unowned title, and the simulator's synthesized
/// input is unreliable — so this boots straight to the form with its model already driven into a
/// given state, for screenshot verification.
///
/// Launch with `-uiPreview <target>`:
///   - `magnetidle`    — the resting form, Download disabled
///   - `magnetinvalid` — a paste that isn't a magnet
///   - `magnetready`   — a valid magnet, release name shown, Download enabled
///   - `magnetfailed`  — RD refused the add
///
/// Not compiled into release builds.
struct MagnetUIPreview: View {
    let target: String

    var body: some View {
        NavigationStack {
            MagnetAddForm(model: Self.model(for: target))
                .navigationTitle("Add by Magnet")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") {} }
                }
        }
        // RootView sets this app-wide; the harness bypasses RootView, so without it these
        // screenshots render light and misrepresent how the sheet actually looks.
        .preferredColorScheme(.dark)
    }

    /// A model on stub dependencies, driven into the requested state. `.failed` is produced by a
    /// stub whose RD call throws, so the message is the real one the user would see — not a
    /// hand-written string that could drift from the production text.
    @MainActor static func model(for target: String) -> MagnetAddModel {
        let hex = "0123456789abcdef0123456789abcdef01234567"
        let fails = target == "magnetfailed"
        let store = DownloadStore(service: StubRequesting(fails: fails),
                                  records: StubRecords(),
                                  poller: StubPoller(),
                                  deleter: StubDeleter(),
                                  pollInterval: .seconds(60))
        let model = MagnetAddModel(
            target: .init(contentKey: DownloadKey.season(showTmdbID: 15969, season: 1),
                          tmdbID: 15969, title: "HaPijamot Season 1", kind: .show),
            downloads: store)
        switch target {
        case "magnetinvalid":
            model.update(text: "not a magnet link")
        case "magnetready":
            model.update(text: "magnet:?xt=urn:btih:\(hex)&dn=HaPijamot.S01E01.HDTV.x264")
        case "magnetfailed":
            model.update(text: "magnet:?xt=urn:btih:\(hex)")
            Task { await model.submit() }
        default:
            break
        }
        return model
    }
}

private enum StubError: Error { case refused }

private struct StubRequesting: DownloadRequesting {
    let fails: Bool
    func startDownload(infoHash: String) async throws -> TorrentInfo {
        if fails { throw StubError.refused }
        return TorrentInfo(id: "T", filename: "f", hash: infoHash, bytes: 1, progress: 0,
                           status: "queued", files: [], links: [])
    }
}

private struct StubRecords: DownloadRecording {
    func upsert(_ data: DownloadRequestData) async throws {}
    func all() async throws -> [DownloadRequestData] { [] }
    func delete(torrentID: String) async throws {}
}

private struct StubPoller: DownloadPolling {
    func poll() async throws -> [DownloadStatus] { [] }
}

private struct StubDeleter: DownloadDeleting {
    func deleteTorrent(id: String) async throws {}
}
#endif
