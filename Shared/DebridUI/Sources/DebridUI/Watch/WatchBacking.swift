import DebridCore
import Foundation

/// Every capability the on-device watch state can answer, in one seam.
///
/// It used to have a Trakt twin (`TraktWatchBacking`) for the mirroring provider, plus a
/// `CommunityRatingProviding` that local could never answer. Trakt was removed 2026-08-15 — it had
/// been rejecting this build's client id since July — so local is the whole picture now.
public protocol LocalWatchBacking: WatchProgressProviding, WatchSummaryProviding,
                                   WatchRatingProviding {}

extension LocalWatchProvider: LocalWatchBacking {}
