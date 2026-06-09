import Foundation

/// Profile avatars are **local emoji** — rendered on-device as text inside the profile's colour
/// circle. No network, so every one shows instantly (the old DiceBear HTTP avatars left blank
/// circles whenever the CDN was slow/unreachable, especially on Apple TV). An avatar is stored as
/// the emoji string itself.
public enum ProfileAvatars {
    /// A big, varied set of emoji (faces, animals, creatures, things) for the picker.
    public static let all: [String] = [
        "😀", "😎", "🤩", "🥳", "😈", "🤖", "👻", "👽",
        "🐶", "🐱", "🦊", "🐼", "🐯", "🦁", "🐸", "🐵",
        "🐧", "🦉", "🦄", "🐲", "🦖", "🦋", "🐙", "🦀",
        "🌟", "🔥", "⚡️", "🌈", "🍿", "🎮", "🎬", "🎸",
        "🚀", "👾", "💎", "🎃", "🍕", "🦕", "🐢", "🐝",
    ]

    /// Fallback for a profile with no avatar (or a legacy DiceBear `"style:seed"` token).
    public static let fallback = "🍿"

    /// Resolve a stored avatar value to a renderable emoji. Legacy DiceBear tokens (which contain
    /// ":") and empty values map to the fallback emoji.
    public static func emoji(_ stored: String) -> String {
        stored.isEmpty || stored.contains(":") ? fallback : stored
    }

    /// Back-compat shim — older call sites resolve a stored value to a "token". Now an emoji.
    public static func token(_ stored: String) -> String { emoji(stored) }

    /// Hex (no '#') for a profile colour tag — the avatar circle's background.
    public static func backgroundHex(forColorTag tag: String) -> String {
        switch tag {
        case "blue":   return "3B82F6"
        case "green":  return "22C55E"
        case "red":    return "EF4444"
        case "purple": return "A855F7"
        default:        return "EBC11D"   // gold
        }
    }
}
