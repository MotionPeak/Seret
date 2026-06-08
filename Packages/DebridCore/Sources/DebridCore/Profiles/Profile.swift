import Foundation
import SwiftData

/// A viewer profile on the shared Real-Debrid account (Netflix-style). CloudKit-ready: every
/// property defaulted, no unique constraint. `id` is a caller-supplied UUID string.
@Model
public final class Profile {
    public var id: String = ""
    public var name: String = ""
    /// A design-system color token (e.g. "gold"); the UI maps it to a palette. Stored as a string
    /// so the brain stays UI-free.
    public var colorTag: String = ""
    public var createdAt: Date = Date(timeIntervalSince1970: 0)

    public init(id: String = "", name: String = "", colorTag: String = "",
                createdAt: Date = Date(timeIntervalSince1970: 0)) {
        self.id = id
        self.name = name
        self.colorTag = colorTag
        self.createdAt = createdAt
    }
}

/// `Sendable` snapshot of a `Profile` — what the store hands back, so callers never touch the
/// non-`Sendable` `@Model`.
public struct ProfileDTO: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let colorTag: String
    public let createdAt: Date

    public init(id: String, name: String, colorTag: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.colorTag = colorTag
        self.createdAt = createdAt
    }

    public init(_ m: Profile) {
        self.init(id: m.id, name: m.name, colorTag: m.colorTag, createdAt: m.createdAt)
    }
}
