import Foundation

/// The curated set of cute emoji avatars a profile can pick from. UI-agnostic data (just strings)
/// so both apps share the same options.
public enum ProfileAvatars {
    public static let all: [String] = [
        "🦊", "🐼", "🐧", "🦄", "🐯", "🐸", "🐙", "🐰",
        "🐨", "🐵", "🦁", "🐶", "🐱", "🐮", "🐷", "🐻",
        "🦖", "🦉", "🐝", "🦋", "🍿", "👾", "🚀", "⭐️",
    ]

    /// A stable fallback when a profile has no avatar yet (old rows).
    public static let fallback = "🍿"
}
