import DebridCore
import Foundation

/// What the mirror needs from its local side: the seam plus every capability local can answer.
public protocol LocalWatchBacking: WatchProgressProviding, WatchSummaryProviding,
                                   WatchRatingProviding, ResumeFractionProviding {}

extension LocalWatchProvider: LocalWatchBacking {}

/// What the mirror needs from its Trakt side: the seam for write mirroring, ratings for the same,
/// and the community score — the one thing local can never answer.
public protocol TraktWatchBacking: WatchProgressProviding, WatchRatingProviding,
                                   CommunityRatingProviding {}

extension TraktWatchProvider: TraktWatchBacking {}
