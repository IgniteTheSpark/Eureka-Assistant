"""
Report presentation CSS — ported from the design handoff (design_handoff_eureka_reports).

Per §6.5 the render layer is deterministic: **surface × palette × block kit**.
- BASE_CSS  = report-base.css: the shared block primitives (.r-*) + the 6 palettes
              (.pal-* → --rk-* token sets). Single source of truth for tokens.
- SURFACE_CSS[surface] = each genre-variant's bespoke layout (masthead/hero + block
              tweaks), built ON the base. A report = base + one surface + one palette
              class on <main class="report pal-X surface-Y">.

This module holds ONLY the verbatim design CSS so report_render.py stays logic.
Fonts: the design uses Google Fonts CDN; production should inline/bundle (§6.5) —
report_render injects the <link> for now.
"""

# ── report-base.css (verbatim) — block kit + 6 palettes ───────────────────────
BASE_CSS = r"""
*, *::before, *::after { box-sizing: border-box; }
.report {
  --rk-bg:#0b1220; --rk-bg-2:#11192b; --rk-surface:rgba(255,255,255,.04); --rk-surface-2:rgba(255,255,255,.06);
  --rk-border:rgba(255,255,255,.10); --rk-rule:rgba(255,255,255,.07);
  --rk-text-hi:#f3f6fb; --rk-text:rgba(255,255,255,.84); --rk-text-mid:rgba(255,255,255,.62); --rk-text-lo:rgba(255,255,255,.42); --rk-text-muted:rgba(255,255,255,.30);
  --rk-accent:#6f9eff; --rk-accent-2:#8ab4ff; --rk-accent-soft:rgba(111,158,255,.16);
  --rk-good:#43c98a; --rk-bad:#f0666f; --rk-warn:#e7b35a; --rk-glow:rgba(111,158,255,.35);
  --rk-font:"Manrope",-apple-system,"Segoe UI",system-ui,sans-serif;
  --rk-font-cjk:"Noto Sans SC",var(--rk-font); --rk-font-mono:"JetBrains Mono",ui-monospace,monospace;
  --rk-font-display:var(--rk-font-cjk); --rk-r:16px; --rk-r-sm:10px;
  margin:0; width:100%; min-height:100%; background:var(--rk-bg); color:var(--rk-text);
  font-family:var(--rk-font-cjk); font-size:15px; line-height:1.6;
  -webkit-font-smoothing:antialiased; text-rendering:optimizeLegibility; overflow-x:hidden;
}
html, body { margin:0; padding:0; background:var(--rk-bg); }

.pal-dashboard {
  --rk-bg:#0c1118; --rk-bg-2:#131a24; --rk-surface:#141b26; --rk-surface-2:#1a2330;
  --rk-border:rgba(150,180,220,.13); --rk-rule:rgba(150,180,220,.09);
  --rk-text-hi:#eaf1fb; --rk-text:rgba(225,235,248,.82); --rk-text-mid:rgba(200,215,235,.58); --rk-text-lo:rgba(180,198,222,.40); --rk-text-muted:rgba(160,180,210,.28);
  --rk-accent:#4f8cff; --rk-accent-2:#6fa6ff; --rk-accent-soft:rgba(79,140,255,.15);
  --rk-good:#35c98c; --rk-bad:#ff6b73; --rk-warn:#f0b35a; --rk-glow:rgba(79,140,255,.30); --rk-r:14px; --rk-r-sm:9px;
}
.pal-neon {
  --rk-bg:#06070f; --rk-bg-2:#0c0e1c; --rk-surface:rgba(140,120,255,.05); --rk-surface-2:rgba(140,120,255,.09);
  --rk-border:rgba(150,130,255,.18); --rk-rule:rgba(150,130,255,.12);
  --rk-text-hi:#f4f0ff; --rk-text:rgba(228,224,255,.82); --rk-text-mid:rgba(200,194,240,.58); --rk-text-lo:rgba(180,172,225,.42); --rk-text-muted:rgba(160,150,210,.30);
  --rk-accent:#a06bff; --rk-accent-2:#2ee6c6; --rk-accent-soft:rgba(160,107,255,.16);
  --rk-good:#2ee6c6; --rk-bad:#ff5d8f; --rk-warn:#ffd166; --rk-glow:rgba(160,107,255,.55); --rk-r:18px; --rk-r-sm:11px;
}
.pal-ink {
  --rk-bg:#14130f; --rk-bg-2:#1c1a14; --rk-surface:rgba(245,238,222,.04); --rk-surface-2:rgba(245,238,222,.07);
  --rk-border:rgba(232,224,205,.14); --rk-rule:rgba(232,224,205,.10);
  --rk-text-hi:#f6f1e6; --rk-text:rgba(244,238,224,.83); --rk-text-mid:rgba(228,220,200,.60); --rk-text-lo:rgba(210,200,178,.42); --rk-text-muted:rgba(190,180,158,.30);
  --rk-accent:#d98a4b; --rk-accent-2:#e6a96b; --rk-accent-soft:rgba(217,138,75,.15);
  --rk-good:#8caa5a; --rk-bad:#d96a5a; --rk-warn:#d9a84b; --rk-glow:rgba(217,138,75,.28);
  --rk-font-display:"Noto Serif SC","Songti SC",serif; --rk-r:6px; --rk-r-sm:4px;
}
.pal-minimal {
  --rk-bg:#f6f5f1; --rk-bg-2:#fbfaf7; --rk-surface:#ffffff; --rk-surface-2:#fbfaf6;
  --rk-border:rgba(30,28,22,.10); --rk-rule:rgba(30,28,22,.07);
  --rk-text-hi:#1a1813; --rk-text:rgba(26,24,19,.82); --rk-text-mid:rgba(26,24,19,.56); --rk-text-lo:rgba(26,24,19,.40); --rk-text-muted:rgba(26,24,19,.26);
  --rk-accent:#2f63d6; --rk-accent-2:#4f80e6; --rk-accent-soft:rgba(47,99,214,.10);
  --rk-good:#1f9d63; --rk-bad:#d8483f; --rk-warn:#c98a1e; --rk-glow:rgba(47,99,214,.18); --rk-r:12px; --rk-r-sm:8px;
}
.pal-warm {
  --rk-bg:#f3ece0; --rk-bg-2:#faf5ec; --rk-surface:#fffaf1; --rk-surface-2:#fdf4e6;
  --rk-border:rgba(80,55,30,.12); --rk-rule:rgba(80,55,30,.08);
  --rk-text-hi:#2a2015; --rk-text:rgba(50,38,24,.84); --rk-text-mid:rgba(70,54,34,.58); --rk-text-lo:rgba(90,70,46,.42); --rk-text-muted:rgba(110,88,60,.30);
  --rk-accent:#c9722e; --rk-accent-2:#e09349; --rk-accent-soft:rgba(201,114,46,.13);
  --rk-good:#5a8a3c; --rk-bad:#c75440; --rk-warn:#c9942e; --rk-glow:rgba(201,114,46,.22); --rk-r:16px; --rk-r-sm:10px;
}
.pal-forest {
  --rk-bg:#0c1410; --rk-bg-2:#11201a; --rk-surface:rgba(180,230,200,.045); --rk-surface-2:rgba(180,230,200,.08);
  --rk-border:rgba(160,220,185,.15); --rk-rule:rgba(160,220,185,.10);
  --rk-text-hi:#eef6ef; --rk-text:rgba(225,240,228,.83); --rk-text-mid:rgba(195,220,200,.58); --rk-text-lo:rgba(175,205,182,.42); --rk-text-muted:rgba(155,190,165,.30);
  --rk-accent:#4fb37a; --rk-accent-2:#79d29a; --rk-accent-soft:rgba(79,179,122,.15);
  --rk-good:#5bc98a; --rk-bad:#e07a6a; --rk-warn:#d9b15a; --rk-glow:rgba(79,179,122,.34); --rk-r:20px; --rk-r-sm:12px;
}

.report-pad { padding:0 20px; }
.report section { position:relative; }
.r-eyebrow { font-family:var(--rk-font-mono); font-size:11px; letter-spacing:.22em; text-transform:uppercase; color:var(--rk-text-lo); font-weight:600; }
.r-h1 { font-family:var(--rk-font-display); color:var(--rk-text-hi); font-weight:700; font-size:30px; line-height:1.18; letter-spacing:-.01em; margin:10px 0 0; text-wrap:balance; }
.r-headline { font-size:17px; line-height:1.55; color:var(--rk-text); margin:14px 0 0; }
.r-h2 { font-family:var(--rk-font-display); color:var(--rk-text-hi); font-weight:700; font-size:21px; line-height:1.25; margin:0 0 12px; letter-spacing:-.005em; }
.r-h2 .r-h2-num { font-family:var(--rk-font-mono); font-size:12px; font-weight:600; color:var(--rk-accent); letter-spacing:.1em; display:block; margin-bottom:4px; }
.r-p { margin:0 0 14px; color:var(--rk-text); }
.r-p strong { color:var(--rk-text-hi); font-weight:700; }
.r-block { margin:0 0 26px; }

.r-kpi { display:grid; gap:10px; grid-template-columns:repeat(auto-fit,minmax(96px,1fr)); }
.r-kpi-item { background:var(--rk-surface); border:1px solid var(--rk-border); border-radius:var(--rk-r-sm); padding:14px 12px; }
.r-kpi-label { font-family:var(--rk-font-mono); font-size:10.5px; letter-spacing:.08em; text-transform:uppercase; color:var(--rk-text-lo); margin-bottom:8px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.r-kpi-n { font-family:var(--rk-font-display); font-weight:700; color:var(--rk-text-hi); font-size:24px; line-height:1; white-space:nowrap; letter-spacing:-.01em; font-variant-numeric:tabular-nums; }
.r-kpi-sub { font-size:11px; color:var(--rk-text-mid); margin-top:5px; }
.r-kpi-delta { font-size:11px; font-weight:700; margin-top:5px; }
.r-kpi-delta.up { color:var(--rk-good); } .r-kpi-delta.down { color:var(--rk-bad); }

.r-chart { background:var(--rk-surface); border:1px solid var(--rk-border); border-radius:var(--rk-r); padding:18px 16px 14px; }
.r-chart-title { font-size:13px; font-weight:700; color:var(--rk-text-hi); margin-bottom:2px; }
.r-chart-unit { font-family:var(--rk-font-mono); font-size:10px; letter-spacing:.1em; text-transform:uppercase; color:var(--rk-text-lo); margin-bottom:16px; }
.r-bars { display:flex; align-items:flex-end; gap:10px; height:150px; }
.r-bar-col { flex:1; display:flex; flex-direction:column; align-items:center; justify-content:flex-end; height:100%; gap:8px; }
.r-bar-track { width:100%; display:flex; align-items:flex-end; justify-content:center; flex:1; }
.r-bar { width:78%; max-width:34px; border-radius:6px 6px 2px 2px; background:linear-gradient(180deg,var(--rk-accent-2),var(--rk-accent)); transform-origin:bottom; }
html.rk-anim .report .r-bar { transform:scaleY(0); }
.r-bar-val { font-family:var(--rk-font-mono); font-size:11px; font-weight:600; color:var(--rk-text); }
.r-bar-lbl { font-size:10.5px; color:var(--rk-text-lo); text-align:center; }

.r-donut-wrap { display:flex; align-items:center; gap:18px; }
.r-donut { flex:0 0 auto; } .r-donut circle { transition:none; }
.r-donut-legend { flex:1; display:flex; flex-direction:column; gap:9px; min-width:0; }
.r-leg-row { display:flex; align-items:center; gap:8px; font-size:12px; }
.r-leg-dot { width:9px; height:9px; border-radius:3px; flex:0 0 auto; }
.r-leg-lbl { color:var(--rk-text-mid); flex:1; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.r-leg-val { font-family:var(--rk-font-mono); font-weight:600; color:var(--rk-text-hi); font-variant-numeric:tabular-nums; }

.r-callout { border-radius:var(--rk-r); padding:16px 18px; background:var(--rk-accent-soft); border:1px solid var(--rk-border); position:relative; }
.r-callout-tag { font-family:var(--rk-font-mono); font-size:10px; letter-spacing:.16em; text-transform:uppercase; font-weight:700; margin-bottom:8px; display:flex; align-items:center; gap:6px; }
.r-callout p { margin:0; color:var(--rk-text); font-size:14.5px; line-height:1.55; }
.r-callout.insight { --c:var(--rk-accent); } .r-callout.success { --c:var(--rk-good); } .r-callout.warn { --c:var(--rk-warn); }
.r-callout .r-callout-tag { color:var(--c); }
.r-callout::before { content:""; position:absolute; left:0; top:14px; bottom:14px; width:3px; background:var(--c); border-radius:3px; opacity:.9; }

.r-quote { padding:6px 0 6px 18px; border-left:2px solid var(--rk-accent); font-family:var(--rk-font-display); color:var(--rk-text-hi); font-size:17px; line-height:1.5; font-style:italic; }
.r-quote cite { display:block; font-style:normal; font-family:var(--rk-font-mono); font-size:10.5px; letter-spacing:.08em; text-transform:uppercase; color:var(--rk-text-lo); margin-top:8px; }

.r-rank { list-style:none; margin:0; padding:0; display:flex; flex-direction:column; gap:1px; }
.r-rank li { display:flex; align-items:center; gap:12px; padding:12px 14px; background:var(--rk-surface); border:1px solid var(--rk-border); }
.r-rank li:first-child { border-radius:var(--rk-r-sm) var(--rk-r-sm) 0 0; } .r-rank li:last-child { border-radius:0 0 var(--rk-r-sm) var(--rk-r-sm); }
.r-rank-i { font-family:var(--rk-font-mono); font-weight:700; font-size:13px; color:var(--rk-accent); width:20px; flex:0 0 auto; }
.r-rank-lbl { flex:1; color:var(--rk-text); font-size:14px; }
.r-rank-val { font-family:var(--rk-font-mono); font-weight:600; color:var(--rk-text-hi); font-size:13px; font-variant-numeric:tabular-nums; }

.r-compare { width:100%; border-collapse:collapse; font-size:13px; }
.r-compare th, .r-compare td { text-align:left; padding:11px 12px; border-bottom:1px solid var(--rk-rule); }
.r-compare th { font-family:var(--rk-font-mono); font-size:10.5px; letter-spacing:.08em; text-transform:uppercase; color:var(--rk-text-lo); font-weight:600; }
.r-compare td { color:var(--rk-text); } .r-compare td:first-child { color:var(--rk-text-hi); font-weight:600; }
.r-compare tr:last-child td { border-bottom:none; }

.r-timeline { position:relative; padding-left:22px; }
.r-timeline::before { content:""; position:absolute; left:4px; top:4px; bottom:4px; width:2px; background:var(--rk-rule); }
.r-tl-item { position:relative; padding-bottom:18px; } .r-tl-item:last-child { padding-bottom:0; }
.r-tl-item::before { content:""; position:absolute; left:-22px; top:4px; width:10px; height:10px; border-radius:50%; background:var(--rk-accent); box-shadow:0 0 0 4px var(--rk-bg); }
.r-tl-date { font-family:var(--rk-font-mono); font-size:11px; color:var(--rk-accent); font-weight:600; }
.r-tl-text { color:var(--rk-text); font-size:14px; margin-top:2px; }

.r-actions { display:flex; flex-direction:column; gap:0; border:1px solid var(--rk-border); border-radius:var(--rk-r); overflow:hidden; }
.r-actions-head { font-family:var(--rk-font-mono); font-size:11px; letter-spacing:.14em; text-transform:uppercase; font-weight:700; color:var(--rk-accent); padding:13px 16px; background:var(--rk-accent-soft); display:flex; align-items:center; gap:7px; }
.r-action { display:flex; align-items:center; gap:12px; padding:13px 16px; border-top:1px solid var(--rk-rule); background:var(--rk-surface); }
.r-action-check { width:20px; height:20px; border-radius:6px; border:1.5px solid var(--rk-border); flex:0 0 auto; position:relative; }
.r-action-txt { flex:1; color:var(--rk-text); font-size:14px; }

.r-moment { margin:0 0 26px; }
.r-moment-tag { font-family:var(--rk-font-mono); font-size:10px; letter-spacing:.24em; text-transform:uppercase; color:var(--rk-accent); font-weight:700; text-align:center; margin-bottom:12px; display:flex; align-items:center; justify-content:center; gap:10px; }
.r-moment-tag::before, .r-moment-tag::after { content:""; height:1px; flex:1; background:var(--rk-rule); max-width:60px; }
.r-ai-img { border-radius:var(--rk-r); overflow:hidden; border:1px solid var(--rk-border); position:relative; background:var(--rk-surface-2); }
.r-ai-img img { width:100%; height:auto; display:block; will-change:transform; }
.r-img-ph { position:absolute; inset:0; aspect-ratio:16/10; display:flex; align-items:center; justify-content:center; background:repeating-linear-gradient(135deg,var(--rk-surface) 0 11px,var(--rk-surface-2) 11px 22px); }
.r-img-ph span { font-family:var(--rk-font-mono); font-size:10.5px; letter-spacing:.12em; text-transform:uppercase; color:var(--rk-text-lo); background:var(--rk-bg); padding:5px 12px; border-radius:999px; border:1px solid var(--rk-border); }

.r-sign { margin-top:14px; padding:22px 20px calc(22px + env(safe-area-inset-bottom)); border-top:1px solid var(--rk-rule); display:flex; align-items:center; gap:14px; background:linear-gradient(180deg,transparent,var(--rk-bg-2)); }
.r-sign-pet { width:52px; height:52px; flex:0 0 auto; position:relative; }
.r-sign-pet canvas { width:100%; height:100%; image-rendering:pixelated; }
.r-sign-meta { flex:1; min-width:0; }
.r-sign-mark { font-family:var(--rk-font-display); font-weight:700; color:var(--rk-text-hi); font-size:15px; letter-spacing:.01em; display:flex; align-items:center; gap:7px; }
.r-sign-spark { color:var(--rk-accent); }
.r-sign-tag { font-family:var(--rk-font-mono); font-size:10.5px; color:var(--rk-text-lo); letter-spacing:.04em; margin-top:3px; }

@media (prefers-reduced-motion:no-preference) {
  html.rk-anim .report [data-reveal] { opacity:0; transform:translateY(16px); }
  html.rk-anim .report [data-reveal].is-in { opacity:1; transform:none; transition:opacity .6s cubic-bezier(.2,.7,.3,1), transform .6s cubic-bezier(.2,.7,.3,1); }
}
.r-divider { height:1px; background:var(--rk-rule); margin:4px 0 26px; }
.r-meta-row { display:flex; align-items:center; gap:8px; flex-wrap:wrap; margin-top:14px; }
.r-chip { font-family:var(--rk-font-mono); font-size:10.5px; letter-spacing:.04em; color:var(--rk-text-mid); border:1px solid var(--rk-border); border-radius:999px; padding:4px 10px; display:inline-flex; align-items:center; gap:5px; }
.r-chip-dot { width:7px; height:7px; border-radius:50%; }
""".strip()


# ── per-surface CSS (bespoke masthead/hero + block tweaks) ────────────────────
SURFACE_CSS = {
    "surface-dashboard": r"""
.surface-dashboard { padding-bottom:0; }
.surface-dashboard .dash-head { padding:26px 20px 22px; background:radial-gradient(120% 90% at 80% -10%,rgba(79,140,255,.16),transparent 60%),var(--rk-bg); border-bottom:1px solid var(--rk-rule); }
.surface-dashboard .dash-grid { padding:24px 20px 8px; }
.surface-dashboard .r-h1 { font-size:28px; }
.dash-hero { display:flex; align-items:baseline; gap:12px; margin-top:18px; font-family:var(--rk-font-display); }
.dash-hero-n { font-size:46px; font-weight:800; color:var(--rk-text-hi); line-height:1; letter-spacing:-.02em; font-variant-numeric:tabular-nums; }
.dash-hero-lbl { font-family:var(--rk-font-mono); font-size:11px; letter-spacing:.12em; text-transform:uppercase; color:var(--rk-text-lo); }
.dash-hero-delta { font-size:13px; font-weight:700; color:var(--rk-good); font-family:var(--rk-font-mono); }
.surface-dashboard .r-kpi { grid-template-columns:repeat(3,1fr); }
""".strip(),

    "surface-neon": r"""
.surface-neon { padding-bottom:0; }
.surface-neon .neon-head { padding:30px 20px 26px; position:relative; overflow:hidden; background:radial-gradient(80% 60% at 50% 0%,rgba(160,107,255,.22),transparent 70%),radial-gradient(60% 50% at 90% 30%,rgba(46,230,198,.12),transparent 70%),var(--rk-bg); }
.neon-grid { position:absolute; inset:0; opacity:.5; background-image:linear-gradient(var(--rk-rule) 1px,transparent 1px),linear-gradient(90deg,var(--rk-rule) 1px,transparent 1px); background-size:28px 28px; -webkit-mask-image:radial-gradient(80% 70% at 50% 0%,#000,transparent 75%); mask-image:radial-gradient(80% 70% at 50% 0%,#000,transparent 75%); }
.neon-head > * { position:relative; }
.surface-neon .r-h1 { font-size:30px; }
.neon-hero { text-align:center; margin-top:22px; }
.neon-hero-n { font-family:var(--rk-font-display); font-weight:800; font-size:58px; line-height:1; letter-spacing:-.02em; color:var(--rk-text-hi); text-shadow:0 0 24px rgba(160,107,255,.7),0 0 50px rgba(160,107,255,.35); font-variant-numeric:tabular-nums; }
.neon-hero-lbl { font-family:var(--rk-font-mono); font-size:11px; letter-spacing:.2em; text-transform:uppercase; color:var(--rk-text-lo); margin-top:10px; }
.neon-hero-delta { display:inline-block; margin-top:12px; font-family:var(--rk-font-mono); font-size:12px; font-weight:700; color:var(--rk-good); border:1px solid rgba(46,230,198,.4); border-radius:999px; padding:5px 14px; box-shadow:0 0 18px rgba(46,230,198,.25); }
.surface-neon .neon-body { padding:26px 20px 8px; }
.surface-neon .r-kpi { grid-template-columns:repeat(3,1fr); }
.surface-neon .r-kpi-item { background:var(--rk-surface); box-shadow:inset 0 0 0 1px var(--rk-border),0 0 24px rgba(160,107,255,.06); }
.surface-neon .r-kpi-n { text-shadow:0 0 16px var(--rk-glow); }
.surface-neon .r-chart { background:var(--rk-surface); box-shadow:0 0 30px rgba(160,107,255,.07); }
.surface-neon .r-donut { filter:drop-shadow(0 0 6px rgba(160,107,255,.55)); }
.surface-neon .r-bar { box-shadow:0 0 14px rgba(160,107,255,.5); }
.surface-neon .r-callout.insight { box-shadow:0 0 28px rgba(160,107,255,.14); }
""".strip(),

    # idea-synthesis V1 — literary magazine: serif, generous whitespace, drop cap.
    "surface-editorial": r"""
.surface-editorial { font-size:16px; }
.surface-editorial .ed-wrap { padding:6px 24px 8px; }
.ed-masthead { padding:30px 24px 0; }
.ed-rule { height:2px; background:var(--rk-text-hi); opacity:.9; }
.ed-kicker { display:flex; justify-content:space-between; align-items:center; padding:10px 0 0; gap:12px; }
.ed-kicker span { font-family:var(--rk-font-mono); font-size:10.5px; letter-spacing:.2em; text-transform:uppercase; color:var(--rk-text-lo); }
.surface-editorial .r-h1 { font-family:var(--rk-font-display); font-weight:900; font-size:38px; line-height:1.12; letter-spacing:-.01em; margin:26px 0 0; color:var(--rk-text-hi); }
.ed-lead { font-family:var(--rk-font-display); font-weight:500; font-size:19px; line-height:1.62; color:var(--rk-text); margin:20px 0 0; }
.ed-lead::first-letter { font-size:58px; float:left; line-height:.82; padding:6px 12px 0 0; color:var(--rk-accent); font-weight:700; }
.ed-byline { display:flex; align-items:center; gap:10px; flex-wrap:wrap; margin:24px 0 0; padding-bottom:26px; border-bottom:1px solid var(--rk-rule); }
.ed-byline .dot { width:5px; height:5px; border-radius:50%; background:var(--rk-accent); }
.ed-byline span { font-family:var(--rk-font-mono); font-size:11px; letter-spacing:.04em; color:var(--rk-text-lo); }
.surface-editorial .r-h2 { font-family:var(--rk-font-display); font-weight:700; font-size:24px; margin:28px 0 16px; color:var(--rk-text-hi); }
.surface-editorial .r-p { font-size:16px; line-height:1.72; }
.surface-editorial .r-quote { font-size:22px; line-height:1.45; padding:4px 0 4px 22px; margin:4px 0 22px; border-left:3px solid var(--rk-accent); font-style:normal; }
.surface-editorial .r-callout { border-radius:4px; }
""".strip(),

    # idea-synthesis V2 — warm notebook 手帐: paper, dashed stamp, marker highlight.
    "surface-note": r"""
.surface-note { --rk-font-display:"Manrope","Noto Sans SC",sans-serif; background:radial-gradient(circle at 12% 8%,rgba(201,114,46,.06),transparent 30%),var(--rk-bg); }
.surface-note .note-wrap { padding:6px 20px 8px; }
.note-head { padding:26px 20px 20px; }
.note-stamp { display:inline-flex; align-items:center; gap:8px; font-family:var(--rk-font-mono); font-size:11px; letter-spacing:.06em; color:var(--rk-accent); border:1.5px dashed var(--rk-accent); border-radius:999px; padding:5px 12px; transform:rotate(-1.5deg); }
.surface-note .r-h1 { font-size:30px; font-weight:800; line-height:1.2; margin-top:16px; }
.mark { background:linear-gradient(transparent 58%,rgba(201,114,46,.32) 58%,rgba(201,114,46,.32) 94%,transparent 94%); padding:0 2px; font-weight:700; color:var(--rk-text-hi); }
.note-lead { font-size:16px; line-height:1.65; color:var(--rk-text); margin:14px 0 0; }
.note-meta { display:flex; gap:7px; flex-wrap:wrap; margin:18px 0 0; }
.surface-note .r-h2 { font-size:21px; font-weight:800; margin:24px 0 14px; }
.surface-note .r-p { font-size:15.5px; line-height:1.68; }
""".strip(),

    # proposal V1 — deck-doc keynote: light, airy, big type, restrained.
    "surface-deck": r"""
.surface-deck { --rk-font-display:"Manrope","Noto Sans SC",sans-serif; }
.surface-deck .deck-wrap { padding:24px 24px 8px; }
.deck-cover { padding:40px 24px 30px; border-bottom:1px solid var(--rk-rule); }
.deck-label { font-family:var(--rk-font-mono); font-size:11px; letter-spacing:.2em; text-transform:uppercase; color:var(--rk-accent); font-weight:600; }
.surface-deck .r-h1 { font-size:36px; font-weight:800; line-height:1.14; letter-spacing:-.02em; margin:18px 0 0; }
.deck-sub { font-size:17px; line-height:1.55; color:var(--rk-text-mid); margin:16px 0 0; }
.deck-cover-meta { display:flex; gap:20px; flex-wrap:wrap; margin:28px 0 0; }
.deck-cm .k { font-family:var(--rk-font-mono); font-size:10px; letter-spacing:.1em; text-transform:uppercase; color:var(--rk-text-lo); }
.deck-cm .v { font-size:14px; font-weight:700; color:var(--rk-text-hi); margin-top:4px; }
.surface-deck .r-h2 { font-size:24px; font-weight:800; margin:30px 0 16px; letter-spacing:-.01em; }
.surface-deck .r-p { font-size:16px; line-height:1.65; color:var(--rk-text); }
""".strip(),

    # proposal V2 — forest deck: deep green, calm, radiant cover glow.
    "surface-forest2": r"""
.surface-forest2 { --rk-font-display:"Manrope","Noto Sans SC",sans-serif; background:radial-gradient(90% 60% at 50% -5%,rgba(79,179,122,.16),transparent 65%),var(--rk-bg); }
.surface-forest2 .fst-wrap { padding:20px 24px 8px; }
.fst-cover { padding:34px 24px 28px; }
.fst-label { display:inline-flex; align-items:center; gap:8px; font-family:var(--rk-font-mono); font-size:11px; letter-spacing:.16em; text-transform:uppercase; color:var(--rk-accent); font-weight:600; border:1px solid var(--rk-border); border-radius:999px; padding:5px 12px; }
.surface-forest2 .r-h1 { font-size:34px; font-weight:800; line-height:1.16; margin:18px 0 0; }
.fst-sub { font-size:16.5px; line-height:1.58; color:var(--rk-text-mid); margin:16px 0 0; }
.fst-meta { display:flex; gap:10px; flex-wrap:wrap; margin:22px 0 0; }
.surface-forest2 .r-h2 { font-size:22px; font-weight:800; margin:26px 0 14px; }
.surface-forest2 .r-p { font-size:15.5px; line-height:1.66; }
""".strip(),

    # digest V1 — magazine-lite: warm card flow + 4-up stat strip.
    "surface-mag": r"""
.surface-mag { --rk-font-display:"Manrope","Noto Sans SC",sans-serif; }
.surface-mag .mag-wrap { padding:24px 20px 8px; }
.mag-head { padding:28px 20px 18px; }
.mag-kicker { font-family:var(--rk-font-mono); font-size:11px; letter-spacing:.16em; text-transform:uppercase; color:var(--rk-accent); font-weight:600; }
.surface-mag .r-h1 { font-size:32px; font-weight:800; line-height:1.14; margin:12px 0 0; }
.mag-range { font-family:var(--rk-font-mono); font-size:13px; color:var(--rk-text-mid); margin-top:10px; }
.mag-overview { font-size:16px; line-height:1.6; color:var(--rk-text); margin:16px 0 0; }
.mag-strip { display:grid; grid-template-columns:repeat(4,1fr); gap:1px; background:var(--rk-rule); border:1px solid var(--rk-border); border-radius:var(--rk-r); overflow:hidden; margin:0 20px; }
.mag-strip-i { background:var(--rk-surface); padding:14px 8px; text-align:center; }
.mag-strip-n { font-size:22px; font-weight:800; color:var(--rk-text-hi); line-height:1; font-variant-numeric:tabular-nums; }
.mag-strip-l { font-size:10.5px; color:var(--rk-text-mid); margin-top:6px; }
.surface-mag .r-h2 { font-size:19px; font-weight:800; margin:26px 0 14px; }
""".strip(),

    # digest V2 — weekly dashboard: cool dark, structured, data-dense.
    "surface-wdash": r"""
.surface-wdash .wd-head { padding:26px 20px 20px; border-bottom:1px solid var(--rk-rule); background:radial-gradient(120% 80% at 90% -10%,rgba(79,140,255,.14),transparent 60%),var(--rk-bg); }
.surface-wdash .r-h1 { font-size:26px; }
.wd-range { font-family:var(--rk-font-mono); font-size:12px; color:var(--rk-text-lo); margin-top:8px; letter-spacing:.04em; }
.surface-wdash .wd-body { padding:22px 20px 8px; }
.surface-wdash .r-h2 { margin:24px 0 12px; }
""".strip(),
}


# ── morning briefing (§14.6) — immersive A/B skins, ported verbatim from
#    morning-brief-a/b.html. NOT block-kit surfaces: agents/morning_briefing.py
#    emits this markup directly from structured data (events/todos/recap), so
#    these live in their own dict instead of SURFACE_CSS.
MORNING_CSS = {
    # DAY A — sunrise, warm, emotional
    "mb-a": r"""
.mb { --bg:#1a1308; --ink:#fff6e9;
  --t-hi:#fff8ee; --t:rgba(255,244,228,.86); --t-mid:rgba(255,240,220,.6); --t-lo:rgba(255,236,212,.42);
  --acc:#ff9e5e; --acc2:#ffd089; --good:#7fd49a; --over:#ff9e5e; --card:rgba(255,235,210,.07); --border:rgba(255,225,190,.14);
  --rk-font-mono:"JetBrains Mono", monospace;
  background:var(--bg); color:var(--t); font-family:"Manrope","Noto Sans SC",sans-serif;
  min-height:100%; overflow-x:hidden; margin:0; width:100%; }
html, body { margin:0; padding:0; background:#1a1308; }
.mb-hero { position:relative; padding:30px 24px 34px; overflow:hidden;
  background: radial-gradient(120% 80% at 78% 6%, #ffb368 0%, rgba(255,150,80,.55) 18%, transparent 52%),
    linear-gradient(180deg, #3a2410 0%, #271a0c 55%, var(--bg) 100%); }
.mb-sun { position:absolute; top:-40px; right:-30px; width:200px; height:200px; border-radius:50%;
  background:radial-gradient(circle, #fff0d0 0%, #ffc070 40%, transparent 70%); filter:blur(6px); opacity:.9; }
@media (prefers-reduced-motion: no-preference){ .mb-sun{ animation: mbsun 6s ease-in-out infinite; } }
@keyframes mbsun { 0%,100%{ transform:scale(1); opacity:.85 } 50%{ transform:scale(1.08); opacity:1 } }
.mb-hero > * { position:relative; }
.mb-top { display:flex; align-items:center; gap:12px; }
.mb-pet { width:60px; height:60px; flex:0 0 auto; }
.mb-pet canvas{ width:100%; height:100%; image-rendering:pixelated; }
.mb-date { font-family:var(--rk-font-mono); font-size:12px; letter-spacing:.08em; color:var(--t-mid); }
.mb-clock { font-family:var(--rk-font-mono); font-size:13px; color:var(--acc2); font-weight:600; }
.mb-greet { font-size:46px; font-weight:800; color:var(--t-hi); line-height:1.05; margin:22px 0 0; letter-spacing:-.02em; }
.mb-greet small { display:block; font-size:17px; font-weight:600; color:var(--t-mid); margin-top:10px; letter-spacing:0; }
.mb-chips { display:flex; gap:8px; flex-wrap:wrap; margin:20px 0 0; }
.mb-chip { display:inline-flex; align-items:center; gap:6px; font-size:12.5px; font-weight:600; color:var(--t-hi);
  background:rgba(255,235,205,.1); border:1px solid var(--border); border-radius:999px; padding:7px 13px; }
.mb-motto { margin:22px 0 0; font-size:15px; line-height:1.55; color:var(--t); font-style:italic;
  border-left:2px solid var(--acc); padding-left:14px; }
""".strip(),

    # DAY B — cool cloudy pre-dawn, centered, calm
    "mb-b": r"""
.mb { --bg:#0b1024; --t-hi:#eef1ff; --t:rgba(226,232,255,.85); --t-mid:rgba(200,210,245,.6); --t-lo:rgba(180,192,235,.42);
  --acc:#9db4ff; --acc2:#6be0d0; --good:#6be0d0; --over:#ffa8c0;
  --card:rgba(150,170,255,.06); --border:rgba(150,170,255,.16);
  --rk-font-mono:"JetBrains Mono", monospace;
  background:var(--bg); color:var(--t); font-family:"Manrope","Noto Sans SC",sans-serif; min-height:100%; overflow-x:hidden; margin:0; width:100%; }
html, body { margin:0; padding:0; background:#0b1024; }
.mb-hero { position:relative; padding:34px 24px 30px; text-align:center; overflow:hidden;
  background: radial-gradient(90% 60% at 50% -10%, rgba(157,180,255,.28), transparent 60%),
    radial-gradient(70% 50% at 80% 20%, rgba(107,224,208,.12), transparent 60%),
    linear-gradient(180deg,#161d3e 0%, #0e1430 50%, var(--bg) 100%); }
.mb-cloud { position:absolute; border-radius:50%; background:radial-gradient(circle,rgba(200,210,255,.16),transparent 70%); filter:blur(4px); }
.mb-cloud.a{ width:160px;height:100px; top:10px; left:-30px; }
.mb-cloud.b{ width:200px;height:120px; top:-20px; right:-40px; }
.mb-hero > * { position:relative; }
.mb-date { font-family:var(--rk-font-mono); font-size:12px; letter-spacing:.1em; color:var(--t-mid); }
.mb-pet { width:88px; height:88px; margin:14px auto 0; }
.mb-pet canvas{ width:100%; height:100%; image-rendering:pixelated; }
.mb-greet { font-size:38px; font-weight:800; color:var(--t-hi); line-height:1.1; margin:14px 0 0; letter-spacing:-.02em; }
.mb-greet small { display:block; font-size:15px; font-weight:500; color:var(--t-mid); margin-top:10px; }
.mb-chips { display:flex; gap:8px; justify-content:center; flex-wrap:wrap; margin:18px 0 0; }
.mb-chip { font-size:12.5px; font-weight:600; color:var(--t-hi); background:rgba(150,170,255,.1); border:1px solid var(--border); border-radius:999px; padding:7px 13px; }
.mb-focus { margin:24px 0 0; padding:22px; border-radius:22px; position:relative; overflow:hidden;
  background:linear-gradient(135deg, rgba(157,180,255,.16), rgba(107,224,208,.08)); border:1px solid var(--border); }
.mb-focus-k { font-family:var(--rk-font-mono); font-size:11px; letter-spacing:.16em; text-transform:uppercase; color:var(--acc); font-weight:700; }
.mb-focus-t { font-size:22px; font-weight:800; color:var(--t-hi); margin:10px 0 6px; line-height:1.25; }
.mb-focus-d { font-size:13.5px; color:var(--t-mid); line-height:1.5; }
.mb-focus-time { display:inline-flex; align-items:center; gap:6px; margin-top:14px; font-family:var(--rk-font-mono); font-size:12px; font-weight:700; color:var(--acc2); border:1px solid var(--border); border-radius:999px; padding:5px 12px; }
.mb-ring-wrap { display:flex; align-items:center; gap:18px; background:var(--card); border:1px solid var(--border); border-radius:20px; padding:18px; }
.mb-ring { flex:0 0 auto; filter:drop-shadow(0 0 6px rgba(157,180,255,.4)); }
.mb-ring-info { flex:1; }
.mb-ring-n { font-size:30px; font-weight:800; color:var(--t-hi); line-height:1; }
.mb-ring-l { font-size:13px; color:var(--t-mid); margin-top:6px; line-height:1.45; }
.mb-line { display:flex; align-items:center; gap:14px; padding:12px 0; border-bottom:1px solid var(--border); }
.mb-line:last-child{ border-bottom:none; }
.mb-line-t { font-family:var(--rk-font-mono); font-size:13px; font-weight:700; color:var(--acc); width:46px; flex:0 0 auto; }
.mb-line-x { flex:1; font-size:14.5px; color:var(--t); }
.mb-line-dot { width:8px;height:8px;border-radius:50%; background:var(--acc); flex:0 0 auto; }
""".strip(),

    # shared body pieces (identical or near-identical across A/B)
    "mb-shared": r"""
.mb-body { padding:4px 20px 0; }
.mb-sec { padding:26px 4px 0; }
.mb-sec-h { display:flex; align-items:center; justify-content:space-between; margin-bottom:14px; }
.mb-sec-t { font-size:13px; font-family:var(--rk-font-mono); letter-spacing:.14em; text-transform:uppercase; color:var(--t-lo); font-weight:600; margin-bottom:0; }
.mb-sec > .mb-sec-t { display:block; margin-bottom:14px; }
.mb-sec-n { font-size:12px; color:var(--acc); font-weight:700; }
.mb-sched { display:flex; flex-direction:column; gap:10px; }
.mb-evt { display:flex; gap:14px; align-items:stretch; background:var(--card); border:1px solid var(--border); border-radius:16px; padding:14px 16px; }
.mb-evt-time { font-family:var(--rk-font-mono); font-size:13px; font-weight:700; color:var(--acc2); width:46px; flex:0 0 auto; padding-top:1px; }
.mb-evt-bar { width:3px; border-radius:3px; background:var(--acc); flex:0 0 auto; }
.mb-evt-b { flex:1; }
.mb-evt-t { font-size:15px; font-weight:700; color:var(--t-hi); }
.mb-evt-d { font-size:12.5px; color:var(--t-mid); margin-top:3px; }
.mb-todo { display:flex; align-items:center; gap:12px; padding:13px 16px; background:var(--card); border:1px solid var(--border); border-radius:14px; margin-bottom:8px; }
.mb-todo-c { width:20px; height:20px; border-radius:7px; border:1.5px solid var(--border); flex:0 0 auto; }
.mb-todo.done .mb-todo-c { background:var(--good); border-color:var(--good); }
.mb-todo-t { flex:1; font-size:14.5px; color:var(--t); }
.mb-todo.over { border-color:color-mix(in srgb, var(--over) 40%, transparent); }
.mb-todo .tag { font-family:var(--rk-font-mono); font-size:10px; font-weight:700; letter-spacing:.06em; color:var(--over); border:1px solid color-mix(in srgb, var(--over) 40%, transparent); border-radius:999px; padding:3px 8px; }
.mb-recap { display:grid; grid-template-columns:repeat(3,1fr); gap:10px; }
.mb-rc { background:var(--card); border:1px solid var(--border); border-radius:16px; padding:16px 12px; text-align:center; }
.mb-rc-n { font-size:26px; font-weight:800; color:var(--t-hi); line-height:1; }
.mb-rc-l { font-size:11px; color:var(--t-mid); margin-top:7px; }
.mb-feed { margin-top:10px; display:flex; flex-direction:column; gap:8px; }
.mb-rec { display:flex; align-items:center; gap:12px; background:var(--card); border:1px solid var(--border); border-radius:13px; padding:11px 14px; }
.mb-rec-ic { width:28px; height:28px; border-radius:9px; flex:0 0 auto; display:flex; align-items:center; justify-content:center; font-size:14px; background:color-mix(in srgb, var(--sc) 18%, transparent); border:1px solid color-mix(in srgb, var(--sc) 40%, transparent); }
.mb-rec-b { flex:1; min-width:0; }
.mb-rec-t { font-size:14px; color:var(--t-hi); font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.mb-rec-s { font-size:11.5px; color:var(--t-mid); margin-top:1px; }
.mb-rec-skill { font-family:var(--rk-font-mono); font-size:10px; font-weight:700; letter-spacing:.04em; color:var(--sc); border:1px solid color-mix(in srgb, var(--sc) 40%, transparent); border-radius:999px; padding:3px 8px; flex:0 0 auto; }
.mb-rec-skill.custom::before { content:"✦ "; }
.mb-empty { background:var(--card); border:1px dashed var(--border); border-radius:14px; padding:16px; font-size:13.5px; color:var(--t-mid); text-align:center; }
.mb-swipe { text-align:center; padding:30px 0 8px; }
.mb-swipe-icon { font-size:18px; color:var(--t-lo); }
@media (prefers-reduced-motion: no-preference){ .mb-swipe-icon{ animation: mbbob 1.8s ease-in-out infinite; display:inline-block; } }
@keyframes mbbob { 0%,100%{transform:translateY(0)} 50%{transform:translateY(5px)} }
.mb-swipe-t { font-size:12.5px; color:var(--t-lo); margin-top:6px; font-family:var(--rk-font-mono); letter-spacing:.06em; }
.mb .r-sign { margin-top:18px; padding:22px 20px calc(22px + env(safe-area-inset-bottom)); border-top:1px solid var(--border); display:flex; align-items:center; gap:14px; background:linear-gradient(180deg, transparent, rgba(157,180,255,.05)); }
.mb .r-sign-pet { width:52px; height:52px; flex:0 0 auto; position:relative; }
.mb .r-sign-pet canvas { width:100%; height:100%; image-rendering:pixelated; }
.mb .r-sign-meta { flex:1; min-width:0; }
.mb .r-sign-mark { font-weight:700; color:var(--t-hi); font-size:15px; display:flex; align-items:center; gap:7px; }
.mb .r-sign-spark { color:var(--acc); }
.mb .r-sign-tag { font-family:var(--rk-font-mono); font-size:10.5px; color:var(--t-lo); letter-spacing:.04em; margin-top:3px; }
@media (prefers-reduced-motion:no-preference) {
  html.rk-anim .mb [data-reveal] { opacity:0; transform:translateY(16px); }
  html.rk-anim .mb [data-reveal].is-in { opacity:1; transform:none; transition:opacity .6s cubic-bezier(.2,.7,.3,1), transform .6s cubic-bezier(.2,.7,.3,1); }
}
""".strip(),
}
