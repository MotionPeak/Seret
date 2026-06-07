import Foundation
import Observation

/// Observable, `UserDefaults`-persisted trailer preferences. Lives on `AppSession`; the Settings UI
/// binds to it and `TrailerModel` reads it. Mirrors `SubtitleSettingsModel`.
@MainActor
@Observable
public final class TrailerSettingsModel {
    /// Auto-play a muted trailer on the detail backdrop. Default on.
    public var autoplayTrailers: Bool { didSet { defaults.set(autoplayTrailers, forKey: Self.key) } }

    private let defaults: UserDefaults
    private static let key = "seret.autoplayTrailers"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoplayTrailers = defaults.object(forKey: Self.key) as? Bool ?? true
    }
}
