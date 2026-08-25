import DebridCore
import Foundation

/// Persistence seam for the user's chosen default version (DebridCore's `VersionPreferenceStore`
/// conforms). Non-throwing: a preference that cannot be read or written must degrade to "let the
/// quality ranker decide", never break the screen.
public protocol VersionPreferring: Sendable {
    func preferred(forContentKey key: String) async -> String?
    /// Batched read: chosen versions for many titles at once. Declared as a requirement so the
    /// real store's single fetch is used through the seam; fakes fall back to the default below.
    func preferred(forContentKeys keys: [String]) async -> [String: String]
    func choose(contentKey: String, sourceKey: String) async
    func clear(contentKey: String) async
}

public extension VersionPreferring {
    /// Default batched read: one per-key call each. Correct everywhere; stores with a real batch
    /// fetch override it for one round-trip.
    func preferred(forContentKeys keys: [String]) async -> [String: String] {
        var out: [String: String] = [:]
        for key in keys { out[key] = await preferred(forContentKey: key) }
        return out
    }
}

#if canImport(SwiftData)
extension VersionPreferenceStore: VersionPreferring {
    public func preferred(forContentKey key: String) async -> String? {
        try? preferredSourceKey(forContentKey: key)
    }

    public func preferred(forContentKeys keys: [String]) async -> [String: String] {
        (try? preferredSourceKeys(forContentKeys: keys)) ?? [:]
    }

    public func choose(contentKey: String, sourceKey: String) async {
        try? setChoice(contentKey: contentKey, sourceKey: sourceKey, at: Date())
    }

    public func clear(contentKey: String) async {
        try? clearChoice(contentKey: contentKey)
    }
}
#endif
