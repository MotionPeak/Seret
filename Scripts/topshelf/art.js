// Seret brand art: the "Range" Top Shelf landscape and the Monogram app icon.
//
// One drawing file for everything, so the video, the Top Shelf stills and every icon size come
// out of the same code. `render.swift` loads `render.html` (which includes this) into a WKWebView
// and asks `ART[kind](ctx, w, h, t)` for each frame or image. Every function is a pure function
// of its arguments — no state between frames — so any frame can be rendered on its own.
//
// Colours follow the tvOS theme (Apps/SeretTV/DesignSystem/Theme.swift): canvas #0A0D14, white
// hairlines, the mark in white → #C9CEDA silver.
'use strict';

const BG = '#0A0D14';
const HEB = '-apple-system,"SF Hebrew","Arial Hebrew",sans-serif';
const LAT = '-apple-system,"SF Pro Display","Helvetica Neue",sans-serif';

const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const ss = (a, b, x) => { const t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const lerp = (a, b, t) => a + (b - a) * t;

function mulberry(a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}
function hash(i, j, k) {
  let h = Math.imul(i | 0, 374761393) ^ Math.imul(j | 0, 668265263) ^ Math.imul(k | 0, 1440662683);
  h = Math.imul(h ^ (h >>> 13), 1274126177); h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}
function vnoise(x, y, z) {
  const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
  const xf = x - xi, yf = y - yi, zf = z - zi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf), w = zf * zf * (3 - 2 * zf);
  const c = (a, b, d) => hash(xi + a, yi + b, zi + d);
  const x00 = lerp(c(0, 0, 0), c(1, 0, 0), u), x10 = lerp(c(0, 1, 0), c(1, 1, 0), u);
  const x01 = lerp(c(0, 0, 1), c(1, 0, 1), u), x11 = lerp(c(0, 1, 1), c(1, 1, 1), u);
  return lerp(lerp(x00, x10, v), lerp(x01, x11, v), w);
}
function fbm(x, y, z) {
  return vnoise(x, y, z) * 0.6 + vnoise(x * 2.07, y * 2.07, z * 1.3 + 5.1) * 0.3 + vnoise(x * 4.3, y * 4.3, z * 1.7 + 9.7) * 0.1;
}

/** The Seret play triangle (Brand.swift proportions), centred on (cx, cy) in a box of size s. */
function triPts(cx, cy, s) { return [[-0.19, -0.26], [-0.19, 0.26], [0.27, 0]].map(([x, y]) => [cx + x * s, cy + y * s]); }
function roundTri(ctx, P, r) {
  ctx.beginPath();
  for (let i = 0; i < 3; i++) {
    const p0 = P[(i + 2) % 3], p1 = P[i], p2 = P[(i + 1) % 3];
    if (i === 0) ctx.moveTo((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2);
    ctx.arcTo(p1[0], p1[1], (p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2, r);
  }
  ctx.closePath();
}
/** Signed distance to a triangle: negative inside (after Inigo Quilez). */
function makeSdf(P) {
  const [p0, p1, p2] = P;
  const e0x = p1[0] - p0[0], e0y = p1[1] - p0[1], e1x = p2[0] - p1[0], e1y = p2[1] - p1[1], e2x = p0[0] - p2[0], e2y = p0[1] - p2[1];
  const l0 = e0x * e0x + e0y * e0y, l1 = e1x * e1x + e1y * e1y, l2 = e2x * e2x + e2y * e2y;
  const s = Math.sign(e0x * e2y - e0y * e2x);
  return (px, py) => {
    const v0x = px - p0[0], v0y = py - p0[1], v1x = px - p1[0], v1y = py - p1[1], v2x = px - p2[0], v2y = py - p2[1];
    let h = clamp((v0x * e0x + v0y * e0y) / l0); const q0x = v0x - e0x * h, q0y = v0y - e0y * h;
    h = clamp((v1x * e1x + v1y * e1y) / l1); const q1x = v1x - e1x * h, q1y = v1y - e1y * h;
    h = clamp((v2x * e2x + v2y * e2y) / l2); const q2x = v2x - e2x * h, q2y = v2y - e2y * h;
    const dx = Math.min(q0x * q0x + q0y * q0y, q1x * q1x + q1y * q1y, q2x * q2x + q2y * q2y);
    const dy = Math.min(s * (v0x * e0y - v0y * e0x), s * (v1x * e1y - v1y * e1x), s * (v2x * e2y - v2y * e2x));
    return -Math.sqrt(dx) * Math.sign(dy);
  };
}
function silver(ctx, P) {
  const xs = P.map(p => p[0]), ys = P.map(p => p[1]);
  const g = ctx.createLinearGradient(Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys));
  g.addColorStop(0, '#FFFFFF'); g.addColorStop(1, '#C9CEDA');
  return g;
}
function reset(ctx) {
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.setLineDash([]);
  ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.globalCompositeOperation = 'source-over';
  ctx.shadowBlur = 0; ctx.shadowColor = 'rgba(0,0,0,0)';
}
/** Letter-spaced Latin text, centred on x. */
function spaced(ctx, str, x, y, fs, track, color, weight = 600) {
  ctx.save();
  ctx.font = `${weight} ${fs}px ${LAT}`; ctx.fillStyle = color; ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
  const ch = [...str], ws = ch.map(c => ctx.measureText(c).width);
  let cx = x - (ws.reduce((a, b) => a + b, 0) + track * (ch.length - 1)) / 2;
  ch.forEach((c, i) => { ctx.fillText(c, cx, y); cx += ws[i] + track; });
  ctx.restore();
}
/** A perspective camera over the landscape's map plane: tilt 0 looks straight down. */
function camera(cx, cy, S, tilt, F) {
  const ct = Math.cos(tilt), st = Math.sin(tilt);
  return (u, v, h) => { const yp = v * ct - h * st, sc = F / (F - (v * st + h * ct)); return [cx + u * S * sc, cy + yp * S * sc]; };
}

// ───────────────────────────── Range ─────────────────────────────
//
// Rows of white hairline run back to a glow on the horizon. Where the triangle stands they lift
// into a range of peaks with glowing crests. The land drifts toward the viewer, two ripples roll
// out from the triangle twice a loop, a band of light rakes across, and stars twinkle above.
//
// It loops seamlessly every LOOP seconds: the drifting land is two noise fields cross-faded so
// frame LOOP is frame 0 again, the ripples die out before the seam, the light band is off-screen
// at both ends, and every star twinkles a whole number of times per loop.

const LOOP = 16;
const DRIFT = 0.05;                       // map units per second the land moves toward the viewer
const PULSES = [3.0, 3.65, 10.5, 11.15];  // ripple start times (each lives 4.5 s)
const STARS = (() => {
  const rng = mulberry(5);
  return [...Array(170)].map(() => ({ x: rng(), y: rng(), r: 0.4 + rng() * 1.1, ph: rng() * 6.283, k: 1 + Math.floor(rng() * 4) }));
})();

/** Noise that drifts by DRIFT·T and returns to its start at T = LOOP, contrast-preserving. */
function loopNoise(f, u, v, T) {
  const w = T / LOOP, d = DRIFT * T;
  const a = f(u, v - d) - 0.5, b = f(u, v - d + DRIFT * LOOP) - 0.5;
  return 0.5 + ((1 - w) * a + w * b) / Math.sqrt((1 - w) * (1 - w) + w * w);
}
const landNoise = (u, v) => fbm(u * 1.4 + 20, v * 1.4 + 20, 3.7);
const crestNoise = (u, v) => vnoise(u * 4 + 3, v * 4 + 7, 1.3);

/** The Top Shelf loop: the finished landscape, drifting, rippling and lit, forever. */
function range(ctx, W, H, t, opt = {}) {
  const T = ((t % LOOP) + LOOP) % LOOP;
  scene(ctx, W, H, {
    rows: opt.rows, cols: opt.cols,
    noise: (f, u, v) => loopNoise(f, u, v, T),
    twinkle: T / LOOP,
    ages: PULSES.map(tp => T - tp),
    band: T / LOOP,
    wordmark: opt.wordmark !== false,
  });
}

/**
 * Draws the Range landscape. Every animated quantity is a field of `p`; anything left out is the
 * finished, resting landscape, so `range` (the Top Shelf loop) and `intro` (the launch animation)
 * share one drawing.
 *
 * p.noise(f, u, v)   the terrain noise at map point (u, v) — required
 * p.twinkle          the stars' twinkle phase, in loops
 * p.glow, p.stars    horizon glow / star opacity, 0…1
 * p.row(near)        [opacity, lift] of a row, near = 0 at the horizon … 1 at the viewer
 * p.rise             how far the triangle's peaks have risen, 0 (flat land) … 1
 * p.crest            the peaks' glow, 0…1
 * p.ages             seconds since each ripple started (each lives 4.5 s)
 * p.band             the raking light's position: 0 off the left edge … 1 off the right
 * p.wordmark         draw סֶרֶט / SERET; p.word = { a, dy, track, latinA } animates it
 * p.zoom             scale about the triangle's centre (the launch's dive)
 * p.fade             a navy veil over everything, 0…1
 * p.portrait         lay the frame out for a tall screen
 */
function scene(ctx, W, H, p) {
  const u1 = H / 720;                                    // one "pixel" at 720p
  const tall = !!p.portrait;
  // p.size / p.centre override the Top Shelf's layout (triangle box size, and the land's centre
  // as a fraction of H): the intro stands the land lower and smaller so the sky can hold the name.
  const s = p.size ?? H * 0.5, cx = W / 2, cyL = H * (p.centre ?? 0.36);
  const S = s / 0.9, nR = p.rows || 90, NX = p.cols || 480;
  const ua = -3.2 * (W / H) / (16 / 9) * (H * 0.5 / s), ub = -ua;
  const va = -1.75, vb = tall ? 2.2 : 1.35;
  const Pt = triPts(cx, cyL + s * 0.16, s * 1.05), sdS = makeSdf(Pt);
  const pr = camera(cx, cyL + s * 0.12, S, 0.98, 3.0), hz = pr(0, va, 0);
  const xs = new Float32Array(NX), ys = new Float32Array(NX), ins = new Float32Array(NX);
  const glowA = p.glow ?? 1, starA = p.stars ?? 1, rise = p.rise ?? 1, crest = p.crest ?? 1;
  const row = p.row || (() => [1, 1]);

  reset(ctx);
  ctx.fillStyle = BG; ctx.fillRect(0, 0, W, H);
  const zoom = p.zoom ?? 1;
  if (zoom !== 1) {
    const zx = (Pt[0][0] + Pt[1][0] + Pt[2][0]) / 3, zy = (Pt[0][1] + Pt[1][1] + Pt[2][1]) / 3;
    ctx.translate(zx, zy); ctx.scale(zoom, zoom); ctx.translate(-zx, -zy);
  }
  const glow = ctx.createRadialGradient(cx, hz[1], 0, cx, hz[1], Math.max(W, H * 0.9) * 0.55);
  glow.addColorStop(0, 'rgba(70,88,128,0.42)'); glow.addColorStop(1, 'rgba(10,13,20,0)');
  ctx.globalAlpha = glowA; ctx.fillStyle = glow; ctx.fillRect(-W, -H, W * 3, H * 3);

  // Stars — each twinkles k whole times per loop.
  ctx.fillStyle = '#fff';
  for (const st of STARS) {
    const y = st.y * (hz[1] - H * 0.03);
    const a = (0.15 + 0.55 * (0.5 + 0.5 * Math.sin((p.twinkle || 0) * 6.2832 * st.k + st.ph))) * ss(hz[1], hz[1] * 0.4, y) * starA;
    if (a < 0.01) continue;
    ctx.globalAlpha = a; ctx.beginPath(); ctx.arc(st.x * W, y, st.r * u1, 0, 7); ctx.fill();
  }

  const scMid = pr(1, 0, 0)[0] - pr(0, 0, 0)[0], Apx = H * 0.1 * (s / (H * 0.5));
  const us = lerp(-4.2, 4.2, clamp(p.band ?? 0.5)) * (ub / 3.2);    // the raking light, off-screen at both ends
  for (let r = 0; r < nR; r++) {
    const v = lerp(va, vb, r / (nR - 1)), near = r / (nR - 1);
    const [ra, lift] = row(near);
    if (ra <= 0.001) continue;
    const scl = (pr(1, v, 0)[0] - pr(0, v, 0)[0]) / scMid;
    for (let x = 0; x < NX; x++) {
      const u = lerp(ua, ub, x / (NX - 1)), q = pr(u, v, 0);
      const n = p.noise(landNoise, u, v), n2 = p.noise(crestNoise, u, v);
      const inside = ss(s * 0.05, -s * 0.05, sdS(q[0], q[1]));
      ins[x] = inside * rise;
      let d = n * n * 0.75 * Apx + inside * rise * (0.45 + 0.8 * n2) * Apx;
      for (const age of p.ages || []) {
        if (age > 0 && age < 4.5) {
          const dist = Math.hypot(u, (v - 0.1) * 1.3);
          d += Apx * 0.2 * Math.exp(-Math.pow((dist - age * 0.95) / 0.075, 2)) * (1 - age / 4.5);
        }
      }
      xs[x] = q[0]; ys[x] = q[1] - d * lift * scl;
    }
    // Occlude everything behind this row, then draw it.
    ctx.globalAlpha = ra; ctx.fillStyle = BG;
    ctx.beginPath(); ctx.moveTo(xs[0], ys[0]);
    for (let x = 1; x < NX; x++) ctx.lineTo(xs[x], ys[x]);
    ctx.lineTo(xs[NX - 1], H * 3); ctx.lineTo(xs[0], H * 3); ctx.closePath(); ctx.fill();

    const gx = pr(us, v, 0)[0], bw = Math.abs(scMid * scl) * 0.9;
    const band = ctx.createLinearGradient(gx - bw, 0, gx + bw, 0);
    band.addColorStop(0, 'rgba(255,255,255,0.5)'); band.addColorStop(0.5, '#ffffff'); band.addColorStop(1, 'rgba(255,255,255,0.5)');
    const da = lerp(0.14, 0.9, Math.pow(near, 0.7));
    ctx.strokeStyle = band; ctx.globalAlpha = da * ra; ctx.lineWidth = lerp(0.8, 1.25, near) * u1;
    ctx.beginPath(); ctx.moveTo(xs[0], ys[0]);
    for (let x = 1; x < NX; x++) ctx.lineTo(xs[x], ys[x]);
    ctx.stroke();

    // The triangle's crests glow.
    if (crest > 0.001) {
      ctx.save();
      ctx.shadowColor = 'rgba(255,255,255,0.9)'; ctx.shadowBlur = 9 * u1;
      ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.35 * u1; ctx.globalAlpha = Math.min(1, da + 0.25) * ra * crest;
      ctx.beginPath(); let on = false;
      for (let x = 0; x < NX; x++) {
        if (ins[x] > 0.12) { on ? ctx.lineTo(xs[x], ys[x]) : ctx.moveTo(xs[x], ys[x]); on = true; } else on = false;
      }
      ctx.stroke(); ctx.restore();
    }
  }

  // Haze on the horizon and fades at both sides.
  ctx.globalAlpha = 1;
  if (p.size === undefined) {
    const fog = ctx.createLinearGradient(0, hz[1] - H * 0.06, 0, hz[1] + H * 0.12);
    fog.addColorStop(0, 'rgba(10,13,20,0.95)'); fog.addColorStop(1, 'rgba(10,13,20,0)');
    ctx.fillStyle = fog; ctx.fillRect(-W, hz[1] - H * 0.06, W * 3, H * 0.18);
  } else {
    // With open sky above the horizon, the haze has to rise out of it softly, not start at an edge.
    const top = hz[1] - H * 0.1, fog = ctx.createLinearGradient(0, top, 0, hz[1] + H * 0.12);
    fog.addColorStop(0, 'rgba(10,13,20,0)'); fog.addColorStop(0.4, 'rgba(10,13,20,0.9)');
    fog.addColorStop(1, 'rgba(10,13,20,0)');
    ctx.fillStyle = fog; ctx.fillRect(-W, top, W * 3, H * 0.22);
  }
  if (tall) {
    // Bottom fade: the near rows run off a tall frame instead of filling it.
    const foot = ctx.createLinearGradient(0, H * 0.82, 0, H);
    foot.addColorStop(0, 'rgba(10,13,20,0)'); foot.addColorStop(1, 'rgba(10,13,20,0.9)');
    ctx.fillStyle = foot; ctx.fillRect(-W, H * 0.82, W * 3, H * 3);
  }
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  const side = ctx.createLinearGradient(0, 0, W, 0);
  const e = tall ? 0.1 : 0.12 * (16 / 9) / (W / H);
  side.addColorStop(0, 'rgba(10,13,20,1)'); side.addColorStop(e, 'rgba(10,13,20,0)');
  side.addColorStop(1 - e, 'rgba(10,13,20,0)'); side.addColorStop(1, 'rgba(10,13,20,1)');
  ctx.fillStyle = side; ctx.fillRect(0, 0, W, H);

  if (p.wordmark) {
    const w = p.word || { a: 1, dy: 0, track: 1, latinA: 1 };
    // The intro's name is the hero: larger, standing in the sky just above the horizon.
    const sz = p.word ? (tall ? W * 0.17 : H * 0.095) : H * 0.05;
    const y = (p.word ? hz[1] - H * (tall ? 0.085 : 0.075) : H * 0.1) + w.dy;
    if (w.a > 0.001) {
      ctx.save();
      ctx.globalAlpha = w.a;
      ctx.shadowColor = 'rgba(200,215,255,0.55)'; ctx.shadowBlur = p.word ? sz * 0.45 * (w.glow ?? 0) : 0;
      ctx.fillStyle = '#F5F6F8'; ctx.textAlign = 'center'; ctx.direction = 'rtl';
      ctx.font = `700 ${sz}px ${HEB}`; ctx.fillText('סֶרֶט', W / 2, y);
      ctx.restore();
    }
    if ((w.latinA ?? w.a) > 0.001) {
      ctx.save(); ctx.globalAlpha = 0.9 * (w.latinA ?? w.a);
      spaced(ctx, 'SERET', W / 2, y + sz * 0.72, sz * 0.25, sz * 0.24 * w.track, '#A3AAB8');
      ctx.restore();
    }
  }

  if (p.fade) { ctx.globalAlpha = clamp(p.fade); ctx.fillStyle = BG; ctx.fillRect(0, 0, W, H); ctx.globalAlpha = 1; }
}

// ───────────────────────────── Intro ─────────────────────────────
//
// The launch animation, played once when the app opens: out of the dark the horizon glows, the
// ridgelines pour in from the horizon toward the viewer, the triangle's peaks rise out of the
// land and catch light, two ripples roll out as they settle, a band of light rakes across, the
// name arrives in the sky — then the camera dives into the triangle and everything sinks into
// the app's own navy. INTRO_HOLD is the frame where everything is in and nothing has dived yet
// (the app may pause there while the library loads, and shows it as a still under Reduce Motion).

const INTRO = 3.4;
const INTRO_HOLD = 2.7;
const easeOutBack = x => { const c = 1.45; x = clamp(x); return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2); };

function intro(ctx, W, H, t, portrait) {
  const dive = ss(INTRO_HOLD, INTRO, t);                 // 0 until the hold, then 0…1
  const drift = DRIFT * 2 * t + 0.9 * dive * dive;       // the land runs under the camera as it dives
  scene(ctx, W, H, {
    portrait,
    size: portrait ? Math.min(H * 0.5, W * 0.95) : H * 0.42,
    centre: portrait ? 0.55 : 0.46,
    noise: (f, u, v) => f(u, v - drift),
    twinkle: t / 4,
    glow: ss(0, 0.7, t) * (1 + 0.35 * ss(1.6, 2.2, t) * (1 - ss(2.2, 3.0, t))),
    stars: ss(0.4, 1.5, t),
    row: near => { const t0 = 0.15 + 1.0 * near, a = ss(t0, t0 + 0.4, t); return [a, a]; },
    rise: easeOutBack((t - 1.05) / 0.9),
    crest: ss(1.25, 1.85, t),
    ages: [t - 1.8, t - 2.1],
    band: (t - 1.5) / 1.3,
    wordmark: true,
    word: {
      a: ss(1.95, 2.45, t) * (1 - ss(2.75, 3.05, t)),
      dy: (1 - ss(1.95, 2.55, t)) * H * 0.02,
      track: lerp(2.4, 1, ss(2.0, 2.75, t)),
      latinA: ss(2.15, 2.65, t) * (1 - ss(2.75, 3.0, t)),
      glow: ss(2.0, 2.4, t) * (1 - 0.6 * ss(2.4, 2.8, t)),
    },
    zoom: 1 + 2.2 * Math.pow(dive, 2.4),
    fade: ss(2.95, INTRO - 0.05, t),
  });
}

// ───────────────────────────── Monogram ─────────────────────────────
//
// The solid silver triangle, cut through by dark ridgelines like a carved landscape.

/** The navy field behind the mark. */
function monoBack(ctx, W, H) {
  reset(ctx);
  ctx.fillStyle = BG; ctx.fillRect(0, 0, W, H);
  const g = ctx.createRadialGradient(W / 2, H * 0.42, 0, W / 2, H * 0.42, Math.max(W, H) * 0.75);
  g.addColorStop(0, 'rgba(52,66,98,0.55)'); g.addColorStop(1, 'rgba(10,13,20,0)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
}
/** The mark on a transparent canvas; `size` is the triangle box as a fraction of min(W, H). */
function monoFront(ctx, W, H, size) {
  reset(ctx);
  const m = Math.min(W, H), u = m / 300, P = triPts(W / 2 + m * 0.03 * size / 0.78, H / 2, m * size);
  const k = size / 0.78;                                 // the mockup was tuned at size 0.78
  ctx.save(); roundTri(ctx, P, m * 0.05 * k); ctx.fillStyle = silver(ctx, P);
  ctx.shadowColor = 'rgba(150,170,220,0.35)'; ctx.shadowBlur = 30 * u * k; ctx.fill(); ctx.restore();
  ctx.save(); roundTri(ctx, P, m * 0.05 * k); ctx.clip();
  const nL = 8, ya = H / 2 - m * 0.2 * k, yb = H / 2 + m * 0.24 * k, gap = (yb - ya) / (nL - 1);
  const xa = P[0][0] - m * 0.05 * k, xb = P[2][0] + m * 0.05 * k;
  ctx.strokeStyle = BG; ctx.lineWidth = 2.4 * u * k; ctx.globalAlpha = 0.85;
  for (let l = 0; l < nL; l++) {
    const y = ya + l * gap;
    ctx.beginPath();
    for (let i = 0; i <= 160; i++) {
      const x = lerp(xa, xb, i / 160), q = (x - xa) / (xb - xa);
      const peak = Math.exp(-Math.pow((q - 0.36) / 0.12, 2)) + Math.exp(-Math.pow((q - 0.58) / 0.09, 2)) * 0.55;
      const yy = y - peak * gap * 1.15 * (0.6 + 0.4 * Math.sin(l * 1.3 + 1));
      i ? ctx.lineTo(x, yy) : ctx.moveTo(x, yy);
    }
    ctx.stroke();
  }
  ctx.restore();
}

const ART = {
  range: (ctx, W, H, t) => range(ctx, W, H, t),
  rangeStill: (ctx, W, H) => range(ctx, W, H, 0),
  introWide: (ctx, W, H, t) => intro(ctx, W, H, t, false),
  introTall: (ctx, W, H, t) => intro(ctx, W, H, t, true),
  monoBack: (ctx, W, H) => monoBack(ctx, W, H),
  monoFrontTV: (ctx, W, H) => { ctx.clearRect(0, 0, W, H); monoFront(ctx, W, H, 0.98); },
  monoPhone: (ctx, W, H) => { monoBack(ctx, W, H); monoFront(ctx, W, H, 0.86); },
};
