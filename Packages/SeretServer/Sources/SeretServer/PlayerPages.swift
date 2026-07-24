import Foundation
import Vapor

/// The web face, styled to match the iOS/iPadOS app's "Gold Glass" look.
///
/// Every colour, radius, type size and spacing value below is ported verbatim from
/// `Apps/SeretMobile/DesignSystem/Theme.swift`, exposed as CSS custom properties. When Plan 3
/// swaps these inline pages for the React SPA, it reuses this same `:root` token block — the
/// tokens are the durable part, the markup is not.
func registerPlayerPages(_ app: Application) {
    app.get { _ async throws -> Response in htmlResponse(homePage) }

    app.get("item") { req async throws -> Response in
        let id = try req.query.get(String.self, at: "id")
        return htmlResponse(detailPage(itemID: id))
    }

    app.get("watch") { req async throws -> Response in
        let item = try? req.query.get(String.self, at: "item")
        let torrent = try? req.query.get(String.self, at: "id")
        guard item != nil || torrent != nil else { throw Abort(.badRequest, reason: "need ?item= or ?id=") }
        let version = (try? req.query.get(Int.self, at: "version")) ?? 0
        return htmlResponse(watchPage(item: item, torrent: torrent, version: version))
    }
}

// MARK: - Design tokens (mirrors Theme.swift)

private let tokens = """
:root{
  --gold:#EBC11D; --gold-light:#F6D24A; --gold-bright:#FDE98A; --gold-deep:#C8930A;
  --canvas:#08080A; --surface1:#141416; --surface2:#1C1C1F;
  --hairline:rgba(255,255,255,.09); --chip:rgba(255,255,255,.12);
  --text:#F5F5F7; --text2:#8A8A90; --text3:#5A5A60;
  --gold-grad:linear-gradient(135deg,var(--gold-light),var(--gold),var(--gold-deep));
  --xs:4px; --sm:8px; --md:12px; --lg:16px; --xl:20px; --xxl:24px; --xxxl:32px;
  --r-card:12px; --r-chip:8px; --r-pill:22px;
  --font:-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",system-ui,sans-serif;
  color-scheme:dark;
}
*{box-sizing:border-box}
html,body{margin:0;background:var(--canvas);color:var(--text);font-family:var(--font);
  -webkit-font-smoothing:antialiased}
/* canvasGlow: RadialGradient at (0.8,-0.05), gold @14%, radius 520 */
body::before{content:"";position:fixed;inset:0;pointer-events:none;z-index:0;
  background:radial-gradient(520px 520px at 80% -5%, rgba(235,193,29,.14), transparent 70%)}
.wrap{position:relative;z-index:1;max-width:1400px;margin:0 auto;padding:var(--xxl) var(--xl) 64px}
a{color:inherit;text-decoration:none}
.t-xl{font-size:30px;font-weight:800;letter-spacing:-.02em}
.t-title{font-size:22px;font-weight:700}
.t-head{font-size:17px;font-weight:600}
.t-body{font-size:15px;font-weight:400}
.t-label{font-size:12px;font-weight:600}
.t-cap{font-size:12px;font-weight:500;font-variant-numeric:tabular-nums}
.muted{color:var(--text2)} .faint{color:var(--text3)}
.chip{background:var(--chip);border-radius:var(--r-chip);padding:4px 10px;
  font-size:12px;font-weight:600;color:var(--text)}
.btn-gold{background:var(--gold-grad);color:#1A1400;border:0;border-radius:var(--r-pill);
  padding:12px 26px;font:600 17px var(--font);cursor:pointer;display:inline-flex;
  align-items:center;gap:var(--sm);transition:transform .18s cubic-bezier(.2,.8,.2,1)}
.btn-gold:hover{transform:scale(1.03)}
.btn-ghost{background:transparent;color:var(--gold);border:1px solid var(--hairline);
  border-radius:var(--r-pill);padding:10px 20px;font:600 15px var(--font);cursor:pointer}
"""

// MARK: - Home (poster grid)

private let homePage = """
<!doctype html><meta charset=utf-8><title>Seret</title>
<meta name=viewport content="width=device-width,initial-scale=1">
<style>
\(tokens)
.head{display:flex;align-items:baseline;gap:var(--md);margin-bottom:var(--xxl)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));
  gap:var(--xl) var(--lg)}
.card .poster{width:100%;aspect-ratio:2/3;border-radius:var(--r-card);background:var(--surface2)
  center/cover no-repeat;border:1px solid var(--hairline);display:flex;align-items:center;
  justify-content:center;text-align:center;padding:var(--sm);color:var(--text3);font-size:13px;
  transition:transform .3s cubic-bezier(.2,.8,.2,1),box-shadow .3s}
.card:hover .poster{transform:translateY(-4px) scale(1.02);
  box-shadow:0 14px 34px rgba(0,0,0,.55),0 0 0 1px rgba(235,193,29,.35)}
.card .ct{margin-top:var(--sm);font-size:14px;font-weight:600;line-height:1.25}
.card .cy{font-size:12px;font-weight:500;color:var(--text2);margin-top:2px}
.badge{display:inline-block;margin-top:var(--xs);font-size:11px;font-weight:600;color:var(--gold)}
</style>
<div class=wrap>
  <div class=head><div class=t-xl>Seret</div><div class="t-body muted" id=sub>loading…</div></div>
  <div class=grid id=grid></div>
</div>
<script>
fetch('/api/library').then(r=>r.json()).then(items=>{
  document.getElementById('sub').textContent = items.length + ' movies';
  document.getElementById('grid').innerHTML = items.map(i=>{
    const bg = i.posterPath ? `background-image:url(https://image.tmdb.org/t/p/w500${i.posterPath})` : '';
    const fallback = i.posterPath ? '' : i.title;
    const badge = i.versions.length > 1 ? `<div class=badge>${i.versions.length} versions</div>` : '';
    return `<a class=card href="/item?id=${encodeURIComponent(i.id)}">
      <div class=poster style="${bg}">${fallback}</div>
      <div class=ct>${i.title}</div>
      <div class=cy>${i.year || ''}</div>${badge}</a>`;
  }).join('');
}).catch(e=>{document.getElementById('sub').textContent = 'error: ' + e});
</script>
"""

// MARK: - Detail (backdrop hero → versions → Play)

private func detailPage(itemID: String) -> String {
    """
    <!doctype html><meta charset=utf-8><title>Seret</title>
    <meta name=viewport content="width=device-width,initial-scale=1">
    <style>
    \(tokens)
    .hero{position:relative;height:52vh;min-height:320px;background:var(--surface1) center/cover no-repeat}
    .hero::after{content:"";position:absolute;inset:0;
      background:linear-gradient(to bottom, rgba(8,8,10,.25) 0%, rgba(8,8,10,.75) 60%, var(--canvas) 100%)}
    .back{position:fixed;top:var(--lg);left:var(--lg);z-index:3;width:38px;height:38px;
      border-radius:50%;background:rgba(20,20,22,.75);backdrop-filter:blur(12px);
      border:1px solid var(--hairline);display:flex;align-items:center;justify-content:center;
      color:var(--gold);font-size:18px}
    .sheet{position:relative;z-index:2;margin-top:-140px}
    .meta{display:flex;flex-wrap:wrap;gap:var(--sm);align-items:center;margin:var(--md) 0 var(--lg)}
    .ov{max-width:720px;line-height:1.5;color:var(--text2);margin:0 0 var(--xl)}
    .sect{font-size:12px;font-weight:600;letter-spacing:1.5px;color:var(--gold);margin:var(--xxl) 0 var(--md)}
    .ver{display:flex;align-items:center;justify-content:space-between;gap:var(--md);
      background:var(--surface1);border:1px solid var(--hairline);border-radius:var(--r-card);
      padding:var(--md) var(--lg);margin-bottom:var(--sm);cursor:pointer;
      transition:border-color .2s,background .2s}
    .ver:hover{border-color:rgba(235,193,29,.5);background:var(--surface2)}
    .ver .go{color:var(--gold);font-size:18px}
    </style>
    <a class=back href="/">‹</a>
    <div class=hero id=hero></div>
    <div class="wrap sheet">
      <div class=t-xl id=title>…</div>
      <div class=meta id=meta></div>
      <p class="ov t-body" id=ov></p>
      <button class=btn-gold id=play>▶ Play</button>
      <div class=sect id=vsect style="display:none">VERSIONS</div>
      <div id=versions></div>
    </div>
    <script>
    const id = \(encodeForJS(itemID));
    fetch('/api/item/' + encodeURIComponent(id)).then(r=>r.json()).then(i=>{
      document.title = i.title + ' — Seret';
      document.getElementById('title').textContent = i.title;
      if (i.backdropPath)
        document.getElementById('hero').style.backgroundImage =
          `url(https://image.tmdb.org/t/p/w1280${i.backdropPath})`;
      else if (i.posterPath)
        document.getElementById('hero').style.backgroundImage =
          `url(https://image.tmdb.org/t/p/w780${i.posterPath})`;
      const bits = [];
      if (i.year) bits.push(`<span class=chip>${i.year}</span>`);
      i.versions.slice(0,4).forEach(v=>bits.push(`<span class=chip>${v.label}</span>`));
      document.getElementById('meta').innerHTML = bits.join('');
      document.getElementById('ov').textContent = i.overview || '';
      document.getElementById('play').onclick = () =>
        location.href = `/watch?item=${encodeURIComponent(i.id)}&version=0`;
      if (i.versions.length > 1) {
        document.getElementById('vsect').style.display = 'block';
        document.getElementById('versions').innerHTML = i.versions.map(v=>
          `<div class=ver onclick="location.href='/watch?item=${encodeURIComponent(i.id)}&version=${v.index}'">
             <div><div class=t-head>${v.label}</div>
                  <div class="t-cap muted">Version ${v.index + 1}</div></div>
             <div class=go>▶</div></div>`).join('');
      }
    }).catch(e=>{document.getElementById('title').textContent = 'error: ' + e});
    </script>
    """
}

// MARK: - Watch

private func watchPage(item: String?, torrent: String?, version: Int) -> String {
    """
    <!doctype html><meta charset=utf-8><title>Seret — watch</title>
    <meta name=viewport content="width=device-width,initial-scale=1">
    <style>
    \(tokens)
    body{background:#000}
    video{width:100vw;height:100vh;background:#000;display:block}
    .hud{position:fixed;top:var(--lg);left:var(--lg);z-index:3;display:flex;gap:var(--sm);
      align-items:center}
    .pill{background:rgba(20,20,22,.78);backdrop-filter:blur(12px);border:1px solid var(--hairline);
      border-radius:var(--r-pill);padding:7px 14px;font:600 12px var(--font);color:var(--gold)}
    .close{position:fixed;top:var(--lg);right:var(--lg);z-index:3;width:38px;height:38px;
      border-radius:50%;background:rgba(20,20,22,.78);backdrop-filter:blur(12px);
      border:1px solid var(--hairline);display:flex;align-items:center;justify-content:center;
      color:var(--gold);font-size:16px}
    </style>
    <div class=hud><div class=pill id=msg>preparing…</div></div>
    <a class=close href="/">✕</a>
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
          msg.textContent = mode === 'direct' ? 'Direct play' : 'Transcoding';
          setTimeout(() => { msg.parentElement.style.opacity = '0'; }, 2600);
          if (mode === 'direct') { v.src = url; return; }
          // hls.js FIRST: Chrome reports a truthy "maybe" for native HLS but cannot play it
          // (DEMUXER_ERROR_COULD_NOT_PARSE). Native HLS is the Safari-only fallback.
          if (window.Hls && Hls.isSupported()) { const h = new Hls(); h.loadSource(url); h.attachMedia(v); }
          else if (v.canPlayType('application/vnd.apple.mpegurl')) { v.src = url; }
          else { msg.textContent = 'HLS unsupported'; }
        })
        .catch(e => { msg.textContent = 'error: ' + e; });
    </script>
    """
}

// MARK: - Helpers

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
