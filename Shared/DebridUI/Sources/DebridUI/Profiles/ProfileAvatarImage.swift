import SwiftUI

/// Renders a profile's DiceBear avatar (a `"style:seed"` token → PNG) clipped to a circle, with a
/// solid-color placeholder while it loads or if the network fails. Shared by both apps so every
/// avatar — picker, launch gate, shell button — looks identical.
public struct ProfileAvatarImage: View {
    private let token: String
    private let diameter: CGFloat
    private let colorTag: String

    public init(token: String, diameter: CGFloat, colorTag: String) {
        self.token = token
        self.diameter = diameter
        self.colorTag = colorTag
    }

    public var body: some View {
        let hex = ProfileAvatars.backgroundHex(forColorTag: colorTag)
        AsyncImage(url: ProfileAvatars.imageURL(for: ProfileAvatars.token(token),
                                                size: 256, backgroundColor: hex)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Circle().fill(Color(avatarHex: hex))   // loading / failure placeholder
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }
}

private extension Color {
    /// Build a Color from a hex string without '#' (e.g. "EBC11D").
    init(avatarHex hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}
