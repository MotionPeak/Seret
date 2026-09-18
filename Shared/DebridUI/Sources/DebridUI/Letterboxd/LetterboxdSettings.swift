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

/// Settings that follow the Apple ID rather than the device.
///
/// The username is typed on the iPhone and read on the Apple TV, and `UserDefaults` is per-device —
/// so a plain defaults store leaves the TV permanently saying "set this on your phone". iCloud's
/// key-value store syncs it. Both apps declare the SAME `ubiquity-kvstore-identifier`, because
/// their bundle ids differ and the default identifier is derived from the bundle id.
///
/// Every write also goes to `UserDefaults`, and a read falls back to it: iCloud may be unavailable
/// (no account, offline, first launch before the first sync), and the import should still work on
/// the device where the username was typed.
public struct UbiquitousLetterboxdSettingsStore: LetterboxdSettingsStoring, @unchecked Sendable {
    private static let key = "letterboxd.settings"
    private let cloud: NSUbiquitousKeyValueStore
    private let local: UserDefaults

    public init(cloud: NSUbiquitousKeyValueStore = .default, local: UserDefaults = .standard) {
        self.cloud = cloud
        self.local = local
    }

    /// Ask iCloud to pull anything newer. Cheap, and safe to call on launch.
    public func synchronize() { cloud.synchronize() }

    public func load() -> LetterboxdSettings {
        if let data = cloud.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(LetterboxdSettings.self, from: data) {
            return decoded
        }
        if let data = local.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(LetterboxdSettings.self, from: data) {
            return decoded
        }
        return LetterboxdSettings()
    }

    public func save(_ settings: LetterboxdSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        cloud.set(data, forKey: Self.key)
        cloud.synchronize()
        local.set(data, forKey: Self.key)      // so it survives iCloud being unavailable
    }
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
