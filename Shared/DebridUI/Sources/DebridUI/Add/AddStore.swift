import DebridCore
import Observation

/// Drives the Add flow for one chosen title: fetch cached streams, rank by
/// original-language+quality, and add the pick to RD.
@MainActor
@Observable
public final class AddStore {
    public enum State: Equatable {
        case idle, loadingStreams, streams, noStreams, failed(String)
        case adding, added(TorrentInfo), addFailed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var ranked: [CachedStream] = []
    public private(set) var best: CachedStream?
    public private(set) var isFallback = false

    private let imdbID: String
    private let kind: StreamQuery.Kind
    private let originalLanguage: String?
    private let streamSource: StreamSource
    private let addService: AddProviding

    public init(imdbID: String, kind: StreamQuery.Kind, originalLanguage: String?,
                streamSource: StreamSource, add: AddProviding) {
        self.imdbID = imdbID; self.kind = kind; self.originalLanguage = originalLanguage
        self.streamSource = streamSource; self.addService = add
    }

    public func loadStreams() async {
        state = .loadingStreams
        do {
            let query = StreamQuery(imdbID: imdbID, kind: kind, originalLanguage: originalLanguage)
            let found = try await streamSource.streams(for: query)
            ranked = found.rankedFor(originalLanguage: originalLanguage)
            if let match = found.bestMatch(originalLanguage: originalLanguage) {
                best = match.stream; isFallback = match.isFallback; state = .streams
            } else {
                best = nil; isFallback = false; state = .noStreams
            }
        } catch {
            state = .failed("Couldn't find sources. Check your connection and try again.")
        }
    }

    /// How many ranked candidates "Get best" will try before giving up. ElfCache "cached" isn't
    /// a guarantee a torrent is instant for THIS account, so the top pick sometimes isn't
    /// instantly available — fall through to the next best instead of failing outright.
    private static let maxAddAttempts = 6

    /// Adds the best available version, automatically falling back to the next-ranked one if a
    /// pick turns out not to be instantly available (each failed attempt self-cleans in RD).
    public func addBest() async {
        guard !ranked.isEmpty else { return }
        state = .adding
        for stream in ranked.prefix(Self.maxAddAttempts) {
            do {
                let info = try await addService.add(infoHash: stream.infoHash)
                best = stream            // the version that actually landed
                state = .added(info)
                return
            } catch {
                continue                 // not instant for this account → try the next
            }
        }
        state = .addFailed("None of the cached versions were instantly available. Try again later.")
    }

    public func add(stream: CachedStream) async {
        state = .adding
        do {
            let info = try await addService.add(infoHash: stream.infoHash)
            state = .added(info)
        } catch let RDAddError.notInstant(torrentID) {
            state = .addFailed("That version isn't instantly available (RD id \(torrentID)).")
        } catch {
            state = .addFailed("Couldn't add this to Real-Debrid. Try another version.")
        }
    }
}
