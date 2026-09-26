import DebridCore
import DebridUI
import Testing
@testable import Seret

@Suite struct EpisodeMenuTests {
    private func source(_ id: String) -> MediaSource {
        MediaSource(torrentID: id, fileID: nil, restrictedLink: "https://real-debrid.invalid/\(id)",
                   parsed: ParsedRelease(title: "Breaking Bad", resolution: "1080p"))
    }

    private func ownedRow(alternates: [MediaSource] = []) -> DetailStore.EpisodeRowInfo {
        let episode = Episode(season: 1, number: 3, source: source("primary"), alternates: alternates)
        return DetailStore.EpisodeRowInfo(season: 1, number: 3, meta: nil, ownedEpisode: episode)
    }

    private func notOwnedRow() -> DetailStore.EpisodeRowInfo {
        DetailStore.EpisodeRowInfo(season: 1, number: 3, meta: nil, ownedEpisode: nil)
    }

    @Test func anOwnedEpisodeOffersPlayFirst() {
        let menu = EpisodeMenu.make(row: ownedRow(), watched: false, inProgress: false, availability: .downloaded)
        #expect(menu.first == [.play])
    }

    @Test func playFromBeginningOnlyWhenInProgress() {
        let notInProgress = EpisodeMenu.make(row: ownedRow(), watched: false, inProgress: false, availability: .downloaded)
        #expect(notInProgress.first == [.play])

        let inProgress = EpisodeMenu.make(row: ownedRow(), watched: false, inProgress: true, availability: .downloaded)
        #expect(inProgress.first == [.play, .playFromBeginning])
    }

    @Test func versionsOnlyWhenThereAreAlternates() {
        let noAlternates = EpisodeMenu.make(row: ownedRow(), watched: false, inProgress: false, availability: .downloaded)
        #expect(!noAlternates.contains { $0.contains { if case .version = $0 { true } else { false } } })

        let alt = source("alt")
        let row = ownedRow(alternates: [alt])
        let withAlternates = EpisodeMenu.make(row: row, watched: false, inProgress: false, availability: .downloaded)
        let versionsGroup = withAlternates.first { $0.contains { if case .version = $0 { true } else { false } } }
        #expect(versionsGroup?.count == 2)
        #expect(versionsGroup?.contains(.version(row.ownedSource!, isPlaying: true)) == true)
        #expect(versionsGroup?.contains(.version(alt, isPlaying: false)) == true)
    }

    @Test func aMissingEpisodeOffersDownloadAndPlay() {
        let menu = EpisodeMenu.make(row: notOwnedRow(), watched: false, inProgress: false, availability: .notDownloaded)
        #expect(menu.first == [.downloadAndPlay])
    }

    @Test func noDownloadAndPlayWhileFindingOrDownloading() {
        let finding = EpisodeMenu.make(row: notOwnedRow(), watched: false, inProgress: false, availability: .finding)
        #expect(!finding.contains([.downloadAndPlay]))

        let downloading = EpisodeMenu.make(row: notOwnedRow(), watched: false, inProgress: false, availability: .downloading(0.4))
        #expect(!downloading.contains([.downloadAndPlay]))
    }

    @Test func cancelOnlyWhileDownloading() {
        let notDownloading = EpisodeMenu.make(row: notOwnedRow(), watched: false, inProgress: false, availability: .notDownloaded)
        #expect(!notDownloading.contains([.cancelDownload]))

        let downloading = EpisodeMenu.make(row: notOwnedRow(), watched: false, inProgress: false, availability: .downloading(0.4))
        #expect(downloading.contains([.cancelDownload]))
    }

    @Test func findOtherVersionsAlways() {
        let owned = EpisodeMenu.make(row: ownedRow(), watched: false, inProgress: false, availability: .downloaded)
        #expect(owned.contains([.findOtherVersions]))

        let notOwned = EpisodeMenu.make(row: notOwnedRow(), watched: false, inProgress: false, availability: .notDownloaded)
        #expect(notOwned.contains([.findOtherVersions]))
    }
}
