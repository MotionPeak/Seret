// Renders the macOS app icon set: a dark squircle on Apple's icon grid (824 pt body on a 1024 pt
// canvas) with the gold glow and the gold play mark, at every size the asset catalog wants.
// Usage: swift Scripts/generate-mac-icon.swift Apps/SeretMac/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : "Apps/SeretMac/Resources/Assets.xcassets/AppIcon.appiconset"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func renderMaster() -> CGImage {
    let size = 1024.0
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    // Drop shadow under the body, like every macOS icon.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(squircle); ctx.setFillColor(CGColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    // Body: vertical near-black gradient, a gold glow, a faint rim.
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1),
                                                  CGColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
    let glow = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.92, green: 0.76, blue: 0.11, alpha: 0.32),
                                                    CGColor(red: 0.92, green: 0.76, blue: 0.11, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    let centre = CGPoint(x: size * 0.5, y: size * 0.56)
    ctx.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: size * 0.45, options: [])
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); ctx.setLineWidth(3); ctx.strokePath(); ctx.restoreGState()
    // The mark (CG origin is bottom-left, so y is flipped).
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: size * x, y: size * (1 - y)) }
    let tri = CGMutablePath()
    tri.move(to: p(0.40, 0.31)); tri.addLine(to: p(0.40, 0.69)); tri.addLine(to: p(0.70, 0.50)); tri.closeSubpath()
    let rounded = tri.copy(strokingWithWidth: size * 0.075, lineCap: .round, lineJoin: .round, miterLimit: 10)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: size * 0.05, color: CGColor(red: 0.92, green: 0.76, blue: 0.11, alpha: 0.7))
    ctx.addPath(tri); ctx.addPath(rounded)
    ctx.setFillColor(CGColor(red: 0.92, green: 0.76, blue: 0.11, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(tri); ctx.addPath(rounded); ctx.clip()
    let gold = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.99, green: 0.91, blue: 0.54, alpha: 1),
                                                    CGColor(red: 0.78, green: 0.58, blue: 0.04, alpha: 1)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(gold, start: p(0.40, 0.69), end: p(0.70, 0.35), options: [])
    ctx.restoreGState()
    return ctx.makeImage()!
}

func resized(_ image: CGImage, to pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return ctx.makeImage()!
}

let master = renderMaster()
var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let rep = NSBitmapImageRep(cgImage: resized(master, to: points * scale))
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
        entries.append(#"{ "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(points)x\#(points)" }"#)
    }
}
let json = "{\n  \"images\" : [\n    " + entries.joined(separator: ",\n    ") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try! json.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("wrote \(entries.count) icon images to \(outDir)")
