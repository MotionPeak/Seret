import DebridCore
import Foundation
import Observation
import SwiftData

/// Owns the one shared `RealDebridSession` and the app's coarse auth state. It is the
/// `AccessTokenProviding` source that 7b's library + 7c's playback will consume.
@MainActor
@Observable
final class AppSession {
    enum State: Equatable { case unknown, signedIn, signedOut }

    private(set) var state: State = .unknown

    /// The sign-in model for the current signed-out episode (nil while signed in or
    /// unresolved). Built when *entering* `.signedOut` so the view never creates it
    /// during `body` evaluation.
    private(set) var signInModel: SignInModel?

    /// The library store for the current signed-in episode (nil while signed out).
    private(set) var libraryStore: LibraryStore?

    /// On-demand TMDB detail provider for the Detail screen (nil while signed out).
    private(set) var detailsProvider: MediaDetailsProviding?

    /// Shared watch-progress store (nil while signed out, or if the container fails to build).
    /// 7c's player + a later Continue-Watching feed reuse this same instance.
    private(set) var watchStore: WatchProgressProviding?

    /// On-demand OpenSubtitles provider (nil while signed out or if no key+account configured).
    private(set) var subtitlesProvider: SubtitleProvider?
    private var watchProgressStore: WatchProgressStore?   // concrete ref for PlaybackCoordinator
    private var torrents: TorrentsClient?

    let realDebrid: RealDebridSession

    init(realDebrid: RealDebridSession) {
        self.realDebrid = realDebrid
    }

    /// Resolve launch state from persisted credentials. `validAccessToken()` throws
    /// `.notSignedIn` ONLY when there are no stored credentials, which lets us treat
    /// offline-with-credentials as optimistically signed in (spec §143) while a server
    /// rejection of the refresh token routes back to sign-in (spec §165).
    func resolve() async {
        do {
            _ = try await realDebrid.validAccessToken()
            enterSignedIn()
        } catch RealDebridSessionError.notSignedIn {
            enterSignedOut()
        } catch HTTPError.status(_, _) {
            // RD actively rejected the stored/refresh token → must re-authenticate.
            enterSignedOut()
        } catch {
            // Transport/offline but credentials exist: stay signed in; later calls retry.
            // (A genuine decoding bug would also land here as optimistic-signedIn; the
            // first real library call in 7b surfaces it — acceptable for this slice.)
            enterSignedIn()   // transport/offline with stored creds: optimistic
        }
    }

    func markSignedIn() {
        enterSignedIn()
        signInModel = nil
    }

    func signOut() async {
        try? await realDebrid.signOut()
        enterSignedOut()
    }

    /// Enter `.signedOut` with a fresh sign-in model for the new episode.
    private func enterSignedOut() {
        guard state != .signedOut else { return }
        signInModel = SignInModel(
            flow: LiveAuthFlow(auth: RealDebridAuthClient(), session: realDebrid),
            onSignedIn: { [weak self] in self?.markSignedIn() })
        libraryStore = nil
        detailsProvider = nil
        watchStore = nil
        watchProgressStore = nil
        torrents = nil
        subtitlesProvider = nil
        state = .signedOut
    }

    /// Enter `.signedIn`, composing the DebridCore library pipeline once. Thin glue: the app
    /// assembles brain objects and reads a config value; no RD/TMDB logic lives here.
    private func enterSignedIn() {
        guard state != .signedIn else { return }
        let tmdb = TMDBClient(apiKey: Secrets.tmdbAPIKey)
        let torrents = TorrentsClient(tokens: realDebrid)
        self.torrents = torrents
        let service = LibraryService(
            torrents: torrents,
            builder: LibraryBuilder(),
            enricher: MetadataEnricher(tmdb: tmdb),
            store: LibrarySnapshotStore(directory: Self.cachesDirectory))
        libraryStore = LibraryStore(library: service)
        detailsProvider = TMDBDetailsService(client: tmdb)
        let concreteStore = (try? ModelContainer(for: WatchProgress.self))
            .map { WatchProgressStore(modelContainer: $0) }
        watchProgressStore = concreteStore
        watchStore = concreteStore.map { $0 as WatchProgressProviding }
        let osKey = Secrets.openSubtitlesAPIKey
        if !osKey.isEmpty,
           let account = KeychainSecretStore(service: "com.solomons.seret.opensubtitles").readAccount() {
            subtitlesProvider = OpenSubtitlesProvider(apiKey: osKey, credentials: account.credentials)
        } else {
            subtitlesProvider = nil
        }
        state = .signedIn
    }

    /// Build a fully-wired player for a playback request, or nil if not signed in.
    func makePlayer(for request: PlaybackRequest) -> (PlayerModel, VLCKitVideoPlayerEngine)? {
        guard let torrents, let store = watchProgressStore else { return nil }
        let coordinator = PlaybackCoordinator(store: store)
        let engine = VLCKitVideoPlayerEngine()
        let thumbnails = ThumbnailProvider()
        let contentKey = request.contentKey
        let sourceKey = WatchKey.source(request.source)
        let model = PlayerModel(
            request: request,
            engine: engine,
            unrestrict: { link in
                let unrestricted = try await torrents.unrestrict(link: link)
                guard let url = URL(string: unrestricted.download) else { throw URLError(.badURL) }
                return url
            },
            recordProgress: { position, duration in
                await coordinator.record(contentKey: contentKey, sourceKey: sourceKey,
                                         position: position, duration: duration)
            },
            subtitles: subtitlesProvider,
            fetchThumbnail: { url, fraction in await thumbnails.frame(url: url, fraction: fraction) })
        return (model, engine)
    }

    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}
