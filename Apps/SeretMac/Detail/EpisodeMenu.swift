import DebridCore
import DebridUI

/// One thing an episode card's right-click menu can do. `.version` is one entry of the "Versions ▸"
/// submenu — `EpisodeCard` builds that submenu from the group carrying these, rather than a flat
/// item, but the menu logic that decides WHICH versions to offer (and which is ✓) lives here so it
/// is tested without a view.
enum EpisodeMenuItem: Hashable {
    case play, playFromBeginning, downloadAndPlay, markWatched(Bool)
    case version(MediaSource, isPlaying: Bool)
    case findOtherVersions, cancelDownload
}

/// What an episode card's context menu offers, worked out once from the row's ownership, watch and
/// download state — mirrors `TitleMenu.make` / `VersionMenu.make`'s shape.
enum EpisodeMenu {
    /// Owned: `[play, playFromBeginning?]` · `[markWatched]` · `[versions…]` (only with alternates)
    /// · `[findOtherVersions]`.
    /// Not owned: `[downloadAndPlay]` (unless already finding/downloading) · `[markWatched]` ·
    /// `[findOtherVersions]` · `[cancelDownload]` (only while downloading).
    static func make(row: DetailStore.EpisodeRowInfo, watched: Bool, inProgress: Bool,
                     availability: TitleAcquirer.EpisodeAvailability) -> [[EpisodeMenuItem]] {
        if row.isDownloaded {
            var playGroup: [EpisodeMenuItem] = [.play]
            if inProgress { playGroup.append(.playFromBeginning) }
            var groups: [[EpisodeMenuItem]] = [playGroup, [.markWatched(!watched)]]
            if row.hasAlternateVersions {
                groups.append(row.ownedVersions.map { .version($0, isPlaying: $0 == row.ownedSource) })
            }
            groups.append([.findOtherVersions])
            return groups
        }

        var groups: [[EpisodeMenuItem]] = []
        switch availability {
        case .finding, .downloading:
            break   // already in flight — clicking again would only double the attempt
        default:
            groups.append([.downloadAndPlay])
        }
        groups.append([.markWatched(!watched)])
        groups.append([.findOtherVersions])
        if case .downloading = availability {
            groups.append([.cancelDownload])
        }
        return groups
    }
}
