"""
Designed render path (ported from the design handoff) — §6.5 surface × palette ×
block kit. ADDITIVE + non-breaking: `report_render.render_report` dispatches only
genres listed in `_VARIANTS` here; every other genre keeps the legacy renderer.

Reuses report_render's parser + helpers (single source for md parsing). Emits the
design's exact markup, styled by report_styles.{BASE_CSS, SURFACE_CSS}. The footer
signature mounts the **real user pet** via the shared __REKA_GENE__ + _REKA_SIGN_JS
(NOT the design package's placeholder mascot).
"""
from __future__ import annotations

import json
import re
from typing import Optional

from agents.report_styles import BASE_CSS, SURFACE_CSS
from agents.report_render import (
    _parse_frontmatter, _split_blocks, _inline, _esc, _fmt, _is_block_start,
    _split_kpi_value, _seed, _REKA_SIGN_JS,
)

# genre → [(palette class, surface class)]; seed picks one (no two consecutive same).
_VARIANTS: dict[str, list[tuple[str, str]]] = {
    "data-report": [("pal-dashboard", "surface-dashboard"), ("pal-neon", "surface-neon")],
}
_BODY_WRAP = {"surface-dashboard": "dash-grid", "surface-neon": "neon-body"}
_GENRE_LABEL = {
    "data-report": ("数据复盘", "DATA REPORT"), "idea-synthesis": ("灵感综合", "SYNTHESIS"),
    "proposal": ("提案", "PROPOSAL"), "digest": ("概览", "DIGEST"),
}
# Categorical series colors for donut segments / multi-series legends. Must be
# DISTINCT HUES (not the palette's accent + accent-2, which are sibling shades →
# two near-identical blues, unreadable). A fixed, accessible set that reads on
# both dark and light palettes (mirrors the §8.3 domain hues). Single-series bars
# use the palette accent gradient (CSS), so only multi-category charts hit this.
_SERIES = ["#4f8cff", "#8a6cff", "#f0b35a", "#35c98c", "#ff6b73", "#2bb6c4", "#d99a2e", "#9b8cff"]
def _sv(i: int) -> str: return _SERIES[i % len(_SERIES)]


def has_variant(genre: str) -> bool:
    return genre in _VARIANTS


# ── block renderers (design markup) ───────────────────────────────────────────
def _kpi(content: str) -> str:
    items = []
    for line in content.splitlines():
        line = line.strip()
        if not line or ":" not in line:
            continue
        k, v = line.split(":", 1)
        main, sub = _split_kpi_value(v.strip())
        sub_html = f'<div class="r-kpi-sub">{_esc(sub)}</div>' if sub else ""
        items.append(
            f'<div class="r-kpi-item"><div class="r-kpi-label">{_esc(k.strip())}</div>'
            f'<div class="r-kpi-n" data-count>{_esc(main)}</div>{sub_html}</div>'
        )
    if not items:
        return ""
    # Grid columns by count so it never strands a lonely row (5 → hero+4→2×2 etc.):
    # 2/4 → 2 cols, otherwise 3. (Hero is pulled into the masthead before this.)
    cols = 2 if len(items) in (2, 4) else 3
    return (f'<div class="r-block" data-reveal>'
            f'<div class="r-kpi" style="grid-template-columns:repeat({cols},1fr)">{"".join(items)}</div></div>')


def _bars(series: list[dict]) -> str:
    vals = [abs(float(s.get("value", 0) or 0)) for s in series]
    mx = max(vals) or 1
    cols = []
    for k, s in enumerate(series):
        v = float(s.get("value", 0) or 0)
        h = max(3, round(abs(v) / mx * 100))
        cols.append(
            f'<div class="r-bar-col"><div class="r-bar-track">'
            f'<div class="r-bar" data-h="{h}" style="height:{h}%"></div></div>'
            f'<div class="r-bar-val">{_esc(_fmt(v))}</div><div class="r-bar-lbl">{_esc(str(s.get("label","")))}</div></div>'
        )
    return f'<div class="r-bars">{"".join(cols)}</div>'


def _donut(series: list[dict]) -> str:
    import math
    vals = [float(s.get("value", 0) or 0) for s in series]
    total = sum(vals) or 1
    r = 46
    circ = 2 * math.pi * r
    segs, offset = [], 0.0
    for k, v in enumerate(vals):
        dash = circ * (v / total)
        segs.append(
            f'<circle cx="60" cy="60" r="{r}" stroke="{_sv(k)}" data-arc="{dash:.1f}" data-c="{circ:.0f}" '
            f'stroke-dasharray="{dash:.1f} {circ:.0f}" stroke-dashoffset="{-offset:.1f}"></circle>'
        )
        offset += dash
    top = series[0] if series else {}
    pct = round((vals[0] / total) * 100) if vals else 0
    legend = "".join(
        f'<div class="r-leg-row"><span class="r-leg-dot" style="background:{_sv(k)}"></span>'
        f'<span class="r-leg-lbl">{_esc(str(s.get("label","")))}</span>'
        f'<span class="r-leg-val">{_esc(_fmt(float(s.get("value",0) or 0)))}</span></div>'
        for k, s in enumerate(series)
    )
    svg = (
        '<svg class="r-donut" width="120" height="120" viewBox="0 0 120 120">'
        f'<circle cx="60" cy="60" r="{r}" fill="none" stroke="var(--rk-rule)" stroke-width="15"></circle>'
        f'<g transform="rotate(-90 60 60)" fill="none" stroke-width="15" stroke-linecap="butt">{"".join(segs)}</g>'
        f'<text x="60" y="56" text-anchor="middle" fill="var(--rk-text-hi)" font-family="JetBrains Mono" font-size="19" font-weight="700">{pct}%</text>'
        f'<text x="60" y="72" text-anchor="middle" fill="var(--rk-text-lo)" font-family="JetBrains Mono" font-size="8.5" letter-spacing="1">{_esc(str(top.get("label","")))}</text>'
        '</svg>'
    )
    return f'<div class="r-donut-wrap">{svg}<div class="r-donut-legend">{legend}</div></div>'


def _chart(raw: str) -> str:
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return ""
    series = data.get("series") or []
    if not series:
        return ""
    ctype = (data.get("type") or "bar").lower()
    title, unit = data.get("title") or "", data.get("unit") or ""
    head = ""
    if title:
        head = f'<div class="r-chart-title">{_esc(title)}</div>'
        if unit:
            head += f'<div class="r-chart-unit">{_esc(unit)}</div>'
    inner = _donut(series) if ctype == "donut" else _bars(series)
    return f'<div class="r-block" data-reveal><div class="r-chart">{head}{inner}</div></div>'


_TONE = {"insight": ("insight", "✦ 洞察"), "warn": ("warn", "⚠ 注意"), "success": ("success", "✦ 方向")}
def _callout(opts: str, content: str) -> str:
    m = re.search(r"tone\s*=\s*(\w+)", opts or "")
    cls, tag = _TONE.get(m.group(1) if m else "insight", _TONE["insight"])
    return (f'<div class="r-block" data-reveal><div class="r-callout {cls}">'
            f'<div class="r-callout-tag">{tag}</div><p>{_inline(content.strip())}</p></div></div>')


def _quote(content: str) -> str:
    text = content.strip()
    src = ""
    m = re.search(r"\n?\s*[—–-]\s*([^\n]+)$", text)
    if m:
        src = m.group(1).strip()
        text = text[:m.start()].strip()
    cite = f'<cite>— {_esc(src)}</cite>' if src else ""
    return f'<div class="r-block" data-reveal><blockquote class="r-quote">{_inline(text)}{cite}</blockquote></div>'


def _rank(content: str) -> str:
    """Numbered rank. A `label：value` line uses the label+value columns ONLY when
    the value is short (a metric); long descriptive items render full-width so the
    label never gets squished onto two chars. The design's compact 3-col layout
    assumes short values; real content is often a sentence."""
    lis = []
    i = 0
    for line in content.splitlines():
        line = line.strip()
        if not re.match(r"^(\d+\.|[-*])\s+", line):
            continue
        i += 1
        it = re.sub(r"^(\d+\.|[-*])\s+", "", line)
        body = ""
        sep = "：" if "：" in it else (":" if ":" in it else "")
        if sep:
            lbl, val = (x.strip() for x in it.split(sep, 1))
            # short value (a metric, no comma/long text) → two-column look
            if val and len(val) <= 14 and "，" not in val and "," not in val:
                body = (f'<span class="r-rank-lbl">{_inline(lbl)}</span>'
                        f'<span class="r-rank-val">{_esc(val)}</span>')
        if not body:  # long / descriptive → full-width label, wraps cleanly
            body = f'<span class="r-rank-lbl">{_inline(it)}</span>'
        lis.append(f'<li><span class="r-rank-i">{i}</span>{body}</li>')
    return f'<div class="r-block" data-reveal><ol class="r-rank">{"".join(lis)}</ol></div>' if lis else ""


def _compare(content: str) -> str:
    rows = [l for l in content.splitlines() if l.strip().startswith("|")]
    if len(rows) < 2:
        return ""
    cells = lambda r: [c.strip() for c in r.strip().strip("|").split("|")]
    header = cells(rows[0])
    data_rows = [cells(r) for r in rows[1:] if not set(r.replace("|", "").strip()) <= set("-: ")]
    th = "".join(f"<th>{_esc(c)}</th>" for c in header)
    trs = "".join("<tr>" + "".join(f"<td>{_inline(c)}</td>" for c in r) + "</tr>" for r in data_rows)
    return (f'<div class="r-block" data-reveal><table class="r-compare">'
            f'<thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table></div>')


def _timeline(content: str) -> str:
    rows = []
    for line in content.splitlines():
        line = line.strip()
        if not line:
            continue
        m = re.match(r"^(.+?)\s*[—–-]\s*(.+)$", line)
        date, ev = (m.group(1).strip(), m.group(2).strip()) if m else ("", line)
        rows.append(f'<div class="r-tl-item"><div class="r-tl-date">{_esc(date)}</div>'
                    f'<div class="r-tl-text">{_inline(ev)}</div></div>')
    return f'<div class="r-block" data-reveal><div class="r-timeline">{"".join(rows)}</div></div>' if rows else ""


def _actions(content: str) -> str:
    acts = [re.sub(r"^(\d+\.|[-*])\s+", "", l.strip())
            for l in content.splitlines() if re.match(r"^(\d+\.|[-*])\s+", l.strip())]
    if not acts:
        return ""
    rows = "".join(
        f'<div class="r-action"><span class="r-action-check"></span>'
        f'<span class="r-action-txt">{_inline(a)}</span></div>' for a in acts
    )
    return (f'<div class="r-block" data-reveal><div class="r-actions">'
            f'<div class="r-actions-head">✦ 接下来</div>{rows}</div></div>')


def _h2(text: str) -> str:
    # "／ label" or "/ label" prefix → mono eyebrow line above the heading
    m = re.match(r"^[／/]\s*(\S+)\s+(.*)$", text.strip())
    if m:
        return f'<h2 class="r-h2"><span class="r-h2-num">／ {_esc(m.group(1))}</span>{_inline(m.group(2))}</h2>'
    return f'<h2 class="r-h2">{_inline(text)}</h2>'


def _render_blocks(blocks: list) -> str:
    out = []
    for kind, payload in blocks:
        if kind == "chart":
            out.append(_chart(payload))
        elif kind == "p":
            out.append(f'<div class="r-block" data-reveal><p class="r-p">{_inline(payload)}</p></div>')
        elif kind == "quote":
            out.append(_quote(payload))
        elif kind in ("h2", "h3", "h4"):
            out.append(_h2(payload))
        elif kind == "h1":
            pass  # title lives in the masthead
        elif kind in ("ol", "ul"):
            tag = "ol" if kind == "ol" else "ul"
            lis = "".join(f"<li>{_inline(it)}</li>" for it in payload)
            out.append(f'<div class="r-block" data-reveal><{tag} class="r-list" style="margin:0 0 14px;padding-left:20px;color:var(--rk-text)">{lis}</{tag}></div>')
        elif kind.startswith("dir:"):
            name = kind[4:]
            opts, content = payload
            fn = {
                "kpi": lambda: _kpi(content), "callout": lambda: _callout(opts, content),
                "quote": lambda: _quote(content), "rank": lambda: _rank(content),
                "compare": lambda: _compare(content), "timeline": lambda: _timeline(content),
                "actions": lambda: _actions(content),
            }.get(name)
            out.append(fn() if fn else f'<div class="r-block" data-reveal><p class="r-p">{_inline(content)}</p></div>')
    return "".join(b for b in out if b)


def _extract_headline(body: str) -> tuple[str, str]:
    """Pull the masthead headline = the judgment line right after the `# title`.
    Returns (headline, remaining_body)."""
    lines = body.lstrip("\n").splitlines()
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i < len(lines) and re.match(r"^#\s+", lines[i].strip()):
        i += 1
    while i < len(lines) and not lines[i].strip():
        i += 1
    headline = ""
    if i < len(lines) and lines[i].strip() and not _is_block_start(lines[i].strip()):
        headline = lines[i].strip()
        i += 1
    return headline, "\n".join(lines[i:])


def _extract_hero(blocks: list) -> tuple[Optional[tuple], list]:
    """Promote the FIRST KPI item into the masthead hero (the design's big number),
    leaving the rest in the KPI wall. Only when the KPI block has ≥3 items, so the
    wall never ends up sparse."""
    hero = None
    out = []
    for kind, payload in blocks:
        if hero is None and kind == "dir:kpi":
            opts, content = payload
            kpi_lines = [l for l in content.splitlines() if l.strip() and ":" in l]
            if len(kpi_lines) >= 3:
                k, v = kpi_lines[0].split(":", 1)
                main, _sub = _split_kpi_value(v.strip())
                hero = (k.strip(), main)
                content = "\n".join(kpi_lines[1:])
            out.append((kind, (opts, content)))
            continue
        out.append((kind, payload))
    return hero, out


def _masthead(surface_class: str, genre: str, title: str, headline: str,
              date_str: str, hero: Optional[tuple] = None) -> str:
    zh, en = _GENRE_LABEL.get(genre, ("报告", "REPORT"))
    chips = (
        f'<span class="r-chip"><span class="r-chip-dot" style="background:var(--rk-accent)"></span>{en}</span>'
        + (f'<span class="r-chip">{_esc(date_str)}</span>' if date_str else "")
        + '<span class="r-chip">✦ REKA</span>'
    )
    hero_html = ""
    if hero:
        hl, hv = hero
        if surface_class == "surface-neon":
            hero_html = (f'<div class="neon-hero"><div class="neon-hero-n" data-count>{_esc(hv)}</div>'
                         f'<div class="neon-hero-lbl">{_esc(hl)}</div></div>')
        else:
            hero_html = (f'<div class="dash-hero"><span class="dash-hero-n" data-count>{_esc(hv)}</span>'
                         f'<div><div class="dash-hero-lbl">{_esc(hl)}</div></div></div>')
    inner = (
        f'<div class="r-meta-row" style="margin:0 0 4px;">{chips}</div>'
        f'<p class="r-eyebrow" style="margin-top:14px;">{_esc(zh)} / {_esc(en)}</p>'
        f'<h1 class="r-h1">{_esc(title)}</h1>'
        + (f'<p class="r-headline">{_inline(headline)}</p>' if headline else "")
        + hero_html
    )
    if surface_class == "surface-neon":
        return f'<section class="neon-head"><div class="neon-grid"></div>{inner}</section>'
    return f'<section class="dash-head">{inner}</section>'


def _sign(pet_gene: Optional[dict]) -> str:
    pet = '<div class="r-sign-pet" id="reka-sign-pet"></div>' if pet_gene else ""
    return (
        '<footer class="r-sign">'
        f'{pet}'
        '<div class="r-sign-meta"><div class="r-sign-mark"><span class="r-sign-spark">✦</span>Reka Insights</div>'
        '<div class="r-sign-tag">Reka 为你整理 · eureka.app</div></div></footer>'
    )


# arm script (in <head>, before paint) + 2.6s failsafe → static-complete (§6.6)
_ARM_JS = (
    "(function(){var m=window.matchMedia&&matchMedia('(prefers-reduced-motion: reduce)').matches;"
    "if(!m)document.documentElement.classList.add('rk-anim');"
    "setTimeout(function(){if(!window.__rkMotion)document.documentElement.classList.remove('rk-anim');},2600);})();"
)

# motion: reveal [data-reveal]→.is-in, count-up [data-count], bars scaleY, donut arc sweep.
# Static-complete: content is visible without JS (CSS only hides under html.rk-anim).
_MOTION_JS = r"""
(function(){
  function showAll(){try{document.documentElement.classList.remove('rk-anim');
    [].forEach.call(document.querySelectorAll('[data-reveal]'),function(b){b.classList.add('is-in');});}catch(_){}}
  try{
    window.__rkMotion=true;
    if(matchMedia('(prefers-reduced-motion: reduce)').matches){showAll();return;}
    function countUp(el){var raw=(el.textContent||'').trim();var m=raw.match(/-?[\d,]+(\.\d+)?/);if(!m)return;
      var target=parseFloat(m[0].replace(/,/g,''));if(!isFinite(target))return;
      var pre=raw.slice(0,m.index),suf=raw.slice(m.index+m[0].length);var dec=m[1]?m[1].length-1:0,grp=m[0].indexOf(',')>=0;
      function fmt(v){var s=grp?v.toLocaleString('en-US',{minimumFractionDigits:dec,maximumFractionDigits:dec}):v.toFixed(dec);return pre+s+suf;}
      var t0=null;function step(t){if(t0===null)t0=t;var p=Math.min(1,(t-t0)/1100);
        el.textContent=fmt(target*(0.5-Math.cos(Math.PI*p)/2));if(p<1)requestAnimationFrame(step);else el.textContent=raw;}
      requestAnimationFrame(step);}
    function animate(b){
      b.classList.add('is-in');
      [].forEach.call(b.querySelectorAll('.r-bar'),function(r,i){
        r.style.transition='transform .7s cubic-bezier(.2,.7,.3,1)';r.style.transitionDelay=(i*0.06)+'s';
        requestAnimationFrame(function(){requestAnimationFrame(function(){r.style.transform='scaleY(1)';});});});
      [].forEach.call(b.querySelectorAll('[data-count]'),countUp);
      [].forEach.call(b.querySelectorAll('circle[data-arc]'),function(a){
        var arc=parseFloat(a.getAttribute('data-arc')),c=parseFloat(a.getAttribute('data-c'));if(!isFinite(arc))return;
        a.style.transition='none';a.setAttribute('stroke-dasharray','0 '+c);
        requestAnimationFrame(function(){requestAnimationFrame(function(){
          a.style.transition='stroke-dasharray 1s cubic-bezier(.2,.7,.3,1)';a.setAttribute('stroke-dasharray',arc+' '+c);});});});
    }
    var els=[].slice.call(document.querySelectorAll('[data-reveal]'));
    if(!('IntersectionObserver' in window)){els.forEach(animate);
      [].forEach.call(document.querySelectorAll('[data-count]'),countUp);return;}
    var io=new IntersectionObserver(function(ents){ents.forEach(function(e){
      if(e.isIntersecting){animate(e.target);io.unobserve(e.target);}});},{threshold:0.12,rootMargin:'0px 0px -6% 0px'});
    els.forEach(function(b){io.observe(b);});
    [].forEach.call(document.querySelectorAll('[data-count]'),function(el){if(!el.closest('[data-reveal]'))countUp(el);});
  }catch(e){showAll();}
})();
""".strip()

_FONTS_LINK = (
    '<link rel="preconnect" href="https://fonts.googleapis.com">'
    '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
    '<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800'
    '&family=JetBrains+Mono:wght@400;500;600;700&family=Noto+Sans+SC:wght@400;500;700;900'
    '&family=Noto+Serif+SC:wght@400;700;900&display=swap" rel="stylesheet">'
)


def render_designed(
    content_md: str,
    *,
    seed_key: Optional[str] = None,
    palette: Optional[str] = None,
    surface: Optional[str] = None,
    seed: Optional[int] = None,
    pet_gene: Optional[dict] = None,
) -> dict:
    """Render a designed report (genre must be in _VARIANTS). Same return shape as
    report_render.render_report."""
    meta, body = _parse_frontmatter(content_md)
    genre = (meta.get("genre") or "data-report").strip()
    title = (meta.get("title") or "报告").strip()
    seed = seed if seed is not None else _seed(seed_key or f"{title}|{genre}")
    variants = _VARIANTS[genre]
    pal_class, surface_class = variants[seed % len(variants)]
    if palette:  # explicit override (换装, §6.7)
        pal_class = palette if palette.startswith("pal-") else f"pal-{palette}"
    if surface:
        surface_class = surface if surface.startswith("surface-") else f"surface-{surface}"

    headline, rest = _extract_headline(body)
    hero, blocks = _extract_hero(_split_blocks(rest))
    inner = _render_blocks(blocks)

    dates = re.findall(r"\d{4}-\d{2}-\d{2}", meta.get("time_range", "") or "")
    if len(dates) >= 2:
        date_str = f'{dates[0].replace("-", ".")} – {dates[1][5:].replace("-", ".")}'
    elif len(dates) == 1:
        date_str = dates[0].replace("-", ".")
    else:
        date_str = ""

    masthead = _masthead(surface_class, genre, title, headline, date_str, hero)
    wrap = _BODY_WRAP.get(surface_class, "dash-grid")
    css = BASE_CSS + "\n" + SURFACE_CSS.get(surface_class, "")
    gene_js = ""
    if pet_gene:
        gene_js = (
            f"<script>window.__REKA_GENE__={json.dumps(pet_gene, ensure_ascii=False)};</script>"
            f"<script>{_REKA_SIGN_JS}</script>"
        )

    html_doc = (
        '<!doctype html><html lang="zh"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
        f'<title>{_esc(title)} · Reka Insights</title>'
        f'{_FONTS_LINK}<script>{_ARM_JS}</script><style>{css}</style></head>'
        f'<body><main class="report {pal_class} {surface_class}">'
        f'{masthead}<div class="{wrap}">{inner}</div>{_sign(pet_gene)}</main>'
        f'<script>{_MOTION_JS}</script>{gene_js}</body></html>'
    )
    return {
        "html": html_doc, "title": title, "genre": genre,
        "surface": surface_class, "palette": pal_class, "seed": seed,
    }
