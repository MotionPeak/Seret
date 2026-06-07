// Renders the SeretTV app-icon layers + top-shelf banners from the Gold Glass design
// (gold play-triangle mark + סֶרֶט/SERET wordmark). Run: swift Scripts/render-tvos-brand.swift
import AppKit

let rgb = CGColorSpaceCreateDeviceRGB()
func hex(_ h: UInt, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: rgb, components: [CGFloat((h>>16)&0xFF)/255, CGFloat((h>>8)&0xFF)/255, CGFloat(h&0xFF)/255, a])!
}
let canvas = hex(0x08080A), gold = hex(0xEBC11D), goldLight = hex(0xF6D24A),
    goldBright = hex(0xFDE98A), goldDeep = hex(0xC8930A)

func makeCtx(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func save(_ c: CGContext, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

/// Rounded play triangle (matches SwiftUI PlayTriangle; CG y is bottom-up so y is flipped).
func playTriangle(in r: CGRect) -> CGPath {
    let p = CGMutablePath()
    let w = r.width, h = r.height, x = r.minX, y = r.minY
    p.move(to: CGPoint(x: x + w*0.32, y: y + h*(1-0.24)))
    p.addLine(to: CGPoint(x: x + w*0.32, y: y + h*(1-0.76)))
    p.addLine(to: CGPoint(x: x + w*0.78, y: y + h*(1-0.50)))
    p.closeSubpath()
    return p
}
func drawMark(_ c: CGContext, _ rect: CGRect, glow: Bool) {
    let tri = playTriangle(in: rect)
    if glow {
        c.saveGState()
        c.setShadow(offset: .zero, blur: rect.width*0.16, color: hex(0xEBC11D, 0.65))
        c.addPath(tri); c.setFillColor(gold); c.fillPath()
        c.restoreGState()
    }
    let grad = CGGradient(colorsSpace: rgb, colors: [goldBright, goldDeep] as CFArray, locations: [0,1])!
    c.saveGState(); c.addPath(tri); c.clip()
    c.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY),
                         end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    c.restoreGState()
    c.saveGState()
    c.addPath(tri); c.setLineWidth(rect.width*0.14); c.setLineJoin(.round)
    c.setStrokeColor(goldLight); c.strokePath()
    c.restoreGState()
}
func drawText(_ c: CGContext, _ s: String, size: CGFloat, weight: NSFont.Weight,
              color col: CGColor, center: CGPoint, tracking: CGFloat = 0, glow: CGColor? = nil) {
    let ns = NSGraphicsContext(cgContext: c, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    if let g = glow { c.setShadow(offset: .zero, blur: size*0.5, color: g) }
    let para = NSMutableParagraphStyle(); para.alignment = .center
    var attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: col)!, .paragraphStyle: para]
    if tracking != 0 { attrs[.kern] = tracking }
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    str.draw(at: CGPoint(x: center.x - sz.width/2, y: center.y - sz.height/2))
    NSGraphicsContext.restoreGraphicsState()
}
func darkGlowBG(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    c.setFillColor(canvas); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let g = CGGradient(colorsSpace: rgb, colors: [hex(0xEBC11D, 0.30), hex(0xEBC11D, 0)] as CFArray, locations: [0,1])!
    let center = CGPoint(x: w/2, y: h*0.52)
    c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: max(w,h)*0.6, options: [])
}

// MARK: app-icon layers (gold mark + SERET lockup over a dark gold-glow back)
func iconBack(_ w: Int, _ h: Int, _ path: String) {
    let c = makeCtx(w, h); darkGlowBG(c, CGFloat(w), CGFloat(h)); save(c, path)
}
func iconFront(_ w: Int, _ h: Int, _ path: String) {
    let c = makeCtx(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    let mh = H * 0.42
    let mark = CGRect(x: W*0.5 - mh*0.5, y: H*0.50, width: mh, height: mh)
    drawMark(c, mark, glow: true)
    drawText(c, "SERET", size: H*0.13, weight: .heavy, color: gold,
             center: CGPoint(x: W*0.5, y: H*0.26), tracking: H*0.03, glow: hex(0xEBC11D, 0.5))
    save(c, path)
}

// MARK: top-shelf banner (mark + סֶרֶט + SERET, big & centered)
func topShelf(_ w: Int, _ h: Int, _ path: String) {
    let c = makeCtx(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    darkGlowBG(c, W, H)
    let mh = H * 0.30
    drawMark(c, CGRect(x: W*0.5 - mh*0.5, y: H*0.60, width: mh, height: mh), glow: true)
    drawText(c, "סֶרֶט", size: H*0.26, weight: .bold, color: gold,
             center: CGPoint(x: W*0.5, y: H*0.36), tracking: 0, glow: hex(0xEBC11D, 0.55))
    drawText(c, "SERET", size: H*0.075, weight: .semibold, color: hex(0x9A9AA0),
             center: CGPoint(x: W*0.5, y: H*0.14), tracking: H*0.05)
    save(c, path)
}

let base = "Apps/SeretTV/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
iconBack(400, 240,  "\(base)/App Icon.imagestack/Back.imagestacklayer/Content.imageset/icon.png")
iconFront(400, 240, "\(base)/App Icon.imagestack/Front.imagestacklayer/Content.imageset/icon.png")
iconBack(1280, 768,  "\(base)/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/icon.png")
iconFront(1280, 768, "\(base)/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/icon.png")
topShelf(1920, 720,  "\(base)/Top Shelf Image.imageset/shelf@1x.png")
topShelf(3840, 1440, "\(base)/Top Shelf Image.imageset/shelf@2x.png")
topShelf(2320, 720,  "\(base)/Top Shelf Image Wide.imageset/shelf@1x.png")
topShelf(4640, 1440, "\(base)/Top Shelf Image Wide.imageset/shelf@2x.png")
print("done")
