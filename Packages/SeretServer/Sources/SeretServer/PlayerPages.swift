import Foundation
import Vapor

/// Interim UI: a TMDB poster grid + a player page. Plan 3 replaces both with the React app,
/// so this deliberately stays a couple of inline pages with no build step.
func registerPlayerPages(_ app: Application) {
    // Home: the organized library as a poster grid.
    app.get { _ async throws -> Response in
        let html = """
        <!doctype html><meta charset=utf-8><title>Seret</title>
        <meta name=viewport content="width=device-width,initial-scale=1">
        <style>
          :root{color-scheme:dark}
          body{margin:0;background:#0d0d0f;color:#eee;font:16px/1.4 system-ui,-apple-system,sans-serif;padding:28px}
          h1{font-size:22px;letter-spacing:.02em;margin:0 0 4px}
          .sub{color:#8a8a92;font-size:14px;margin-bottom:24px}
          .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:20px}
          a.card{text-decoration:none;color:inherit;display:block}
          .poster{width:100%;aspect-ratio:2/3;border-radius:10px;background:#1c1c20 center/cover no-repeat;
                  display:flex;align-items:center;justify-content:center;text-align:center;padding:8px;
                  box-sizing:border-box;font-size:13px;color:#6f6f78;transition:transform .12s ease}
          a.card:hover .poster{transform:scale(1.04)}
          .t{font-size:13px;margin-top:8px;line-height:1.25}
          .y{color:#7a7a83;font-size:12px}
          .v{color:#e8b84b;font-size:11px;margin-top:2px}
        </style>
        <h1>Seret</h1><div class=sub id=sub>loading library…</div>
        <div class=grid id=grid></div>
        <script>
          fetch('/api/library').then(r=>r.json()).then(items=>{
            document.getElementById('sub').textContent = items.length + ' movies';
            document.getElementById('grid').innerHTML = items.map(i=>{
              const img = i.posterPath ? `background-image:url(https://image.tmdb.org/t/p/w342${i.posterPath})` : '';
              const label = i.posterPath ? '' : i.title;
              const vers = i.versions.length > 1 ? `<div class=v>${i.versions.length} versions</div>` : '';
              return `<a class=card href="/watch?item=${encodeURIComponent(i.id)}">
                        <div class=poster style="${img}">${label}</div>
                        <div class=t>${i.title}</div>
                        <div class=y>${i.year || ''}</div>${vers}
                      </a>`;
            }).join('');
          }).catch(e=>{document.getElementById('sub').textContent='error: '+e});
        </script>
        """
        return htmlResponse(html)
    }

    // Watch: ask the server how to play it, then either play the file directly or via hls.js.
    app.get("watch") { req async throws -> Response in
        let item = try? req.query.get(String.self, at: "item")
        let torrent = try? req.query.get(String.self, at: "id")
        guard item != nil || torrent != nil else { throw Abort(.badRequest, reason: "need ?item= or ?id=") }
        let version = (try? req.query.get(Int.self, at: "version")) ?? 0
        let html = """
        <!doctype html><meta charset=utf-8><title>Seret — watch</title>
        <meta name=viewport content="width=device-width,initial-scale=1">
        <style>
          :root{color-scheme:dark}
          body{margin:0;background:#000}video{width:100vw;height:100vh;background:#000}
          #msg{position:fixed;top:10px;left:12px;color:#e8b84b;font:14px system-ui;z-index:2}
          #back{position:fixed;top:10px;right:14px;color:#e8b84b;font:16px system-ui;z-index:2;text-decoration:none}
        </style>
        <div id=msg>preparing…</div><a id=back href="/">✕</a>
        <video id=v controls autoplay playsinline></video>
        <script src="https://cdn.jsdelivr.net/npm/hls.js@1"></script>
        <script>
          const item = \(encodeForJS(item)), torrent = \(encodeForJS(torrent)), version = \(version);
          const q = item ? ('item=' + encodeURIComponent(item) + '&version=' + version)
                         : ('id=' + encodeURIComponent(torrent));
          const msg = document.getElementById('msg');
          fetch('/api/play?' + q, {method:'POST'})
            .then(r => r.ok ? r.json() : r.text().then(t => Promise.reject(t)))
            .then(({mode, url}) => {
              const v = document.getElementById('v');
              msg.textContent = mode === 'direct' ? 'direct play' : 'transcoding';
              setTimeout(() => { msg.textContent = ''; }, 2500);
              if (mode === 'direct') { v.src = url; return; }
              // hls.js FIRST: Chrome reports a truthy "maybe" for native HLS but cannot actually
              // play it (DEMUXER_ERROR_COULD_NOT_PARSE). Native is the Safari-only fallback.
              if (window.Hls && Hls.isSupported()) { const h = new Hls(); h.loadSource(url); h.attachMedia(v); }
              else if (v.canPlayType('application/vnd.apple.mpegurl')) { v.src = url; }
              else { msg.textContent = 'HLS not supported in this browser'; }
            })
            .catch(e => { msg.textContent = 'error: ' + e; });
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

/// JSON-encode an optional string so it embeds safely (and becomes `null` when absent).
private func encodeForJS(_ s: String?) -> String {
    guard let s else { return "null" }
    return (try? String(decoding: JSONEncoder().encode(s), as: UTF8.self)) ?? "null"
}
