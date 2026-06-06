import AppKit
import CoreGraphics

let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError() }
let full = CGRect(x: 0, y: 0, width: S, height: S)
// Opaque near-black background (no alpha; iOS masks corners itself).
ctx.setFillColor(CGColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)); ctx.fill(full)
// Top-center radial gold glow.
let glow = [CGColor(red: 0.92, green: 0.76, blue: 0.11, alpha: 0.30),
            CGColor(red: 0.92, green: 0.76, blue: 0.11, alpha: 0)] as CFArray
if let g = CGGradient(colorsSpace: cs, colors: glow, locations: [0, 1]) {
    let c = CGPoint(x: Double(S) * 0.5, y: Double(S) * 0.62)
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: Double(S) * 0.6, options: [])
}
// Play triangle (CG origin is bottom-left → flip y).
func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: Double(S) * x, y: Double(S) * (1 - y)) }
let tri = CGMutablePath()
tri.move(to: p(0.37, 0.27)); tri.addLine(to: p(0.37, 0.73)); tri.addLine(to: p(0.72, 0.50)); tri.closeSubpath()
let rounded = tri.copy(strokingWithWidth: Double(S) * 0.085, lineCap: .round, lineJoin: .round, miterLimit: 10)
// Halo + solid base.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: Double(S) * 0.055,
              color: CGColor(red: 0.92, green: 0.76, blue: 0.11, alpha: 0.7))
ctx.addPath(tri); ctx.addPath(rounded)
ctx.setFillColor(CGColor(red: 0.92, green: 0.76, blue: 0.11, alpha: 1)); ctx.fillPath()
ctx.restoreGState()
// Gradient sheen on top.
ctx.saveGState(); ctx.addPath(tri); ctx.addPath(rounded); ctx.clip()
let gold = [CGColor(red: 0.99, green: 0.91, blue: 0.54, alpha: 1),
            CGColor(red: 0.78, green: 0.58, blue: 0.04, alpha: 1)] as CFArray
if let g = CGGradient(colorsSpace: cs, colors: gold, locations: [0, 1]) {
    ctx.drawLinearGradient(g, start: p(0.37, 0.73), end: p(0.72, 0.30), options: [])
}
ctx.restoreGState()
guard let image = ctx.makeImage() else { fatalError() }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
