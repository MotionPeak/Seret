import Foundation
import Vapor

/// The web face, styled to match the iOS/iPadOS app's "Gold Glass" look.
///
/// Colours, radii, type sizes and spacing are ported from the app's `Theme.swift` into the
/// `:root` token block. Navigation is responsive: a left sidebar (iPad `NavigationSplitView`) on
/// wide viewports, collapsing to the iPhone's floating bottom tab bar on narrow ones. The detail
/// page mirrors the native title page (meta line, ratings, versions, cast, more-like-this).
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
body::before{content:"";position:fixed;inset:0;pointer-events:none;z-index:0;
  background:radial-gradient(560px 560px at 82% -6%, rgba(235,193,29,.14), transparent 70%)}
a{color:inherit;text-decoration:none}
.t-xl{font-size:clamp(28px,5vw,40px);font-weight:800;letter-spacing:-.02em;line-height:1.05}
.t-title{font-size:22px;font-weight:700}
.muted{color:var(--text2)} .faint{color:var(--text3)}
/* gold uppercase section header, e.g. RECENTLY ADDED / CAST / MORE LIKE THIS */
.sect{font-size:13px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;
  color:var(--gold);margin:var(--xxl) 0 var(--md)}
.chip{background:var(--chip);border-radius:var(--r-chip);padding:5px 11px;
  font-size:12px;font-weight:600;color:var(--text);white-space:nowrap}
.btn-gold{background:var(--gold-grad);color:#1A1400;border:0;border-radius:var(--r-pill);
  padding:13px 30px;font:700 17px var(--font);cursor:pointer;display:inline-flex;
  align-items:center;gap:var(--sm);box-shadow:0 8px 26px rgba(235,193,29,.28);
  transition:transform .18s cubic-bezier(.2,.8,.2,1)}
.btn-gold:hover{transform:scale(1.03)}
.btn-ghost{background:rgba(255,255,255,.08);color:var(--text);border:1px solid var(--hairline);
  border-radius:var(--r-pill);padding:12px 22px;font:600 15px var(--font);cursor:pointer;
  display:inline-flex;align-items:center;gap:var(--sm)}
.btn-ghost:hover{background:rgba(255,255,255,.14)}
/* poster card — shared by every grid + rail */
.card .poster{width:100%;aspect-ratio:2/3;border-radius:var(--r-card);background:var(--surface2)
  center/cover no-repeat;border:1px solid var(--hairline);display:flex;align-items:center;
  justify-content:center;text-align:center;padding:var(--sm);color:var(--text3);font-size:13px;
  overflow:hidden;transition:transform .3s cubic-bezier(.2,.8,.2,1),box-shadow .3s}
.card:hover .poster{transform:translateY(-4px) scale(1.02);
  box-shadow:0 14px 34px rgba(0,0,0,.55),0 0 0 1px rgba(235,193,29,.35)}
.card .ct{margin-top:var(--sm);font-size:14px;font-weight:600;line-height:1.25}
.card .cy{font-size:12px;font-weight:500;color:var(--text2);margin-top:2px}
.badge{display:inline-block;margin-top:var(--xs);font-size:11px;font-weight:600;color:var(--gold)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:var(--xl) var(--lg)}
.rail{display:flex;gap:var(--lg);overflow-x:auto;padding-bottom:var(--sm);scroll-snap-type:x proximity}
.rail::-webkit-scrollbar{height:0}
.rail .card{flex:0 0 132px;scroll-snap-align:start}
"""

// MARK: - Home (sidebar / bottom-bar shell → hero + rails)

private let homePage = """
<!doctype html><meta charset=utf-8><title>Seret</title>
<meta name=viewport content="width=device-width,initial-scale=1">
<style>
\(tokens)
.app{display:flex;min-height:100vh}
/* sidebar (wide) */
.side{position:sticky;top:0;height:100vh;width:230px;flex:0 0 230px;padding:var(--xxl) var(--lg);
  border-right:1px solid var(--hairline);background:rgba(20,20,22,.35);backdrop-filter:blur(20px);
  display:flex;flex-direction:column;gap:2px;z-index:5}
.brand{font-size:24px;font-weight:800;letter-spacing:-.02em;margin:var(--xs) 0 var(--xxl) var(--sm);
  background:var(--gold-grad);-webkit-background-clip:text;background-clip:text;color:transparent}
.navitem{display:flex;align-items:center;gap:var(--md);padding:11px var(--md);border-radius:10px;
  color:var(--text2);font-size:15px;font-weight:600;cursor:pointer;transition:background .15s,color .15s}
.navitem:hover{color:var(--text);background:rgba(255,255,255,.05)}
.navitem.active{background:var(--chip);color:var(--gold)}
.navitem .ic{width:22px;text-align:center;font-size:16px}
.main{flex:1;min-width:0;padding:var(--xxl) var(--xxxl) 96px;max-width:1500px}
/* bottom tab bar (narrow) — the iPhone floating pill */
.tabbar{display:none}
.sec{display:none} .sec.on{display:block;animation:fade .25s ease}
@keyframes fade{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:none}}
.pagehead{display:flex;align-items:center;justify-content:space-between;margin-bottom:var(--xl)}
.avatar{width:42px;height:42px;border-radius:50%;background:var(--gold-grad);display:flex;
  align-items:center;justify-content:center;font-size:20px;box-shadow:0 4px 14px rgba(235,193,29,.35)}
/* featured hero */
.hero{position:relative;border-radius:var(--r-card);overflow:hidden;min-height:340px;
  display:flex;align-items:flex-end;background:var(--surface1) center/cover no-repeat;
  margin-bottom:var(--sm)}
.hero::after{content:"";position:absolute;inset:0;background:
  linear-gradient(to top,rgba(8,8,10,.92) 0%,rgba(8,8,10,.35) 46%,rgba(8,8,10,.15) 100%),
  linear-gradient(to right,rgba(8,8,10,.7),transparent 60%)}
.hero .in{position:relative;z-index:1;padding:var(--xxl) var(--xxxl);max-width:640px}
.hero .eyebrow{color:var(--gold);font-size:13px;font-weight:700;letter-spacing:1px;
  text-transform:uppercase;margin-bottom:var(--sm)}
.hero .htitle{font-size:clamp(28px,4vw,46px);font-weight:800;letter-spacing:-.02em;margin-bottom:var(--md)}
.hero .hrow{display:flex;gap:var(--md);flex-wrap:wrap;align-items:center;margin-top:var(--lg)}
/* search */
.search{width:100%;max-width:560px;background:var(--surface1);border:1px solid var(--hairline);
  border-radius:var(--r-pill);padding:13px var(--lg);color:var(--text);font:15px var(--font);
  margin-bottom:var(--xl);outline:none}
.search:focus{border-color:rgba(235,193,29,.5);box-shadow:0 0 0 3px rgba(235,193,29,.12)}
.count{margin-bottom:var(--lg);color:var(--text2);font-size:14px}
/* segmented Movies / TV */
.seg{display:inline-flex;background:var(--surface2);border-radius:var(--r-pill);padding:3px;
  margin-bottom:var(--xl)}
.seg button{border:0;background:transparent;color:var(--text2);font:600 15px var(--font);
  padding:8px 26px;border-radius:var(--r-pill);cursor:pointer;transition:background .2s,color .2s}
.seg button.on{background:rgba(255,255,255,.14);color:var(--text)}
.empty{color:var(--text3);font-size:15px;padding:var(--xxxl) 0}
@media(max-width:900px){
  .side{display:none}
  .main{padding:var(--lg) var(--lg) 110px;max-width:none}
  .tabbar{display:flex;position:fixed;left:50%;transform:translateX(-50%);bottom:18px;z-index:20;
    gap:var(--xs);padding:8px;background:rgba(24,24,27,.72);backdrop-filter:blur(22px) saturate(1.4);
    border:1px solid var(--hairline);border-radius:30px;box-shadow:0 10px 34px rgba(0,0,0,.5)}
  .tab{display:flex;flex-direction:column;align-items:center;gap:3px;padding:8px 20px;border-radius:22px;
    color:var(--text2);font-size:11px;font-weight:600;cursor:pointer}
  .tab .ic{font-size:19px}
  .tab.active{color:var(--gold)}
  .hero{min-height:260px}
  .hero .in{padding:var(--xl)}
}
</style>
<div class=app>
  <nav class=side>
    <div class=brand>Seret</div>
    <div class="navitem active" data-tab=home><span class=ic>⌂</span><span>Home</span></div>
    <div class=navitem data-tab=find><span class=ic>⌕</span><span>Find</span></div>
    <div class=navitem data-tab=library><span class=ic>▤</span><span>My Library</span></div>
  </nav>
  <main class=main>
    <section class="sec on" id=home>
      <div class=pagehead><div class=t-xl>Home</div><div class=avatar>🍿</div></div>
      <div class=hero id=hero></div>
      <div class=sect>Recently Added</div>
      <div class=rail id=recent></div>
      <div class=sect>All Movies</div>
      <div class=grid id=homegrid></div>
    </section>
    <section class=sec id=find>
      <div class=pagehead><div class=t-xl>Find</div></div>
      <input class=search id=q placeholder="Search your library…" autocomplete=off>
      <div class=count id=findcount></div>
      <div class=grid id=findgrid></div>
    </section>
    <section class=sec id=library>
      <div class=pagehead><div class=t-xl>My Library</div></div>
      <div class=seg><button class=on id=segMovies>Movies</button><button id=segTV>TV</button></div>
      <div class=count id=libcount>loading…</div>
      <div class=grid id=libgrid></div>
      <div class=empty id=libtv style=display:none>No shows in your library yet.</div>
    </section>
  </main>
  <nav class=tabbar>
    <div class="tab active" data-tab=home><span class=ic>⌂</span><span>Home</span></div>
    <div class=tab data-tab=find><span class=ic>⌕</span><span>Find</span></div>
    <div class=tab data-tab=library><span class=ic>▤</span><span>My Library</span></div>
  </nav>
</div>
<script>
const IMG = (p,s)=> p ? `https://image.tmdb.org/t/p/${s}${p}` : '';
const card = i => {
  const bg = i.posterPath ? `background-image:url(${IMG(i.posterPath,'w500')})` : '';
  const fb = i.posterPath ? '' : i.title;
  const badge = i.versions && i.versions.length > 1 ? `<div class=badge>${i.versions.length} versions</div>` : '';
  return `<a class=card href="/item?id=${encodeURIComponent(i.id)}">
    <div class=poster style="${bg}">${fb}</div>
    <div class=ct>${i.title}</div><div class=cy>${i.year||''}</div>${badge}</a>`;
};
let ALL = [];
fetch('/api/library').then(r=>r.json()).then(items=>{
  ALL = items;
  const recent = [...items].filter(i=>i.addedAt).sort((a,b)=>b.addedAt-a.addedAt);
  const feat = recent[0] || items[0];
  if (feat) {
    const h = document.getElementById('hero');
    if (feat.backdropPath) h.style.backgroundImage = `url(${IMG(feat.backdropPath,'w1280')})`;
    else if (feat.posterPath) h.style.backgroundImage = `url(${IMG(feat.posterPath,'w780')})`;
    const v = (feat.versions && feat.versions[0]) ? feat.versions[0].index : 0;
    h.innerHTML = `<div class=in>
      <div class=eyebrow>Recently Added</div>
      <div class=htitle>${feat.title}</div>
      <div class="muted">${feat.year||''}</div>
      <div class=hrow>
        <a class=btn-gold href="/watch?item=${encodeURIComponent(feat.id)}&version=${v}">▶ Play</a>
        <a class=btn-ghost href="/item?id=${encodeURIComponent(feat.id)}">Details</a>
      </div></div>`;
  }
  document.getElementById('recent').innerHTML = (recent.length?recent:items).slice(0,18).map(card).join('');
  document.getElementById('homegrid').innerHTML = items.map(card).join('');
  document.getElementById('libgrid').innerHTML = items.map(card).join('');
  document.getElementById('libcount').textContent = items.length + ' movies';
}).catch(e=>{document.getElementById('libcount').textContent = 'error: ' + e});

// tab switching — sidebar items and bottom-bar tabs share data-tab
document.querySelectorAll('[data-tab]').forEach(n=>n.onclick=()=>{
  const t = n.dataset.tab;
  document.querySelectorAll('[data-tab]').forEach(x=>x.classList.toggle('active', x.dataset.tab===t));
  document.querySelectorAll('.sec').forEach(s=>s.classList.toggle('on', s.id===t));
  if (t==='find') document.getElementById('q').focus();
  window.scrollTo(0,0);
});

// segmented Movies / TV
document.getElementById('segMovies').onclick = () => setSeg(true);
document.getElementById('segTV').onclick = () => setSeg(false);
function setSeg(movies){
  document.getElementById('segMovies').classList.toggle('on', movies);
  document.getElementById('segTV').classList.toggle('on', !movies);
  document.getElementById('libgrid').style.display = movies ? '' : 'none';
  document.getElementById('libcount').style.display = movies ? '' : 'none';
  document.getElementById('libtv').style.display = movies ? 'none' : '';
}

// find
const q = document.getElementById('q');
q.oninput = () => {
  const term = q.value.trim().toLowerCase();
  const res = term ? ALL.filter(i=>i.title.toLowerCase().includes(term)) : ALL;
  document.getElementById('findcount').textContent =
    term ? `${res.length} result${res.length===1?'':'s'}` : `${ALL.length} movies`;
  document.getElementById('findgrid').innerHTML = res.map(card).join('');
};
</script>
"""

// MARK: - Detail (rich title page: meta · ratings · play · versions · cast · more-like-this)

private func detailPage(itemID: String) -> String {
    """
    <!doctype html><meta charset=utf-8><title>Seret</title>
    <meta name=viewport content="width=device-width,initial-scale=1">
    <style>
    \(tokens)
    .stick{position:fixed;top:0;left:0;right:0;z-index:6;display:flex;align-items:center;gap:var(--md);
      padding:var(--md) var(--lg);background:rgba(8,8,10,0);backdrop-filter:blur(0);
      transition:background .25s,backdrop-filter .25s;pointer-events:none}
    .stick.on{background:rgba(12,12,14,.72);backdrop-filter:blur(18px);
      border-bottom:1px solid var(--hairline);pointer-events:auto}
    .stick .st{font-weight:700;font-size:17px;opacity:0;transition:opacity .25s}
    .stick.on .st{opacity:1}
    .circ{width:40px;height:40px;flex:0 0 40px;border-radius:50%;background:rgba(20,20,22,.75);
      backdrop-filter:blur(12px);border:1px solid var(--hairline);display:flex;align-items:center;
      justify-content:center;color:var(--gold);font-size:20px;pointer-events:auto;cursor:pointer}
    .hero{position:relative;height:56vh;min-height:340px;background:var(--surface1) center/cover no-repeat}
    .hero::after{content:"";position:absolute;inset:0;background:
      linear-gradient(to bottom,rgba(8,8,10,.15) 0%,rgba(8,8,10,.7) 62%,var(--canvas) 100%)}
    .wrap{position:relative;z-index:1;max-width:1100px;margin:0 auto;padding:0 var(--xl) 96px}
    .sheet{margin-top:-150px;position:relative;z-index:2}
    .meta{color:var(--text2);font-size:15px;margin:var(--md) 0 var(--lg);line-height:1.5}
    .rates{display:flex;gap:var(--lg);align-items:center;flex-wrap:wrap;margin:0 0 var(--lg)}
    .rate{display:inline-flex;align-items:center;gap:6px;font-size:15px;font-weight:600}
    .rate .imdb{background:var(--gold);color:#1A1400;font-weight:800;font-size:11px;
      padding:2px 6px;border-radius:4px;letter-spacing:.3px}
    .rate .mc{background:#66aa33;color:#06240a;font-weight:800;font-size:12px;padding:1px 6px;border-radius:4px}
    .rate .lbl{color:var(--text2);font-weight:500;font-size:13px}
    .chips{display:flex;gap:var(--sm);flex-wrap:wrap;margin:0 0 var(--xl)}
    .actions{display:flex;gap:var(--md);flex-wrap:wrap;align-items:center;margin-bottom:var(--xl)}
    .ov{max-width:760px;line-height:1.6;color:var(--text2);margin:var(--md) 0 0}
    .ver{display:flex;align-items:center;justify-content:space-between;gap:var(--md);
      background:var(--surface1);border:1px solid var(--hairline);border-radius:var(--r-card);
      padding:var(--md) var(--lg);margin-bottom:var(--sm);cursor:pointer;
      transition:border-color .2s,background .2s}
    .ver:hover{border-color:rgba(235,193,29,.5);background:var(--surface2)}
    .ver .vlabel{font-weight:600}
    .ver .go{color:var(--gold);font-size:20px}
    /* cast rail */
    .castrail{display:flex;gap:var(--lg);overflow-x:auto;padding-bottom:var(--sm)}
    .castrail::-webkit-scrollbar{height:0}
    .cast{flex:0 0 96px;text-align:center}
    .cast .face{width:96px;height:96px;border-radius:50%;object-fit:cover;background:var(--surface2)
      center/cover no-repeat;border:1px solid var(--hairline);display:flex;align-items:center;
      justify-content:center;color:var(--text3);font-size:26px;font-weight:700}
    .cast .nm{margin-top:var(--sm);font-size:13px;font-weight:600;line-height:1.2}
    .cast .ch{font-size:12px;color:var(--text2);margin-top:2px;line-height:1.2}
    .staticcard{flex:0 0 132px}
    .staticcard .poster{width:100%;aspect-ratio:2/3;border-radius:var(--r-card);
      background:var(--surface2) center/cover no-repeat;border:1px solid var(--hairline)}
    </style>
    <div class=stick id=stick><div class=circ onclick="history.length>1?history.back():location.href='/'">‹</div>
      <div class=st id=stitle></div></div>
    <div class=hero id=hero></div>
    <div class="wrap sheet">
      <div class=t-xl id=title>…</div>
      <div class=meta id=meta></div>
      <div class=rates id=rates></div>
      <div class=chips id=chips></div>
      <div class=actions id=actions></div>
      <p class="ov" id=ov></p>
      <div class=sect id=vsect style=display:none>Versions</div>
      <div id=versions></div>
      <div class=sect id=csect style=display:none>Cast</div>
      <div class=castrail id=cast></div>
      <div class=sect id=ssect style=display:none>More Like This</div>
      <div class=rail id=similar></div>
    </div>
    <script>
    const IMG = (p,s)=> p ? `https://image.tmdb.org/t/p/${s}${p}` : '';
    const runtime = m => m ? (m>=60 ? `${Math.floor(m/60)}h ${m%60}m` : `${m}m`) : '';
    const esc = s => (s||'').replace(/[&<>"]/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
    const id = \(encodeForJS(itemID));
    // sticky header on scroll
    addEventListener('scroll', ()=>document.getElementById('stick').classList.toggle('on', scrollY>260));
    fetch('/api/detail/' + encodeURIComponent(id)).then(r=>r.json()).then(i=>{
      document.title = i.title + ' — Seret';
      document.getElementById('title').textContent = i.title;
      document.getElementById('stitle').textContent = i.title;
      const hero = document.getElementById('hero');
      if (i.backdropPath) hero.style.backgroundImage = `url(${IMG(i.backdropPath,'w1280')})`;
      else if (i.posterPath) hero.style.backgroundImage = `url(${IMG(i.posterPath,'w780')})`;
      // meta line: year · runtime · genres · Dir.
      const m = [];
      if (i.year) m.push(i.year);
      if (i.runtime) m.push(runtime(i.runtime));
      if (i.genres && i.genres.length) m.push(i.genres.slice(0,3).join(' · '));
      if (i.director) m.push('Dir. ' + i.director);
      document.getElementById('meta').textContent = m.join('  ·  ');
      // ratings
      if (i.ratings) {
        const r = i.ratings, parts = [];
        if (r.imdb!=null) parts.push(`<span class=rate><span class=imdb>IMDb</span> ${r.imdb.toFixed(1)}</span>`);
        if (r.rottenTomatoes!=null) parts.push(`<span class=rate>🍅 ${r.rottenTomatoes}%</span>`);
        if (r.metacritic!=null) parts.push(`<span class=rate><span class=mc>${r.metacritic}</span> <span class=lbl>Metacritic</span></span>`);
        document.getElementById('rates').innerHTML = parts.join('');
      }
      // quality chips
      document.getElementById('chips').innerHTML =
        (i.qualityChips||[]).map(c=>`<span class=chip>${esc(c)}</span>`).join('');
      // actions
      document.getElementById('actions').innerHTML =
        `<a class=btn-gold href="/watch?item=${encodeURIComponent(i.id)}&version=${i.bestVersionIndex}">▶ Play</a>`;
      document.getElementById('ov').textContent = i.overview || '';
      // versions
      if (i.versions && i.versions.length > 1) {
        document.getElementById('vsect').style.display = 'block';
        document.getElementById('versions').innerHTML = i.versions.map((v,n)=>
          `<div class=ver onclick="location.href='/watch?item=${encodeURIComponent(i.id)}&version=${v.index}'">
             <div><div class=vlabel>${esc(v.label)}</div>
                  <div class="muted" style=font-size:12px>Version ${n+1}</div></div>
             <div class=go>▶</div></div>`).join('');
      }
      // cast
      if (i.cast && i.cast.length) {
        document.getElementById('csect').style.display = 'block';
        document.getElementById('cast').innerHTML = i.cast.map(c=>{
          const face = c.profilePath
            ? `<div class=face style="background-image:url(${IMG(c.profilePath,'w185')})"></div>`
            : `<div class=face>${esc((c.name||'?').slice(0,1))}</div>`;
          return `<div class=cast>${face}<div class=nm>${esc(c.name)}</div>
            <div class=ch>${esc(c.character||'')}</div></div>`;
        }).join('');
      }
      // more like this
      if (i.similar && i.similar.length) {
        document.getElementById('ssect').style.display = 'block';
        document.getElementById('similar').innerHTML = i.similar.map(s=>{
          const bg = s.posterPath ? `background-image:url(${IMG(s.posterPath,'w342')})` : '';
          const inner = `<div class=poster style="${bg}">${s.posterPath?'':esc(s.title)}</div>
            <div class=ct>${esc(s.title)}</div><div class=cy>${s.year||''}</div>`;
          return s.ownedID
            ? `<a class=card href="/item?id=${encodeURIComponent(s.ownedID)}">${inner}</a>`
            : `<div class=staticcard>${inner}</div>`;
        }).join('');
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
