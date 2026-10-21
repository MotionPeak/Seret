// Renders Seret's brand art (art.js) to PNG files through an offscreen WKWebView — the same
// WebKit canvas the art was designed in, with no third-party tooling.
//
//   swift Scripts/topshelf/render.swift <jobs.tsv>
//
// Each line of the jobs file is: kind <TAB> width <TAB> height <TAB> time <TAB> output.png
// (`kind` is a key of `ART` in art.js). Usually driven by render.sh.
import AppKit
import WebKit

struct Job { let kind: String; let w: Int; let h: Int; let t: Double; let out: URL }

let args = CommandLine.arguments
guard args.count == 2, let text = try? String(contentsOfFile: args[1], encoding: .utf8) else {
    FileHandle.standardError.write("usage: render.swift <jobs.tsv>\n".data(using: .utf8)!)
    exit(2)
}
let jobs: [Job] = text.split(separator: "\n").compactMap { line in
    let f = line.split(separator: "\t").map(String.init)
    guard f.count == 5, let w = Int(f[1]), let h = Int(f[2]), let t = Double(f[3]) else { return nil }
    return Job(kind: f[0], w: w, h: h, t: t, out: URL(fileURLWithPath: f[4]))
}
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

@MainActor
func run() async {
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
    web.loadFileURL(here.appendingPathComponent("render.html"), allowingReadAccessTo: here)
    while (try? await web.evaluateJavaScript("window.artReady === true")) as? Bool != true {
        try? await Task.sleep(for: .milliseconds(50))
    }
    let start = Date()
    for (i, job) in jobs.enumerated() {
        let js = "renderFrame('\(job.kind)', \(job.w), \(job.h), \(job.t))"
        do {
            guard let url = try await web.evaluateJavaScript(js) as? String,
                  let comma = url.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else {
                throw NSError(domain: "render", code: 1, userInfo: [NSLocalizedDescriptionKey: "no image for \(job.kind)"])
            }
            try FileManager.default.createDirectory(at: job.out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: job.out)
        } catch {
            FileHandle.standardError.write("render failed (\(job.kind) t=\(job.t)): \(error)\n".data(using: .utf8)!)
            exit(1)
        }
        if (i + 1) % 30 == 0 || i + 1 == jobs.count {
            print(String(format: "  %d/%d  (%.0fs)", i + 1, jobs.count, Date().timeIntervalSince(start)))
        }
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in await run() }
app.run()
