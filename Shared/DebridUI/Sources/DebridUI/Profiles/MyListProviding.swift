import DebridCore
import Foundation

/// Sendable seam over `MyListStore` so `DetailStore` is testable without SwiftData.
public protocol MyListProviding: Sendable {
    func claim(profileID: String, contentKey: String) async throws
    func unclaim(profileID: String, contentKey: String) async throws
    func isClaimed(profileID: String, contentKey: String) async throws -> Bool
    func contentKeys(forProfile profileID: String) async throws -> [String]
}

extension MyListStore: MyListProviding {
    // `unclaim` / `isClaimed` / `contentKeys` satisfy directly. Provide the no-`at:` `claim`.
    public func claim(profileID: String, contentKey: String) async throws {
        try claim(profileID: profileID, contentKey: contentKey, at: Date())
    }
}
