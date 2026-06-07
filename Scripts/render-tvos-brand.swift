// Renders the SeretTV app-icon layers + top-shelf banners by rendering the EXACT SwiftUI
// SeretMark (same as the iPhone/iPad app) via ImageRenderer, on a much darker near-black
// canvas. Run: swift Scripts/render-tvos-brand.swift
import SwiftUI
import AppKit

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex>>16)&0xFF)/255, green: Double((hex>>8)&0xFF)/255,
                  blue: Double(hex&0xFF)/255, opacity: alpha)
    }
}
let gold = Color(hex: 0xEBC11D), goldBright = Color(hex: 0xFDE98A), goldDeep = Color(hex: 0xC8930A)
let goldGlow = Color(hex: 0xEBC11D, alpha: 0.40)
let textSecondary = Color(hex: 0x9A9AA0)
let canvasDark = Color(hex: 0x050506)          // much darker than before
let markGradient = LinearGradient(colors: [goldBright, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)

// Exact copy of the app's mark (Apps/SeretTV/DesignSystem/Brand.swift).
struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w*0.32, y: h*0.24))
        p.addLine(to: CGPoint(x: w*0.32, y: h*0.76))
        p.addLine(to: CGPoint(x: w*0.78, y: h*0.50))
        p.closeSubpath()
        return p
    }
}
struct SeretMark: View {
    var glow: Bool = true
    var body: some View {
        GeometryReader { geo in
            let corner = geo.size.width * 0.14
            PlayTriangle()
                .fill(markGradient)
                .overlay(PlayTriangle().stroke(markGradient, style: StrokeStyle(lineWidth: corner, lineJoin: .round)))
                .shadow(color: glow ? goldGlow : .clear, radius: glow ? geo.size.width * 0.22 : 0)
                .shadow(color: glow ? goldGlow : .clear, radius: glow ? geo.size.width * 0.10 : 0)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

@MainActor func render<V: View>(_ view: V, _ w: CGFloat, _ h: CGFloat, _ path: String) {
    let r = ImageRenderer(content: view.frame(width: w, height: h))
    r.scale = 1
    r.isOpaque = false
    guard let img = r.cgImage else { print("FAILED \(path)"); return }
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

// Icon: transparent front layer = just the mark (exactly like mobile); back = near-black.
struct IconFront: View {
    var body: some View {
        GeometryReader { g in
            SeretMark().frame(width: g.size.height * 0.62)
                .frame(width: g.size.width, height: g.size.height)
        }
    }
}
struct IconBack: View { var body: some View { canvasDark } }

// Top-shelf: dark canvas + faint glow. Big horizontal lockup — the play mark on the LEFT,
// then SERET (large) above its Hebrew סֶרֶט, center-aligned. Sized large to fill the wide space.
struct TopShelf: View {
    let h: CGFloat
    var body: some View {
        ZStack {
            canvasDark
            RadialGradient(colors: [Color(hex: 0xEBC11D, alpha: 0.10), .clear],
                           center: .center, startRadius: 0, endRadius: h * 0.95)
            HStack(spacing: h * 0.08) {
                SeretMark().frame(width: h * 0.55)
                VStack(alignment: .center, spacing: h * 0.03) {
                    Text("SERET")
                        .font(.system(size: h * 0.32, weight: .heavy)).tracking(h * 0.02)
                        .foregroundStyle(gold).shadow(color: goldGlow, radius: h * 0.05)
                    Text("סֶרֶט")
                        .font(.system(size: h * 0.26, weight: .bold))
                        .foregroundStyle(gold).environment(\.layoutDirection, .rightToLeft)
                        .shadow(color: goldGlow, radius: h * 0.04)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

let base = "Apps/SeretTV/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
MainActor.assumeIsolated {
    render(IconBack(),  400, 240,  "\(base)/App Icon.imagestack/Back.imagestacklayer/Content.imageset/icon.png")
    render(IconFront(), 400, 240,  "\(base)/App Icon.imagestack/Front.imagestacklayer/Content.imageset/icon.png")
    render(IconBack(),  1280, 768, "\(base)/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/icon.png")
    render(IconFront(), 1280, 768, "\(base)/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/icon.png")
    render(TopShelf(h: 720),  1920, 720,  "\(base)/Top Shelf Image.imageset/shelf@1x.png")
    render(TopShelf(h: 1440), 3840, 1440, "\(base)/Top Shelf Image.imageset/shelf@2x.png")
    render(TopShelf(h: 720),  2320, 720,  "\(base)/Top Shelf Image Wide.imageset/shelf@1x.png")
    render(TopShelf(h: 1440), 4640, 1440, "\(base)/Top Shelf Image Wide.imageset/shelf@2x.png")
    print("done")
}
