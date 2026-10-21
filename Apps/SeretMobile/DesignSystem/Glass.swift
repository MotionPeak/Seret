import SwiftUI

/// The Liquid Glass toolkit every screen builds on.
///
/// iOS 26 draws real Liquid Glass (`glassEffect`, `GlassEffectContainer`). iOS 18 — still the
/// deployment target — gets a faithful stand-in: a thin material, a white hairline, a brighter top
/// edge and a soft shadow, which is what the approved mockups draw.
///
/// Nothing outside this file calls `glassEffect` directly, so the fallback can never be forgotten
/// at one call site, and the DEBUG `-glassFallback` launch argument shows the iOS 18 look on an
/// iOS 26 simulator (no iOS 18 runtime is installed here).
enum GlassSupport {
    /// DEBUG only: `-glassFallback` forces the iOS 18 rendering everywhere this file draws glass.
    /// The system tab bar is not ours to restyle, so it stays Liquid Glass on iOS 26 regardless.
    static let forceFallback: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-glassFallback")
        #else
        false
        #endif
    }()
}

extension View {
    /// Glass behind this view, clipped to `shape`. `interactive` lets iOS 26 glass react to touch
    /// (it brightens and flexes under the finger); leave it off for glass that is not a control.
    @ViewBuilder
    func seretGlass<S: Shape>(in shape: S, interactive: Bool = true) -> some View {
        if #available(iOS 26, *), !GlassSupport.forceFallback {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background { GlassFallbackBackground(shape: shape) }
        }
    }
}

/// The iOS 18 glass: material + white hairline + top highlight + soft shadow.
struct GlassFallbackBackground<S: Shape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .background {
                // The shadow on its own underlay, cut away under the glass: a shadow on the
                // translucent fill itself darkened the picture seen THROUGH the glass.
                shape.fill(Color.black.opacity(0.32))
                    .blur(radius: 12)
                    .offset(y: 6)
                    .mask {
                        Rectangle().padding(-40)
                            .overlay { shape.blendMode(.destinationOut) }
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)
            }
            // A touch of white so the glass reads as a raised surface over a dark canvas, not a hole.
            .overlay(shape.fill(Color.white.opacity(0.07)))
            .overlay(shape.stroke(Color.white.opacity(0.30), lineWidth: 1))
            // Light catching the top edge — the cue that makes a flat blur look like glass.
            .overlay(
                shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1.2)
            )
    }
}

/// Groups glass shapes that sit together so iOS 26 can blend and morph them as one surface; a
/// plain pass-through on iOS 18.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = Theme.Space.md
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *), !GlassSupport.forceFallback {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Press feedback for glass controls. iOS 26's interactive glass already answers the finger, so
/// the scale is the fallback's job only — doubling it up looks rubbery.
struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let scales: Bool = {
            if #available(iOS 26, *), !GlassSupport.forceFallback { return false }
            return true
        }()
        return configuration.label
            .scaleEffect(scales && configuration.isPressed ? 0.94 : 1)
            .opacity(scales && configuration.isPressed ? 0.85 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

// MARK: - Circle

/// The round glass icon (search, settings, +, …) — the label only, so it can sit inside a
/// `NavigationLink` or a `Menu` as well as a `Button`.
struct GlassCircleLabel: View {
    let systemImage: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .seretGlass(in: Circle())
    }
}

/// A round glass icon button. `label` is what VoiceOver reads.
struct GlassCircleButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) { GlassCircleLabel(systemImage: systemImage, size: size) }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel(label)
    }
}

/// A glass circle with its name under it — the title page's action row (Trailer, Watchlist,
/// Watched, Versions, More), as g3 draws it. The label only, so it can sit inside a `Menu` as well
/// as a `Button`. `isOn` fills the circle white (a film on the watchlist, a watched film): white is
/// the one highlight colour, so "on" never needs a second hue.
struct GlassActionLabel: View {
    let systemImage: String
    let title: String
    var isOn = false
    var size: CGFloat = 52
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 7) {
            circle
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: size + 12)
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var circle: some View {
        let glyph = Image(systemName: systemImage)
            .font(.system(size: size * 0.36, weight: .semibold))
            .frame(width: size, height: size)
        if isOn {
            glyph.foregroundStyle(Theme.Palette.onFocus)
                .background(Theme.Palette.focus, in: Circle())
        } else {
            glyph.foregroundStyle(Theme.Palette.textPrimary)
                .seretGlass(in: Circle())
        }
    }
}

/// `GlassActionLabel` as a button. `title` is what VoiceOver reads, unless `accessibility` says
/// more ("Mark Watched" rather than "Watched").
struct GlassActionButton: View {
    let systemImage: String
    let title: String
    var isOn = false
    var accessibility: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassActionLabel(systemImage: systemImage, title: title, isOn: isOn)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(accessibility ?? title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A navigation-bar icon. iOS 26 draws every bar button on Liquid Glass itself, so a glass circle
/// of our own would be glass on glass; iOS 18 gets the toolkit's circle.
struct ToolbarGlassIcon: View {
    let systemImage: String

    var body: some View {
        if #available(iOS 26, *), !GlassSupport.forceFallback {
            Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
        } else {
            GlassCircleLabel(systemImage: systemImage, size: 38)
        }
    }
}

// MARK: - Pills

/// A glass capsule with an icon and a title (Subtitles, Audio, Trailer…).
struct GlassPill: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(GlassPillButtonStyle())
    }
}

/// The white primary action (Resume, Play, Sign In) with dark text.
struct PrimaryPill: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(PrimaryPillButtonStyle())
    }
}

/// `PrimaryPill` as a button style, for buttons that build their own label.
struct PrimaryPillButtonStyle: ButtonStyle {
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Theme.Palette.onFocus)
            .padding(.vertical, 13).padding(.horizontal, Theme.Space.xxl)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Theme.Palette.focus, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// `GlassPill` as a button style: a glass capsule with white text.
struct GlassPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        GlassPressStyle().makeBody(configuration: configuration)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.vertical, 12).padding(.horizontal, Theme.Space.xl)
            .contentShape(Capsule())
            .seretGlass(in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// White progress on a faint track — Continue Watching, downloads, the splash. Same as SeretTV's.
struct ProgressLine: View {
    let fraction: Double
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.track)
                Capsule().fill(Theme.Palette.focus)
                    .frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: height)
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        VStack(spacing: 20) {
            GlassGroup {
                HStack {
                    GlassCircleButton(systemImage: "magnifyingglass", label: "Search") {}
                    GlassCircleButton(systemImage: "gearshape", label: "Settings") {}
                }
            }
            PrimaryPill(title: "Resume", systemImage: "play.fill") {}
            GlassPill(title: "Subtitles", systemImage: "captions.bubble") {}
            ProgressLine(fraction: 0.4).frame(width: 160)
        }
    }
    .preferredColorScheme(.dark)
}
