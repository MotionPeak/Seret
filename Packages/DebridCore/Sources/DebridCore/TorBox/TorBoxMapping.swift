import Foundation

/// Maps TorBox's wire shapes into the shared `Torrent` / `TorrentInfo` currency so the library
/// pipeline never needs to know which provider a torrent came from.
enum TorBoxMapping {
    static let idPrefix = "tb:"
    static let linkPrefix = "torbox://"

    static func torrentID(_ id: Int) -> String { "\(idPrefix)\(id)" }

    static func numericID(_ torrentID: String) -> Int? {
        guard torrentID.hasPrefix(idPrefix) else { return nil }
        return Int(torrentID.dropFirst(idPrefix.count))
    }

    /// The only TorBox link that is ever persisted. The real `requestdl` URL is minted at play time.
    static func link(torrentID: Int, fileID: Int) -> String {
        "\(linkPrefix)\(Self.torrentID(torrentID))/\(fileID)"
    }

    static func parseLink(_ link: String) -> (torrentID: Int, fileID: Int)? {
        guard link.hasPrefix(linkPrefix) else { return nil }
        let parts = link.dropFirst(linkPrefix.count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let torrentID = numericID(String(parts[0])), let fileID = Int(parts[1])
        else { return nil }
        return (torrentID, fileID)
    }

    /// Real-Debrid's status vocabulary, which the rest of the app already understands.
    static func status(_ t: TorBoxTorrent) -> String {
        let state = (t.downloadState ?? "").lowercased()
        if t.downloadPresent == true || t.downloadFinished == true || state == "cached" || state == "completed" {
            return "downloaded"
        }
        if state.contains("error") { return "error" }
        switch state {
        case "metadl": return "magnet_conversion"
        case "paused", "queued", "checkingresumedata": return "queued"
        default: return "downloading"
        }
    }

    static func torrent(_ t: TorBoxTorrent) -> Torrent {
        let info = info(t)
        return Torrent(id: info.id, filename: info.filename, hash: info.hash, bytes: info.bytes,
                       host: "torbox", progress: info.progress, status: info.status,
                       added: info.added ?? "", links: info.links,
                       speed: info.speed, seeders: info.seeders)
    }

    static func info(_ t: TorBoxTorrent) -> TorrentInfo {
        let status = status(t)
        let ready = status == "downloaded"
        let torBoxFiles = t.files ?? []

        // Only an unzipped video file can be streamed. Zipped content has no per-file stream.
        let playable = torBoxFiles.filter { f in
            let ext = URL(fileURLWithPath: f.name).pathExtension.lowercased()
            return TorrentInfo.videoExtensions.contains(ext)
                && f.zipped != true
                && f.mimetype != "application/zip"
        }
        let playableIDs = Set(playable.map(\.id))

        let files = torBoxFiles.map { f in
            TorrentFile(id: f.id, path: f.name, bytes: f.size, selected: playableIDs.contains(f.id) ? 1 : 0)
        }
        // A handle per selected file, in file order — and only once the content is really there.
        let links = ready
            ? torBoxFiles.filter { playableIDs.contains($0.id) }
                .map { link(torrentID: t.id, fileID: $0.id) }
            : []

        let progress = ready ? 100 : min(max((t.progress ?? 0) * 100, 0), 100)
        return TorrentInfo(id: torrentID(t.id), filename: t.name, hash: t.hash, bytes: t.size,
                           progress: progress, status: status, files: files, links: links,
                           added: t.createdAt, speed: t.downloadSpeed, seeders: t.seeds)
    }
}
