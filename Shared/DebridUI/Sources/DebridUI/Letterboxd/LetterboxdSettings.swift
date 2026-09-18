import Foundation

public struct LetterboxdSettings: Sendable, Codable, Equatable {
    /// The public profile to read, e.g. "thebigshin".
    public var username: String
    public var isEnabled: Bool
    public var lastImportAt: Date?

    public init(username: String = "", isEnabled: Bool = false, lastImportAt: Date? = nil) {
        self.username = username
        self.isEnabled = isEnabled
        self.lastImportAt = lastImportAt
    }
}

public protocol LetterboxdSettingsStoring: Sendable {
    func load() -> LetterboxdSettings
    func save(_ settings: LetterboxdSettings)
}

/// `@unchecked Sendable` because `UserDefaults` is documented thread-safe but not marked `Sendable`.
/// The store is captured by the import closure, which is `@Sendable`, so the compiler needs telling.
public struct UserDefaultsLetterboxdSettingsStore: LetterboxdSettingsStoring, @unchecked Sendable {
    private static let key = "letterboxd.settings"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> LetterboxdSettings {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(LetterboxdSettings.self, from: data)
        else { return LetterboxdSettings() }
        return decoded
    }

    public func save(_ settings: LetterboxdSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
