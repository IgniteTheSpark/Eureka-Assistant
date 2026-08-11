from app.domains.reports.presentation.catalog import ColorScheme, StyleVariant


# Ported from the legacy Report surface/palette system. Theme V2 owns this copy:
# it has no runtime import, remote font, animation script, or pet dependency.
BASE_CSS = r"""
*,*::before,*::after{box-sizing:border-box}
html,body{margin:0;padding:0;min-height:100%;background:#0c1118}
body{font-family:Geist,"Noto Sans SC",-apple-system,"Segoe UI",system-ui,sans-serif}
.report{
  --rk-bg:#0b1220;--rk-bg-2:#11192b;--rk-surface:rgba(255,255,255,.04);--rk-surface-2:rgba(255,255,255,.06);
  --rk-border:rgba(255,255,255,.10);--rk-rule:rgba(255,255,255,.07);
  --rk-text-hi:#f3f6fb;--rk-text:rgba(255,255,255,.84);--rk-text-mid:rgba(255,255,255,.62);--rk-text-lo:rgba(255,255,255,.42);
  --rk-accent:#6f9eff;--rk-accent-2:#8ab4ff;--rk-accent-soft:rgba(111,158,255,.16);
  --rk-good:#43c98a;--rk-bad:#f0666f;--rk-warn:#e7b35a;--rk-r:16px;--rk-r-sm:10px;
  width:100%;min-height:100vh;background:var(--rk-bg);color:var(--rk-text);
  font-family:Geist,"Noto Sans SC",-apple-system,"Segoe UI",system-ui,sans-serif;
  font-size:15px;line-height:1.65;-webkit-font-smoothing:antialiased;overflow-x:hidden
}
.pal-dashboard{--rk-bg:#0c1118;--rk-bg-2:#131a24;--rk-surface:#141b26;--rk-surface-2:#1a2330;--rk-border:rgba(150,180,220,.13);--rk-rule:rgba(150,180,220,.09);--rk-text-hi:#eaf1fb;--rk-text:rgba(225,235,248,.82);--rk-text-mid:rgba(200,215,235,.58);--rk-text-lo:rgba(180,198,222,.40);--rk-accent:#4f8cff;--rk-accent-2:#6fa6ff;--rk-accent-soft:rgba(79,140,255,.15);--rk-good:#35c98c;--rk-bad:#ff6b73;--rk-warn:#f0b35a;--rk-r:14px;--rk-r-sm:9px}
.pal-neon{--rk-bg:#06070f;--rk-bg-2:#0c0e1c;--rk-surface:rgba(140,120,255,.05);--rk-surface-2:rgba(140,120,255,.09);--rk-border:rgba(150,130,255,.18);--rk-rule:rgba(150,130,255,.12);--rk-text-hi:#f4f0ff;--rk-text:rgba(228,224,255,.82);--rk-text-mid:rgba(200,194,240,.58);--rk-text-lo:rgba(180,172,225,.42);--rk-accent:#a06bff;--rk-accent-2:#2ee6c6;--rk-accent-soft:rgba(160,107,255,.16);--rk-good:#2ee6c6;--rk-bad:#ff5d8f;--rk-warn:#ffd166;--rk-r:18px;--rk-r-sm:11px}
.pal-ink{--rk-bg:#14130f;--rk-bg-2:#1c1a14;--rk-surface:rgba(245,238,222,.04);--rk-surface-2:rgba(245,238,222,.07);--rk-border:rgba(232,224,205,.14);--rk-rule:rgba(232,224,205,.10);--rk-text-hi:#f6f1e6;--rk-text:rgba(244,238,224,.83);--rk-text-mid:rgba(228,220,200,.60);--rk-text-lo:rgba(210,200,178,.42);--rk-accent:#d98a4b;--rk-accent-2:#e6a96b;--rk-accent-soft:rgba(217,138,75,.15);--rk-good:#8caa5a;--rk-bad:#d96a5a;--rk-warn:#d9a84b;--rk-r:6px;--rk-r-sm:4px}
.pal-minimal{--rk-bg:#f6f5f1;--rk-bg-2:#fbfaf7;--rk-surface:#fff;--rk-surface-2:#fbfaf6;--rk-border:rgba(30,28,22,.10);--rk-rule:rgba(30,28,22,.07);--rk-text-hi:#1a1813;--rk-text:rgba(26,24,19,.82);--rk-text-mid:rgba(26,24,19,.56);--rk-text-lo:rgba(26,24,19,.40);--rk-accent:#2f63d6;--rk-accent-2:#4f80e6;--rk-accent-soft:rgba(47,99,214,.10);--rk-good:#1f9d63;--rk-bad:#d8483f;--rk-warn:#c98a1e;--rk-r:12px;--rk-r-sm:8px}
.pal-warm{--rk-bg:#f3ece0;--rk-bg-2:#faf5ec;--rk-surface:#fffaf1;--rk-surface-2:#fdf4e6;--rk-border:rgba(80,55,30,.12);--rk-rule:rgba(80,55,30,.08);--rk-text-hi:#2a2015;--rk-text:rgba(50,38,24,.84);--rk-text-mid:rgba(70,54,34,.58);--rk-text-lo:rgba(90,70,46,.42);--rk-accent:#c9722e;--rk-accent-2:#e09349;--rk-accent-soft:rgba(201,114,46,.13);--rk-good:#5a8a3c;--rk-bad:#c75440;--rk-warn:#c9942e;--rk-r:16px;--rk-r-sm:10px}
.pal-forest{--rk-bg:#0c1410;--rk-bg-2:#11201a;--rk-surface:rgba(180,230,200,.045);--rk-surface-2:rgba(180,230,200,.08);--rk-border:rgba(160,220,185,.15);--rk-rule:rgba(160,220,185,.10);--rk-text-hi:#eef6ef;--rk-text:rgba(225,240,228,.83);--rk-text-mid:rgba(195,220,200,.58);--rk-text-lo:rgba(175,205,182,.42);--rk-accent:#4fb37a;--rk-accent-2:#79d29a;--rk-accent-soft:rgba(79,179,122,.15);--rk-good:#5bc98a;--rk-bad:#e07a6a;--rk-warn:#d9b15a;--rk-r:20px;--rk-r-sm:12px}
.r-masthead{padding:30px 22px 26px;border-bottom:1px solid var(--rk-rule)}
.r-eyebrow{margin:0;color:var(--rk-accent);font:700 10px/1.4 ui-monospace,"SFMono-Regular",monospace;letter-spacing:.18em;text-transform:uppercase}
.r-h1{margin:13px 0 0;color:var(--rk-text-hi);font-size:clamp(30px,8vw,42px);line-height:1.12;letter-spacing:-.025em;text-wrap:balance}
.r-body{padding:26px 20px 8px}.r-block{margin:0 0 26px}.r-p{margin:0;color:var(--rk-text);font-size:15.5px;line-height:1.72}.r-p strong{color:var(--rk-text-hi)}
.r-h2,.r-h3,.r-h4{color:var(--rk-text-hi);line-height:1.25;margin:34px 0 15px}.r-h2{font-size:22px}.r-h3{font-size:18px}.r-h4{font-size:16px}
.r-list{margin:0;padding-left:22px}.r-list li{padding:4px 0}.r-kpi{display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:10px}
.r-kpi-item{padding:15px 13px;background:var(--rk-surface);border:1px solid var(--rk-border);border-radius:var(--rk-r-sm)}
.r-kpi-label{color:var(--rk-text-lo);font:600 10.5px/1.3 ui-monospace,"SFMono-Regular",monospace;letter-spacing:.07em;text-transform:uppercase}
.r-kpi-n{margin-top:9px;color:var(--rk-text-hi);font-size:24px;font-weight:760;line-height:1.05;font-variant-numeric:tabular-nums}
.r-timeline{position:relative;padding-left:24px}.r-timeline::before{content:"";position:absolute;left:5px;top:5px;bottom:6px;width:2px;background:var(--rk-rule)}
.r-tl-item{position:relative;padding-bottom:18px}.r-tl-item:last-child{padding-bottom:0}.r-tl-item::before{content:"";position:absolute;left:-24px;top:5px;width:11px;height:11px;border-radius:50%;background:var(--rk-accent);box-shadow:0 0 0 4px var(--rk-bg)}
.r-tl-date{color:var(--rk-accent);font:650 11px/1.4 ui-monospace,"SFMono-Regular",monospace}.r-tl-text{margin-top:3px;color:var(--rk-text);font-size:14px}
.r-rank{list-style:none;margin:0;padding:0;display:flex;flex-direction:column}.r-rank li{display:flex;gap:13px;align-items:center;min-height:48px;padding:11px 14px;background:var(--rk-surface);border:1px solid var(--rk-border);border-bottom:0}.r-rank li:first-child{border-radius:var(--rk-r-sm) var(--rk-r-sm) 0 0}.r-rank li:last-child{border-bottom:1px solid var(--rk-border);border-radius:0 0 var(--rk-r-sm) var(--rk-r-sm)}.r-rank-i{color:var(--rk-accent);font:700 12px ui-monospace,"SFMono-Regular",monospace}.r-rank-lbl{color:var(--rk-text)}
.r-callout{position:relative;padding:17px 18px;border:1px solid var(--rk-border);border-radius:var(--rk-r);background:var(--rk-accent-soft)}.r-callout::before{content:"";position:absolute;left:0;top:14px;bottom:14px;width:3px;border-radius:3px;background:var(--tone,var(--rk-accent))}.r-callout.insight{--tone:var(--rk-accent)}.r-callout.success{--tone:var(--rk-good)}.r-callout.warn{--tone:var(--rk-warn)}.r-callout-tag{color:var(--tone);font:700 10px ui-monospace,"SFMono-Regular",monospace;letter-spacing:.16em}.r-callout p{margin:8px 0 0}
.r-quote{margin:0;padding:5px 0 5px 19px;border-left:2px solid var(--rk-accent);color:var(--rk-text-hi);font-family:"Noto Serif SC","Songti SC",serif;font-size:18px;line-height:1.55}.r-quote cite{display:block;margin-top:9px;color:var(--rk-text-lo);font:500 10px ui-monospace,"SFMono-Regular",monospace;font-style:normal;letter-spacing:.06em}
.r-table-wrap{overflow-x:auto;border:1px solid var(--rk-border);border-radius:var(--rk-r-sm)}.r-compare{width:100%;border-collapse:collapse;font-size:13px}.r-compare th,.r-compare td{padding:11px 12px;text-align:left;border-bottom:1px solid var(--rk-rule)}.r-compare th{color:var(--rk-text-lo);font:600 10px ui-monospace,"SFMono-Regular",monospace;letter-spacing:.06em}.r-compare td:first-child{color:var(--rk-text-hi);font-weight:650}.r-compare tr:last-child td{border-bottom:0}
.r-chart{padding:16px;background:var(--rk-surface);border:1px solid var(--rk-border);border-radius:var(--rk-r)}.r-chart svg{display:block;width:100%;height:auto}
.r-illustration{margin:4px 0 30px;border:1px solid var(--rk-border);border-radius:var(--rk-r);overflow:hidden;background:var(--rk-surface-2)}.r-illustration img{display:block;width:100%;height:auto}
.r-illustration--pending{height:clamp(180px,52vw,320px);position:relative;background:linear-gradient(135deg,var(--rk-surface),var(--rk-surface-2))}.r-illustration-placeholder{position:absolute;inset:0;background:radial-gradient(circle at 30% 25%,var(--rk-accent-soft),transparent 52%),linear-gradient(110deg,transparent 20%,var(--rk-border) 48%,transparent 76%);opacity:.58}
.r-actions,.r-sources{margin:34px 20px 0;padding-top:22px;border-top:1px solid var(--rk-rule)}.r-section-label{margin:0 0 12px;color:var(--rk-accent);font:700 10.5px ui-monospace,"SFMono-Regular",monospace;letter-spacing:.16em;text-transform:uppercase}
.r-action-list{overflow:hidden;border:1px solid var(--rk-border);border-radius:var(--rk-r);background:var(--rk-surface)}.r-action{display:flex;align-items:center;gap:12px;min-height:48px;padding:12px 15px;border-bottom:1px solid var(--rk-rule)}.r-action:last-child{border-bottom:0}.r-action-check{width:20px;height:20px;flex:0 0 auto;border:1.5px solid var(--rk-border);border-radius:6px}.r-action-title{flex:1;color:var(--rk-text-hi);font-size:14px}.r-action-due{color:var(--rk-text-lo);font:500 10px ui-monospace,"SFMono-Regular",monospace}
.r-source-list{list-style:none;margin:0;padding:0}.r-source{padding:10px 0;border-bottom:1px solid var(--rk-rule)}.r-source:last-child{border-bottom:0}.r-source a{color:var(--rk-text-hi);font-weight:650;text-decoration:none}.r-source-meta{margin-top:3px;color:var(--rk-text-lo);font:500 10.5px ui-monospace,"SFMono-Regular",monospace}
.r-sign{margin-top:36px;padding:22px 20px calc(24px + env(safe-area-inset-bottom));border-top:1px solid var(--rk-rule);background:linear-gradient(180deg,transparent,var(--rk-bg-2))}.r-sign-mark{color:var(--rk-text-hi);font-size:13px;font-weight:750;letter-spacing:.12em}.r-sign-tag{margin-top:4px;color:var(--rk-text-lo);font-size:11px}
pre{overflow:auto;padding:14px;border-radius:var(--rk-r-sm);background:var(--rk-surface);color:var(--rk-text)}code{font-family:ui-monospace,"SFMono-Regular",monospace}
@media(min-width:720px){.report{width:min(100%,760px);margin:0 auto}.r-masthead{padding-left:34px;padding-right:34px}.r-body{padding-left:34px;padding-right:34px}.r-actions,.r-sources{margin-left:34px;margin-right:34px}}
@media(prefers-reduced-motion:reduce){*,*::before,*::after{scroll-behavior:auto!important;transition:none!important;animation:none!important}}
""".strip()


SURFACE_CSS: dict[str, str] = {
    "surface-dashboard": r"""
.surface-dashboard .r-masthead{background:radial-gradient(120% 90% at 80% -10%,rgba(79,140,255,.16),transparent 60%),var(--rk-bg)}
.surface-dashboard .r-h1{font-size:34px}.surface-dashboard .r-body{padding-top:24px}.surface-dashboard .r-kpi{grid-template-columns:repeat(3,1fr)}
""".strip(),
    "surface-neon": r"""
.surface-neon{background:radial-gradient(70% 32% at 50% 0%,rgba(160,107,255,.18),transparent 72%),var(--rk-bg)}
.surface-neon .r-masthead{position:relative;padding-top:36px;border-color:rgba(46,230,198,.12)}.surface-neon .r-masthead::after{content:"";position:absolute;inset:0;pointer-events:none;opacity:.35;background-image:linear-gradient(var(--rk-rule) 1px,transparent 1px),linear-gradient(90deg,var(--rk-rule) 1px,transparent 1px);background-size:28px 28px;mask-image:linear-gradient(#000,transparent)}
.surface-neon .r-masthead>*{position:relative;z-index:1}.surface-neon .r-h1{text-shadow:0 0 30px rgba(160,107,255,.42)}.surface-neon .r-kpi-item,.surface-neon .r-chart{box-shadow:0 0 26px rgba(160,107,255,.08)}
""".strip(),
    "surface-editorial": r"""
.surface-editorial{font-family:"Noto Serif SC","Songti SC",serif}.surface-editorial .r-masthead{padding-top:35px}.surface-editorial .r-masthead::before{content:"REKA INSIGHTS / EDITORIAL";display:block;padding-top:10px;border-top:2px solid var(--rk-text-hi);color:var(--rk-text-lo);font:600 10px ui-monospace,"SFMono-Regular",monospace;letter-spacing:.16em}.surface-editorial .r-eyebrow{display:none}.surface-editorial .r-h1{font-size:40px;font-weight:900}.surface-editorial .r-p{font-family:"Noto Serif SC","Songti SC",serif;font-size:16px}.surface-editorial .r-h2{font-family:"Noto Serif SC","Songti SC",serif;font-size:25px}.surface-editorial .r-callout{border-radius:4px}
""".strip(),
    "surface-note": r"""
.surface-note{background:radial-gradient(circle at 12% 8%,rgba(201,114,46,.07),transparent 30%),var(--rk-bg)}.surface-note .r-masthead{border-bottom:0}.surface-note .r-eyebrow{display:inline-block;padding:5px 12px;border:1.5px dashed var(--rk-accent);border-radius:999px;transform:rotate(-1.2deg)}.surface-note .r-h1{font-size:33px;font-weight:820}.surface-note .r-h2{font-weight:820}.surface-note .r-callout{box-shadow:3px 4px 0 rgba(201,114,46,.08)}
""".strip(),
    "surface-deck": r"""
.surface-deck .r-masthead{padding-top:46px;padding-bottom:34px}.surface-deck .r-h1{max-width:660px;font-size:42px;font-weight:820}.surface-deck .r-eyebrow{letter-spacing:.22em}.surface-deck .r-body{padding-top:30px}.surface-deck .r-h2{font-size:25px;font-weight:820}.surface-deck .r-p{font-size:16px}
""".strip(),
    "surface-forest2": r"""
.surface-forest2{background:radial-gradient(90% 44% at 50% -5%,rgba(79,179,122,.17),transparent 65%),var(--rk-bg)}.surface-forest2 .r-masthead{padding-top:38px;border-bottom:0}.surface-forest2 .r-eyebrow{display:inline-flex;padding:5px 12px;border:1px solid var(--rk-border);border-radius:999px}.surface-forest2 .r-h1{font-size:38px;font-weight:820}.surface-forest2 .r-kpi-item{border-radius:16px}
""".strip(),
    "surface-mag": r"""
.surface-mag .r-masthead{padding-top:34px;border-bottom:0}.surface-mag .r-h1{font-size:36px;font-weight:820}.surface-mag .r-body{padding-top:12px}.surface-mag .r-body>.r-block{padding:17px;border:1px solid var(--rk-border);border-radius:var(--rk-r);background:var(--rk-surface)}.surface-mag .r-body>.r-kpi{padding:0;border:0;background:transparent}
""".strip(),
    "surface-wdash": r"""
.surface-wdash .r-masthead{background:radial-gradient(120% 80% at 90% -10%,rgba(79,140,255,.14),transparent 60%),var(--rk-bg)}.surface-wdash .r-h1{font-size:31px}.surface-wdash .r-body{padding-top:22px}.surface-wdash .r-h2{font-size:19px}.surface-wdash .r-block{margin-bottom:20px}
""".strip(),
}


def stylesheet(variant: StyleVariant, color_scheme: ColorScheme) -> str:
    return (
        f":root{{color-scheme:{color_scheme}}}\n"
        + BASE_CSS
        + "\n"
        + SURFACE_CSS[variant.surface]
    )
