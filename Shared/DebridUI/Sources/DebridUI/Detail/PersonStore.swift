import DebridCore
import Observation

/// The store behind a person page: who they are, and what of theirs you can watch.
///
/// It hands the UI `SearchHit`s rather than credits, so a title found through an actor routes
/// through the *same* poster tile a search result does — with no per-platform mapping and no second
/// opinion about what "owned" means.
///
/// Ranking lives in `DebridCore` (`actingFilmography()` / `directingFilmography()`), not here.
@MainActor
@Observable
public final class PersonStore {
    public enum State: Equatable { case idle, loading, loaded, empty, failed(String) }

    public private(set) var state: State = .idle
    public private(set) var person: TMDBPersonDetails?
    /// Things they acted in, most recognisable first.
    public private(set) var acting: [SearchHit] = []
    /// Things they directed, most recognisable first.
    public private(set) var directing: [SearchHit] = []

    public let ref: TMDBPersonRef
    private let credits: PersonCreditsProviding

    public init(ref: TMDBPersonRef, credits: PersonCreditsProviding) {
        self.ref = ref
        self.credits = credits
    }

    /// TMDB's name once it lands, the one we navigated with until then — so the header never
    /// flashes empty on the way in.
    public var name: String { person?.name ?? ref.name }
    public var profilePath: String? { person?.profilePath }
    public var knownFor: String? { person?.knownForDepartment }

    /// Loads once. A second call is a no-op unless the first one failed, so a view whose `.task`
    /// re-runs (a size-class flip, a re-render) does not re-hit TMDB.
    public func load() async {
        switch state {
        case .loading, .loaded, .empty: return
        case .idle, .failed: break
        }
        state = .loading
        do {
            let details = try await credits.person(tmdbID: ref.id)
            guard !Task.isCancelled else { return }
            person = details
            acting = details.castCredits.actingFilmography().map(Self.hit)
            directing = details.crewCredits.directingFilmography().map(Self.hit)
            state = acting.isEmpty && directing.isEmpty ? .empty : .loaded
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed("Couldn't load \(ref.name).")
        }
    }

    private static func hit(_ credit: TMDBPersonCredit) -> SearchHit {
        SearchHit(result: credit.result, kind: credit.kind)
    }
}
