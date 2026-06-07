import SwiftUI
import AppKit

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

// The Seret play triangle (matches Brand.swift exactly).
struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.32, y: h * 0.24))
        p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.76))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.50))
        p.closeSubpath()
        return p
    }
}

let goldBright = Color(hex: 0xFDE98A)
let gold       = Color(hex: 0xEBC11D)
let goldLight  = Color(hex: 0xF6D24A)
let goldDeep   = Color(hex: 0xC8930A)
let glow       = Color(hex: 0xEBC11D, alpha: 0.55)
let markGradient = LinearGradient(colors: [goldBright, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
let goldText = LinearGradient(colors: [goldLight, gold, goldDeep], startPoint: .top, endPoint: .bottom)

struct SeretMark: View {
    var body: some View {
        GeometryReader { geo in
            let corner = geo.size.width * 0.14
            PlayTriangle().fill(markGradient)
                .overlay(PlayTriangle().stroke(markGradient, style: StrokeStyle(lineWidth: corner, lineJoin: .round)))
                .shadow(color: glow, radius: geo.size.width * 0.26)
                .shadow(color: glow, radius: geo.size.width * 0.10)
        }.aspectRatio(1, contentMode: .fit)
    }
}

// Measure rendered widths so SERET is tracked to exactly span the Hebrew hero's width.
func widthOf(_ s: String, size: CGFloat, weight: NSFont.Weight, tracking: CGFloat = 0) -> CGFloat {
    var attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight)]
    if tracking != 0 { attrs[.kern] = tracking }
    return NSAttributedString(string: s, attributes: attrs).size().width
}

struct TopShelf: View {
    var frameW: CGFloat = 1920
    let hebrewSize: CGFloat = 250
    let latinSize: CGFloat = 74
    var hebrewWidth: CGFloat { widthOf("סֶרֶט", size: hebrewSize, weight: .bold) }
    var latinTracking: CGFloat {
        let base = widthOf("SERET", size: latinSize, weight: .semibold)
        return max(20, (hebrewWidth - base) / 5)   // spread SERET to the Hebrew width
    }
    var seretWidth: CGFloat { hebrewWidth }

    var body: some View {
        ZStack {
            Color(hex: 0x08080A)
            RadialGradient(colors: [Color(hex: 0xEBC11D, alpha: 0.20), .clear],
                           center: UnitPoint(x: 0.5, y: 0.5), startRadius: 0, endRadius: 720)
            HStack(spacing: 96) {
                VStack(spacing: 18) {
                    Text("סֶרֶט")
                        .font(.system(size: hebrewSize, weight: .bold))
                        .foregroundStyle(goldText)
                        .environment(\.layoutDirection, .rightToLeft)
                        .shadow(color: glow, radius: 64)
                        .shadow(color: glow, radius: 22)
                        .fixedSize()
                    Text("SERET")
                        .font(.system(size: latinSize, weight: .semibold))
                        .tracking(latinTracking)
                        .foregroundStyle(.white)
                        .frame(width: seretWidth)
                        .shadow(color: .black.opacity(0.55), radius: 10)
                }
                SeretMark().frame(width: 326, height: 326)
            }
        }
        .frame(width: frameW, height: 720)
    }
}

@MainActor func render(frameW: CGFloat, scale: CGFloat, to path: String) {
    let r = ImageRenderer(content: TopShelf(frameW: frameW))
    r.scale = scale
    guard let cg = r.cgImage else { print("no cgImage"); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { print("no png"); return }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(cg.width)x\(cg.height)")
}

MainActor.assumeIsolated {
    render(frameW: 1920, scale: 1, to: "Apps/SeretTV/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets/Top Shelf Image.imageset/shelf@1x.png")
    render(frameW: 1920, scale: 2, to: "Apps/SeretTV/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets/Top Shelf Image.imageset/shelf@2x.png")
    render(frameW: 2320, scale: 1, to: "Apps/SeretTV/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets/Top Shelf Image Wide.imageset/shelf@1x.png")
    render(frameW: 2320, scale: 2, to: "Apps/SeretTV/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets/Top Shelf Image Wide.imageset/shelf@2x.png")
}
