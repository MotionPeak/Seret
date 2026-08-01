import DebridCore
import Foundation

/// Persistence seam for the user's chosen default version (DebridCore's `VersionPreferenceStore`
/// conforms). Non-throwing: a preference that cannot be read or written must degrade to "let the
/// quality ranker decide", never break the screen.
public protocol VersionPreferring: Sendable {
    func preferred(forContentKey key: String) async -> String?
    func choose(contentKey: String, sourceKey: String) async
    func clear(contentKey: String) async
}

#if canImport(SwiftData)
extension VersionPreferenceStore: VersionPreferring {
    public func preferred(forContentKey key: String) async -> String? {
        try? preferredSourceKey(forContentKey: key)
    }

    public func choose(contentKey: String, sourceKey: String) async {
        try? setChoice(contentKey: contentKey, sourceKey: sourceKey, at: Date())
    }

    public func clear(contentKey: String) async {
        try? clearChoice(contentKey: contentKey)
    }
}
#endif
