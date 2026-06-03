#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = "Apps/SeretTV/Resources/Assets.xcassets"
let fm = FileManager.default

// Paths below are relative to the repo root. Fail loudly if run from elsewhere,
// rather than silently scattering the catalog into the wrong directory.
guard fm.fileExists(atPath: "Packages/DebridCore/Package.swift") else {
    fatalError("Run from the Seret repo root: swift Scripts/make-placeholder-assets.swift")
}

func write(_ rel: String, _ text: String) {
    let url = URL(fileURLWithPath: "\(root)/\(rel)")
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! text.data(using: .utf8)!.write(to: url)
}

func png(_ rel: String, _ w: Int, _ h: Int,
         bg: (Double, Double, Double), dot: Bool) {
    let url = URL(fileURLWithPath: "\(root)/\(rel)")
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let cs = CGColorSpaceCreateDeviceRGB()
    // Opaque (no alpha) — tvOS App Store icons must not have an alpha channel,
    // else actool warns and breaks the zero-warning bar.
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(red: bg.0, green: bg.1, blue: bg.2, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    if dot {
        let d = Double(min(w, h)) * 0.5
        ctx.setFillColor(red: 0.96, green: 0.78, blue: 0.30, alpha: 1)   // Seret amber
        ctx.fillEllipse(in: CGRect(x: (Double(w) - d) / 2, y: (Double(h) - d) / 2, width: d, height: d))
    }
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let info = #"{"author":"xcode","version":1}"#

// Catalog root
write("Contents.json", "{\n  \"info\" : \(info)\n}\n")

// --- App Icon brand-asset set ---
write("App Icon & Top Shelf Image.brandassets/Contents.json", """
{
  "assets" : [
    { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" },
    { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" },
    { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" },
    { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" }
  ],
  "info" : \(info)
}
""")

// Helper: a 2-layer imagestack (Back + Front), each layer a full-size image.
func imagestack(_ name: String, _ w: Int, _ h: Int) {
    let base = "App Icon & Top Shelf Image.brandassets/\(name).imagestack"
    write("\(base)/Contents.json", """
    {
      "info" : \(info),
      "layers" : [
        { "filename" : "Front.imagestacklayer" },
        { "filename" : "Back.imagestacklayer" }
      ]
    }
    """)
    for (layer, dot, bg) in [("Front", true, (0.08, 0.10, 0.13)),
                             ("Back", false, (0.05, 0.06, 0.08))] {
        let lp = "\(base)/\(layer).imagestacklayer"
        write("\(lp)/Contents.json", "{\n  \"info\" : \(info)\n}\n")
        write("\(lp)/Content.imageset/Contents.json", """
        {
          "images" : [ { "filename" : "icon.png", "idiom" : "tv", "scale" : "1x" } ],
          "info" : \(info)
        }
        """)
        png("\(lp)/Content.imageset/icon.png", w, h, bg: bg, dot: dot)
    }
}

imagestack("App Icon", 400, 240)
imagestack("App Icon - App Store", 1280, 768)

// Helper: a top-shelf imageset (1x + 2x).
func topShelf(_ name: String, _ w: Int, _ h: Int) {
    let base = "App Icon & Top Shelf Image.brandassets/\(name).imageset"
    write("\(base)/Contents.json", """
    {
      "images" : [
        { "filename" : "shelf@1x.png", "idiom" : "tv", "scale" : "1x" },
        { "filename" : "shelf@2x.png", "idiom" : "tv", "scale" : "2x" }
      ],
      "info" : \(info)
    }
    """)
    png("\(base)/shelf@1x.png", w, h, bg: (0.06, 0.07, 0.09), dot: true)
    png("\(base)/shelf@2x.png", w * 2, h * 2, bg: (0.06, 0.07, 0.09), dot: true)
}

topShelf("Top Shelf Image Wide", 2320, 720)
topShelf("Top Shelf Image", 1920, 720)

print("Wrote placeholder asset catalog to \(root)")
