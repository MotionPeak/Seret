import Foundation

public struct LetterboxdSettings: Sendable, Codable, Equatable {
    /// The public profile to read, e.g. "thebigshin".
    public var username: String
    public var isEnabled: Bool
    public var lastImportAt: Date?
    /// Where SeretServer lives, e.g. `http://192.168.1.179:8080`.
    ///
    /// Writing to Letterboxd needs a real browser, and only the server has one — tvOS has no
    /// WebKit at all. So a removal made on the Apple TV is pushed through here. Empty means the
    /// removal is honoured locally and Letterboxd is simply not told, which is the behaviour
    /// before any of this existed.
    ///
    /// It rides the same iCloud key-value store as the username, and for the same reason: it is
    /// typed once on the iPhone and read on the TV.
    public var serverURL: String

    public init(username: String = "", isEnabled: Bool = false, lastImportAt: Date? = nil,
                serverURL: String = "") {
        self.username = username
        self.isEnabled = isEnabled
        self.lastImportAt = lastImportAt
        self.serverURL = serverURL
    }

    /// Decoded leniently, because this blob is persisted and the store falls back to defaults when
    /// it cannot be read — which makes a decoding failure silent AND destructive. A missing
    /// `serverURL` would have thrown, the store would have handed back a blank `LetterboxdSettings`,
    /// and the username typed on the iPhone would simply have vanished.
    ///
    /// Same reasoning as `LetterboxdWrite`: every field added later must be absent-tolerant.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        lastImportAt = try c.decodeIfPresent(Date.self, forKey: .lastImportAt)
        serverURL = try c.decodeIfPresent(String.self, forKey: .serverURL) ?? ""
    }

    /// `serverURL` parsed into something that can actually be sent to.
    ///
    /// A bare `host:port` is what a person types, and a URL without a scheme is not a URL. Named
    /// apart from the stored string it reads because both are wanted: the watchlist relay passes
    /// the address along as typed, and the diary push needs a base to build paths on.
    public var serverBaseURL: URL? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "http://\(trimmed)")
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
