import Foundation
import Vapor

/// The Phase 0 skeleton UI: a raw torrent list and an hls.js watch page. The real React UI is Plan 3.
func registerPlayerPages(_ app: Application) {
    // Home: fetch the torrent list and render play links.
    app.get { _ async throws -> Response in
        let html = """
        <!doctype html><meta charset=utf-8><title>Seret (skeleton)</title>
        <style>body{font:16px system-ui;background:#111;color:#eee;padding:24px}a{color:#e8b84b}</style>
        <h1>Seret — skeleton</h1><ul id=list><li>loading…</li></ul>
        <script>
          fetch('/api/torrents').then(r=>r.json()).then(items=>{
            document.getElementById('list').innerHTML =
              items.map(i=>`<li><a href="/watch?id=${encodeURIComponent(i.id)}">${i.filename}</a></li>`).join('');
          }).catch(e=>{document.getElementById('list').innerText='error: '+e});
        </script>
        """
        return htmlResponse(html)
    }

    // Watch: request a transcode session, then play the HLS with hls.js (Safari uses native HLS).
    app.get("watch") { req async throws -> Response in
        let id = try req.query.get(String.self, at: "id")
        let html = """
        <!doctype html><meta charset=utf-8><title>Seret — watch</title>
        <style>body{margin:0;background:#000}video{width:100vw;height:100vh}#msg{position:fixed;top:8px;left:8px;color:#e8b84b;font:14px system-ui}</style>
        <div id=msg>starting transcode…</div>
        <video id=v controls autoplay playsinline></video>
        <script src="https://cdn.jsdelivr.net/npm/hls.js@1"></script>
        <script>
          const id = \(encodeForJS(id));
          fetch('/api/play?id='+encodeURIComponent(id), {method:'POST'})
            .then(r=>r.json()).then(({url})=>{
              const v=document.getElementById('v'); document.getElementById('msg').innerText='';
              // hls.js FIRST. Chrome returns a truthy "maybe" from canPlayType(vnd.apple.mpegurl)
              // despite having no native HLS, so probing that first sent <video src> at the .m3u8
              // and Chrome died with DEMUXER_ERROR_COULD_NOT_PARSE. Native HLS is the Safari-only
              // fallback. (Verified live against the NAS: hls.js path plays, native path does not.)
              if (window.Hls && Hls.isSupported()) { const h=new Hls(); h.loadSource(url); h.attachMedia(v); }
              else if (v.canPlayType('application/vnd.apple.mpegurl')) { v.src=url; }
              else { document.getElementById('msg').innerText='HLS not supported in this browser'; }
            }).catch(e=>{document.getElementById('msg').innerText='error: '+e});
        </script>
        """
        return htmlResponse(html)
    }
}

private func htmlResponse(_ html: String) -> Response {
    let res = Response(status: .ok, body: .init(string: html))
    res.headers.contentType = .html
    return res
}

/// Minimal JSON-string encode so an RD id is embedded safely in the page script.
private func encodeForJS(_ s: String) -> String {
    (try? String(decoding: JSONEncoder().encode(s), as: UTF8.self)) ?? "\"\""
}
