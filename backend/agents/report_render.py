"""
Deterministic report renderer (§6.5 ③) — annotated Markdown → single-file HTML.

Per §6.5 the render layer is *deterministic*: layout/palette by catalog + seed,
NOT improvised by an LLM (anti-slop). The content skill produces annotated md
(substance); this module is the only thing that turns it into HTML
(presentation). Re-rendering = same md + new seed → new look, zero re-query.

Output is a self-contained HTML document: inline CSS, hand-built inline SVG
charts, no external requests. A small *dependency-free* progressive-enhancement
script (no GSAP) staggers a fade-in of `.r-block` and grows the bars; blocks are
fully visible by default, so if the script never runs the HTML is still complete
and static. Respects `prefers-reduced-motion`.

Public API:
    render_report(content_md, seed_key=None) -> dict
        { "html", "title", "genre", "surface", "palette", "seed" }
"""
from __future__ import annotations

import html as _html
import json
import re
import zlib
from typing import Optional

# ── Catalog: palettes (design tokens) ────────────────────────────────────────
# Each palette = a coherent token set. Reuses the §5 design-system vocabulary
# (dark-first, brand purple, semantic accents). Selected by seed for variety.
_PALETTES: dict[str, dict] = {
    "ink": {  # 杂志墨 — calm editorial dark
        "bg": "#0b0e16", "bg2": "#11151f", "card": "rgba(255,255,255,.045)",
        "line": "rgba(255,255,255,.09)", "hi": "#e9eef7", "mid": "#9aa6b8",
        "lo": "#5d6675", "brand": "#b79dff", "c1": "#6f9eff", "c2": "#5fd6a0",
        "c3": "#f5c879", "c4": "#ff8a8a", "c5": "#7ad7e6",
    },
    "minimal": {  # 极简数据 — near-mono, restrained
        "bg": "#0c0d10", "bg2": "#141519", "card": "rgba(255,255,255,.05)",
        "line": "rgba(255,255,255,.10)", "hi": "#f2f3f5", "mid": "#a6abb5",
        "lo": "#666b75", "brand": "#cfd3da", "c1": "#9aa3b2", "c2": "#7fb8a0",
        "c3": "#d8c08a", "c4": "#d89292", "c5": "#8fb6c2",
    },
    "dashboard": {  # 仪表盘暗 — cool, data-forward
        "bg": "#0a0f1a", "bg2": "#0f1626", "card": "rgba(120,160,255,.06)",
        "line": "rgba(120,160,255,.14)", "hi": "#eaf1ff", "mid": "#93a4c4",
        "lo": "#5a6a88", "brand": "#6f9eff", "c1": "#6f9eff", "c2": "#5fd6a0",
        "c3": "#f5c879", "c4": "#ff8a8a", "c5": "#a78bfa",
    },
    "neon": {  # 暗黑霓虹 — punchy, high-contrast accents
        "bg": "#08080d", "bg2": "#10101a", "card": "rgba(183,157,255,.07)",
        "line": "rgba(183,157,255,.16)", "hi": "#f4f1ff", "mid": "#a99fce",
        "lo": "#6b6388", "brand": "#c08bff", "c1": "#7c8bff", "c2": "#54e6b8",
        "c3": "#ffd166", "c4": "#ff7a9c", "c5": "#5ad1ff",
    },
    "warm": {  # 暖夜 — warm dark, amber/terracotta forward
        "bg": "#100c0a", "bg2": "#181210", "card": "rgba(255,200,150,.06)",
        "line": "rgba(255,200,150,.13)", "hi": "#f6efe9", "mid": "#c2ab99",
        "lo": "#7d6b5d", "brand": "#f0a868", "c1": "#f0a868", "c2": "#7fcf9f",
        "c3": "#ffd98a", "c4": "#ef8a7a", "c5": "#d9a8e0",
    },
    "forest": {  # 林夜 — deep green-teal, calm
        "bg": "#0a1310", "bg2": "#0f1c17", "card": "rgba(120,220,180,.06)",
        "line": "rgba(120,220,180,.13)", "hi": "#e8f3ee", "mid": "#9bb8ad",
        "lo": "#5d7269", "brand": "#5fd6a0", "c1": "#5fd6a0", "c2": "#6fc7e6",
        "c3": "#e6cf86", "c4": "#ef9a8a", "c5": "#a9b6f0",
    },
}

# surface (版式族) per genre — affects width, heading scale, density.
_SURFACES: dict[str, dict] = {
    "dashboard":     {"maxw": 760, "h1": 26, "lead": 14, "gap": 16},
    "editorial":     {"maxw": 680, "h1": 30, "lead": 15, "gap": 20},
    "deck-doc":      {"maxw": 720, "h1": 27, "lead": 14, "gap": 18},
    "magazine-lite": {"maxw": 700, "h1": 25, "lead": 14, "gap": 16},
}

_GENRE_SURFACE = {
    "data-report":    "dashboard",
    "idea-synthesis": "editorial",
    "proposal":       "deck-doc",
    "digest":         "magazine-lite",
}

_PALETTE_KEYS = list(_PALETTES.keys())


def _seed(key: str) -> int:
    return zlib.crc32(key.encode("utf-8")) & 0xFFFFFFFF


def _esc(s: str) -> str:
    return _html.escape(s, quote=True)


# ── Inline markdown (bold / code / italic) ───────────────────────────────────
def _inline(text: str) -> str:
    t = _esc(text)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"`(.+?)`", r"<code>\1</code>", t)
    t = re.sub(r"(?<![\*\w])\*(?!\s)(.+?)(?<!\s)\*(?![\*\w])", r"<em>\1</em>", t)
    return t


# ── Frontmatter ──────────────────────────────────────────────────────────────
def _parse_frontmatter(md: str) -> tuple[dict, str]:
    m = re.match(r"^\s*---\s*\n(.*?)\n---\s*\n?(.*)$", md, re.DOTALL)
    if not m:
        return {}, md
    raw, body = m.group(1), m.group(2)
    meta: dict = {}
    for line in raw.splitlines():
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        meta[k.strip()] = v.strip()
    return meta, body


# ── Block parsing ────────────────────────────────────────────────────────────
# Blocks: directive (:::name ... :::), fenced chart (```chart ... ```),
# heading, list, blockquote, paragraph.
def _split_blocks(body: str) -> list[tuple[str, object]]:
    # Defensive: the flash content skill sometimes wraps a directive fence in
    # backticks (`:::rank` / `:::`) because the prompt references them as inline
    # code. A backticked fence fails the `:::name` match below → the open line
    # leaks as literal monospace text and the block body renders as a bare list
    # (e.g. :::rank → a plain <ol>). Normalize any line that is *only* a fence,
    # optionally backtick-wrapped, back to the bare fence so it parses. Targeted:
    # only fires when the line, after the backticks, starts with ":::".
    body = re.sub(r"(?m)^[ \t]*`+[ \t]*(:::[^`\n]*?)[ \t]*`+[ \t]*$", r"\1", body)
    lines = body.splitlines()
    blocks: list[tuple[str, object]] = []
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()
        if not stripped:
            i += 1
            continue
        # fenced chart
        if re.match(r"^```chart\s*$", stripped):
            j = i + 1
            buf = []
            while j < n and not lines[j].strip().startswith("```"):
                buf.append(lines[j]); j += 1
            blocks.append(("chart", "\n".join(buf)))
            i = j + 1
            continue
        # other fenced code → skip the fence, keep as paragraph-ish (rare)
        if stripped.startswith("```"):
            j = i + 1
            buf = []
            while j < n and not lines[j].strip().startswith("```"):
                buf.append(lines[j]); j += 1
            blocks.append(("code", "\n".join(buf)))
            i = j + 1
            continue
        # directive  :::name{opts}  — also accept inline trailing text on the
        # fence line (e.g. `:::quote — 出处`), which the skills emit. Without
        # capturing it, the line is a `:::`-block-start that no handler consumes
        # → infinite loop. (.* swallows the rest of the line.)
        dm = re.match(r"^:::([a-zA-Z]+)(\{[^}]*\})?\s*(.*)$", stripped)
        if dm:
            name = dm.group(1).lower()
            opts = dm.group(2) or ""
            trailing = (dm.group(3) or "").strip()
            j = i + 1
            buf = []
            while j < n and lines[j].strip() != ":::":
                buf.append(lines[j]); j += 1
            content = "\n".join(buf)
            if trailing:  # e.g. "— 出处" → fold into content for the renderer
                content = (content + "\n" + trailing).strip()
            blocks.append((f"dir:{name}", (opts, content)))
            i = j + 1
            continue
        # heading
        hm = re.match(r"^(#{1,4})\s+(.*)$", stripped)
        if hm:
            blocks.append((f"h{len(hm.group(1))}", hm.group(2)))
            i += 1
            continue
        # blockquote
        if stripped.startswith(">"):
            buf = []
            while i < n and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip()[1:].strip()); i += 1
            blocks.append(("quote", " ".join(buf)))
            continue
        # list (ordered or unordered)
        if re.match(r"^(\d+\.|[-*])\s+", stripped):
            items = []
            ordered = bool(re.match(r"^\d+\.", stripped))
            while i < n and re.match(r"^(\d+\.|[-*])\s+", lines[i].strip()):
                items.append(re.sub(r"^(\d+\.|[-*])\s+", "", lines[i].strip()))
                i += 1
            blocks.append(("ol" if ordered else "ul", items))
            continue
        # paragraph (gather until blank or next block start)
        buf = []
        while i < n and lines[i].strip() and not _is_block_start(lines[i].strip()):
            buf.append(lines[i].strip()); i += 1
        if buf:
            blocks.append(("p", " ".join(buf)))
        else:
            # Safety net: a block-start line that no handler above consumed
            # (e.g. a malformed directive). Emit it as plain text and ALWAYS
            # advance — never leave `i` unchanged, or this loops forever.
            blocks.append(("p", stripped))
            i += 1
    return blocks


def _is_block_start(s: str) -> bool:
    return bool(
        re.match(r"^(#{1,4})\s+", s) or s.startswith(":::") or s.startswith("```")
        or s.startswith(">") or re.match(r"^(\d+\.|[-*])\s+", s)
    )


# ── SVG charts ───────────────────────────────────────────────────────────────
# Named colors a content skill may set per series (`"color":"green"`), mapped to
# palette tokens so they stay on-palette.
_NAMED_TO_TOKEN = {
    "green": "c2", "success": "c2", "good": "c2",
    "red": "c4", "danger": "c4", "bad": "c4",
    "amber": "c3", "warn": "c3", "yellow": "c3", "gold": "c3",
    "blue": "c1", "purple": "brand", "violet": "brand", "cyan": "c5", "teal": "c5",
}
# Sentiment keywords for auto-coloring when no explicit color is given.
_POS_WORDS = ("好评", "好", "优", "正", "盈", "达成", "完成", "涨", "升", "增", "赞", "满意")
_NEG_WORDS = ("差评", "差", "坏", "负", "亏", "未完成", "未达", "降", "跌", "超支", "逾期", "差劲")
_DEFAULT_ORDER = ("c1", "c2", "c3", "c4", "c5", "brand")


def _series_color(s: dict, pal: dict, idx: int) -> str:
    """Per-series fill: explicit named color → sentiment of the label → indexed."""
    named = str(s.get("color", "")).strip().lower()
    if named in _NAMED_TO_TOKEN:
        return pal[_NAMED_TO_TOKEN[named]]
    label = str(s.get("label", ""))
    if any(w in label for w in _POS_WORDS):
        return pal["c2"]  # green
    if any(w in label for w in _NEG_WORDS):
        return pal["c4"]  # red
    return pal[_DEFAULT_ORDER[idx % len(_DEFAULT_ORDER)]]


def _svg_bar(series: list[dict], pal: dict, unit: str) -> str:
    if not series:
        return ""
    W, H, pad_b, pad_t = 320, 170, 26, 14
    vals = [float(s.get("value", 0) or 0) for s in series]
    mx = max(vals) or 1
    n = len(series)
    gap = 10
    bw = max(8, (W - gap * (n + 1)) / n)
    colors = [_series_color(s, pal, k) for k, s in enumerate(series)]
    parts = [f'<svg viewBox="0 0 {W} {H}" width="100%" style="display:block" class="r-chart">']
    base = H - pad_b
    parts.append(f'<line x1="0" y1="{base}" x2="{W}" y2="{base}" stroke="{pal["line"]}"/>')
    for k, s in enumerate(series):
        v = float(s.get("value", 0) or 0)
        h = (v / mx) * (H - pad_b - pad_t)
        x = gap + k * (bw + gap)
        y = base - h
        c = colors[k % len(colors)]
        lbl = _esc(str(s.get("label", "")))[:6]
        parts.append(f'<rect class="r-bar" x="{x:.1f}" y="{y:.1f}" width="{bw:.1f}" height="{h:.1f}" rx="5" fill="{c}"/>')
        parts.append(f'<text x="{x+bw/2:.1f}" y="{base+16:.1f}" fill="{pal["mid"]}" font-size="10" text-anchor="middle">{lbl}</text>')
        parts.append(f'<text x="{x+bw/2:.1f}" y="{y-4:.1f}" fill="{pal["hi"]}" font-size="10" text-anchor="middle">{_fmt(v)}</text>')
    parts.append("</svg>")
    return "".join(parts)


def _svg_line(series: list[dict], pal: dict, area: bool) -> str:
    if not series:
        return ""
    W, H, pad_b, pad_t, pad_x = 320, 170, 26, 14, 10
    vals = [float(s.get("value", 0) or 0) for s in series]
    mx = max(vals) or 1
    mn = min(vals + [0])
    n = len(series)
    base = H - pad_b
    span = (W - 2 * pad_x)
    step = span / max(1, n - 1)
    rng = (mx - mn) or 1
    pts = []
    for k, v in enumerate(vals):
        x = pad_x + k * step
        y = base - ((v - mn) / rng) * (H - pad_b - pad_t)
        pts.append((x, y))
    poly = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    parts = [f'<svg viewBox="0 0 {W} {H}" width="100%" style="display:block" class="r-chart">']
    parts.append(f'<line x1="0" y1="{base}" x2="{W}" y2="{base}" stroke="{pal["line"]}"/>')
    if area:
        ap = f"{pad_x:.1f},{base:.1f} " + poly + f" {pad_x+(n-1)*step:.1f},{base:.1f}"
        parts.append(f'<polygon points="{ap}" fill="{pal["brand"]}" opacity="0.14"/>')
    parts.append(f'<polyline class="r-line" points="{poly}" fill="none" stroke="{pal["brand"]}" stroke-width="2"/>')
    for k, (x, y) in enumerate(pts):
        parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="2.5" fill="{pal["brand"]}"/>')
        lbl = _esc(str(series[k].get("label", "")))[:5]
        parts.append(f'<text x="{x:.1f}" y="{base+16:.1f}" fill="{pal["mid"]}" font-size="9" text-anchor="middle">{lbl}</text>')
    parts.append("</svg>")
    return "".join(parts)


def _svg_donut(series: list[dict], pal: dict) -> str:
    vals = [float(s.get("value", 0) or 0) for s in series]
    total = sum(vals) or 1
    cx, cy, r, sw = 90, 90, 64, 26
    import math
    colors = [_series_color(s, pal, k) for k, s in enumerate(series)]
    parts = ['<div class="r-donut-wrap"><svg viewBox="0 0 180 180" width="180" height="180" class="r-chart">']
    ang = -math.pi / 2
    circ = 2 * math.pi * r
    for k, v in enumerate(vals):
        frac = v / total
        dash = circ * frac
        off = circ * (ang + math.pi / 2) / (2 * math.pi)
        c = colors[k % len(colors)]
        parts.append(
            f'<circle class="r-arc" cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{c}" '
            f'stroke-width="{sw}" stroke-dasharray="{dash:.2f} {circ - dash:.2f}" '
            f'stroke-dashoffset="{-off:.2f}" transform="rotate(-90 {cx} {cy})"/>'
        )
        ang += 2 * math.pi * frac
    parts.append(f'<text x="{cx}" y="{cy+5}" fill="{pal["hi"]}" font-size="15" text-anchor="middle">{_fmt(total)}</text>')
    parts.append("</svg>")
    # legend
    leg = ['<div class="r-legend">']
    for k, s in enumerate(series):
        c = colors[k % len(colors)]
        leg.append(
            f'<div class="r-leg"><span class="r-dot" style="background:{c}"></span>'
            f'{_esc(str(s.get("label","")))} · {_fmt(float(s.get("value",0) or 0))}</div>'
        )
    leg.append("</div>")
    parts.append("".join(leg) + "</div>")
    return "".join(parts)


def _fmt(v: float) -> str:
    if v == int(v):
        return f"{int(v):,}"
    return f"{v:,.1f}"


def _render_chart(raw: str, pal: dict) -> str:
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return ""
    series = data.get("series") or []
    ctype = (data.get("type") or "bar").lower()
    title = data.get("title") or ""
    unit = data.get("unit") or ""
    if ctype == "donut":
        chart = _svg_donut(series, pal)
    elif ctype in ("line", "area"):
        chart = _svg_line(series, pal, area=(ctype == "area"))
    else:
        chart = _svg_bar(series, pal, unit)
    head = f'<div class="r-chart-title">{_esc(title)}{(" · " + _esc(unit)) if unit else ""}</div>' if title else ""
    return f'<div class="r-card r-block">{head}{chart}</div>'


# ── Directive renderers ──────────────────────────────────────────────────────
def _split_kpi_value(v: str) -> tuple[str, str]:
    """Pull a trailing parenthetical qualifier out of a KPI value so the big
    number stays clean and the qualifier renders as a small sub-line.
    `¥999（服装）` → ('¥999', '服装');  `52%` → ('52%', '')."""
    m = re.match(r"^\s*(.+?)\s*[（(]\s*(.+?)\s*[)）]\s*$", v)
    if m and m.group(1).strip():
        return m.group(1).strip(), m.group(2).strip()
    return v.strip(), ""


def _kpi_font_px(max_len: int, n: int) -> int:
    """Pick ONE font size (px) so the LONGEST KPI value fits on a single line in an
    n-up row — numbers must never wrap (`¥1,445`→`¥1,44 / 5` is ugly). Uniform size
    across the row keeps the cards looking consistent. Conservative estimate of the
    usable text width per card; tabular glyph ≈ 0.62em."""
    usable = {1: 270, 2: 130, 3: 84, 4: 58, 5: 46}.get(n, max(40, 260 // max(n, 1)))
    px = int(usable / (max(max_len, 1) * 0.62))
    return max(13, min(24, px))


def _render_kpi(content: str) -> str:
    items = []
    for line in content.splitlines():
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        items.append((k.strip(), v.strip()))
    if not items:
        return ""
    splits = [_split_kpi_value(v) for _, v in items]
    # Size the whole row to its longest main value so nothing wraps + all uniform.
    max_len = max((len(main) for main, _ in splits), default=1)
    fs = _kpi_font_px(max_len, len(items))
    cells = []
    for (k, _v), (main, sub) in zip(items, splits):
        sub_html = f'<div class="r-kpi-sub">{_esc(sub)}</div>' if sub else ""
        cells.append(
            f'<div class="r-kpi"><div class="r-kpi-n" style="font-size:{fs}px">{_esc(main)}</div>'
            f'{sub_html}<div class="r-kpi-k">{_esc(k)}</div></div>'
        )
    return f'<div class="r-kpis r-block">{"".join(cells)}</div>'


def _render_timeline(content: str) -> str:
    rows = []
    for line in content.splitlines():
        line = line.strip()
        if not line:
            continue
        if "—" in line:
            d, _, e = line.partition("—")
        elif "-" in line:
            d, _, e = line.partition("-")
        else:
            d, e = "", line
        rows.append(
            f'<div class="r-tl-row"><span class="r-tl-date">{_esc(d.strip())}</span>'
            f'<span class="r-tl-ev">{_inline(e.strip())}</span></div>'
        )
    return f'<div class="r-card r-block r-timeline">{"".join(rows)}</div>'


def _render_callout(opts: str, content: str) -> str:
    tone = "insight"
    m = re.search(r"tone\s*=\s*([a-z]+)", opts or "")
    if m:
        tone = m.group(1)
    body = _render_inner(content)
    return f'<div class="r-callout r-tone-{_esc(tone)} r-block">{body}</div>'


def _render_quote(opts: str, content: str) -> str:
    # ":::quote — 出处" carries the source in the opts line tail; here opts is {…}
    # form only, so source (if any) is appended in content. Keep simple.
    src = ""
    m = re.search(r"—\s*(.+)$", content.strip(), re.MULTILINE)
    text = content
    if m:
        src = m.group(1).strip()
        text = content.replace(m.group(0), "").strip()
    cite = f'<div class="r-quote-src">— {_esc(src)}</div>' if src else ""
    return f'<blockquote class="r-quote r-block">{_inline(text.strip())}{cite}</blockquote>'


def _render_rank(content: str) -> str:
    items = [re.sub(r"^\d+\.\s*", "", l.strip()) for l in content.splitlines() if l.strip()]
    lis = "".join(f"<li>{_inline(it)}</li>" for it in items)
    return f'<ol class="r-rank r-block">{lis}</ol>'


def _render_compare(content: str) -> str:
    # content is a markdown table
    rows = [l.strip() for l in content.splitlines() if l.strip()]
    rows = [r for r in rows if not re.match(r"^\|?[\s:\-|]+\|?$", r)]  # drop separator row
    if not rows:
        return ""
    def cells(r):
        return [c.strip() for c in r.strip().strip("|").split("|")]
    head = cells(rows[0])
    thead = "".join(f"<th>{_inline(c)}</th>" for c in head)
    body = "".join(
        "<tr>" + "".join(f"<td>{_inline(c)}</td>" for c in cells(r)) + "</tr>"
        for r in rows[1:]
    )
    return f'<div class="r-card r-block"><table class="r-table"><thead><tr>{thead}</tr></thead><tbody>{body}</tbody></table></div>'


def _render_inner(content: str) -> str:
    """Render the inside of a callout/etc — paragraphs + lists only."""
    out = []
    for kind, payload in _split_blocks(content):
        if kind == "p":
            out.append(f"<p>{_inline(payload)}</p>")
        elif kind == "ul":
            out.append("<ul>" + "".join(f"<li>{_inline(x)}</li>" for x in payload) + "</ul>")
        elif kind == "ol":
            out.append("<ol>" + "".join(f"<li>{_inline(x)}</li>" for x in payload) + "</ol>")
        else:
            out.append(f"<p>{_inline(str(payload))}</p>")
    return "".join(out)


# ── Assembly ─────────────────────────────────────────────────────────────────
def _render_body(blocks: list, pal: dict) -> str:
    out: list[str] = []
    first_h1_done = False
    for kind, payload in blocks:
        if kind == "h1":
            cls = "r-h1" if not first_h1_done else "r-h2"
            out.append(f'<h1 class="{cls} r-block">{_inline(payload)}</h1>')
            first_h1_done = True
        elif kind == "h2":
            out.append(f'<h2 class="r-h2 r-block">{_inline(payload)}</h2>')
        elif kind in ("h3", "h4"):
            out.append(f'<h3 class="r-h3 r-block">{_inline(payload)}</h3>')
        elif kind == "p":
            # The first paragraph right after the title reads as the headline.
            cls = "r-lead" if (len(out) == 1 and first_h1_done) else "r-p"
            out.append(f'<p class="{cls} r-block">{_inline(payload)}</p>')
        elif kind == "ul":
            out.append('<ul class="r-ul r-block">' + "".join(f"<li>{_inline(x)}</li>" for x in payload) + "</ul>")
        elif kind == "ol":
            out.append('<ol class="r-ol r-block">' + "".join(f"<li>{_inline(x)}</li>" for x in payload) + "</ol>")
        elif kind == "quote":
            out.append(f'<blockquote class="r-quote r-block">{_inline(payload)}</blockquote>')
        elif kind == "chart":
            out.append(_render_chart(payload, pal))
        elif kind == "code":
            out.append(f'<pre class="r-block"><code>{_esc(payload)}</code></pre>')
        elif kind.startswith("dir:"):
            name = kind[4:]
            opts, content = payload
            if name == "kpi":
                out.append(_render_kpi(content))
            elif name == "timeline":
                out.append(_render_timeline(content))
            elif name == "callout":
                out.append(_render_callout(opts, content))
            elif name == "quote":
                out.append(_render_quote(opts, content))
            elif name == "rank":
                out.append(_render_rank(content))
            elif name == "compare":
                out.append(_render_compare(content))
            else:
                # unknown directive → degrade to paragraphs (§6.4)
                out.append(_render_inner(content))
    return "\n".join(out)


def _css(pal: dict, surf: dict) -> str:
    p = pal
    return f"""
:root{{
  --bg:{p['bg']};--bg2:{p['bg2']};--card:{p['card']};--line:{p['line']};
  --hi:{p['hi']};--mid:{p['mid']};--lo:{p['lo']};--brand:{p['brand']};
  --c1:{p['c1']};--c2:{p['c2']};--c3:{p['c3']};--c4:{p['c4']};--c5:{p['c5']};
}}
*{{box-sizing:border-box}}
html,body{{margin:0;padding:0;background:var(--bg);}}
body{{color:var(--hi);font:{surf['lead']}px/1.6 -apple-system,"PingFang SC","Noto Sans SC",system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;}}
.r-wrap{{max-width:{surf['maxw']}px;margin:0 auto;padding:26px 18px 64px;}}
.r-eyebrow{{font-size:11px;letter-spacing:.20em;color:var(--brand);font-weight:700;
  margin:0 0 12px;text-transform:uppercase;}}
.r-h1{{font-size:{surf['h1']}px;font-weight:800;letter-spacing:-.02em;margin:0 0 6px;line-height:1.2;}}
.r-lead{{color:var(--mid);font-size:{surf['lead']+1}px;margin:0 0 22px;}}
.r-h2{{font-size:16px;font-weight:700;margin:26px 0 12px;letter-spacing:-.01em;}}
.r-h3{{font-size:14px;font-weight:700;color:var(--mid);margin:18px 0 8px;}}
.r-p{{margin:0 0 12px;color:var(--hi);}}
.r-ul,.r-ol{{margin:0 0 14px;padding-left:20px;color:var(--mid);}}
.r-ul li,.r-ol li{{margin:6px 0;}}
.r-card{{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px;margin:0 0 16px;}}
.r-kpis{{display:flex;gap:10px;margin:0 0 20px;flex-wrap:wrap;}}
.r-kpi{{flex:1 1 0;min-width:80px;background:var(--card);border:1px solid var(--line);
  border-radius:14px;padding:14px 10px;text-align:center;}}
.r-kpi-n{{font-size:22px;font-weight:800;color:var(--brand);font-variant-numeric:tabular-nums;
  line-height:1.12;white-space:nowrap;}}
.r-kpi-sub{{font-size:11px;font-weight:700;color:var(--mid);margin-top:3px;line-height:1.15;
  overflow-wrap:anywhere;}}
.r-kpi-k{{font-size:11px;color:var(--lo);margin-top:5px;letter-spacing:.06em;}}
.r-chart-title{{font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--lo);margin:0 0 10px;font-weight:600;}}
.r-donut-wrap{{display:flex;gap:16px;align-items:center;flex-wrap:wrap;}}
.r-legend{{display:flex;flex-direction:column;gap:6px;font-size:12px;color:var(--mid);}}
.r-leg{{display:flex;align-items:center;gap:7px;}}
.r-dot{{width:9px;height:9px;border-radius:3px;display:inline-block;}}
.r-timeline .r-tl-row{{display:flex;gap:12px;padding:7px 0;border-top:1px solid var(--line);}}
.r-timeline .r-tl-row:first-child{{border-top:none;}}
.r-tl-date{{color:var(--brand);font-variant-numeric:tabular-nums;font-size:12px;min-width:54px;}}
.r-tl-ev{{color:var(--hi);font-size:13px;}}
.r-callout{{border-radius:14px;padding:13px 15px;margin:0 0 16px;border:1px solid var(--line);
  background:var(--card);border-left:3px solid var(--brand);}}
.r-callout p{{margin:0;color:var(--hi);}}
.r-tone-insight{{border-left-color:var(--c1);}}
.r-tone-warn{{border-left-color:var(--c3);}}
.r-tone-success{{border-left-color:var(--c2);}}
.r-quote{{margin:0 0 16px;padding:6px 0 6px 16px;border-left:3px solid var(--line);
  color:var(--mid);font-style:italic;}}
.r-quote-src{{margin-top:6px;font-style:normal;font-size:11px;color:var(--lo);}}
.r-rank{{counter-reset:r;list-style:none;padding:0;margin:0 0 16px;}}
.r-rank li{{position:relative;padding:9px 0 9px 34px;border-top:1px solid var(--line);color:var(--hi);}}
.r-rank li:first-child{{border-top:none;}}
.r-rank li::before{{counter-increment:r;content:counter(r);position:absolute;left:0;top:9px;
  width:22px;height:22px;border-radius:7px;background:var(--card);border:1px solid var(--line);
  color:var(--brand);font-weight:700;font-size:12px;display:flex;align-items:center;justify-content:center;}}
.r-table{{width:100%;border-collapse:collapse;font-size:13px;}}
.r-table th{{text-align:left;color:var(--lo);font-size:11px;letter-spacing:.06em;
  padding:6px 8px;border-bottom:1px solid var(--line);font-weight:600;}}
.r-table td{{padding:8px;border-bottom:1px solid var(--line);color:var(--hi);}}
.r-table tr:last-child td{{border-bottom:none;}}
code{{background:var(--card);padding:1px 5px;border-radius:5px;font-size:.92em;}}
strong{{color:var(--hi);font-weight:700;}}
/* Reveal: transition only — the hidden start state is applied by JS, so no-JS
   keeps everything visible (static-complete, §6.6). */
.r-block{{transition:opacity .5s ease, transform .5s ease;}}
@media (prefers-reduced-motion:reduce){{.r-block{{opacity:1!important;transform:none!important;transition:none!important;}}}}
""".strip()


# Progressive-enhancement animation (§6.12 batch 2). Each `.r-block` reveals when
# it **scrolls into view** (IntersectionObserver — robust, no ScrollTrigger plugin
# needed), then its chart draws on: bars grow from the baseline, the donut ring
# and line **draw on** (stroke-dash sweep), and KPI numbers **count up**. Uses
# **GSAP** when `window.gsap` is present (the viewer injects bundled gsap.min.js,
# §6.6) for richer easing; falls back to a dependency-free vanilla reveal so an
# exported/shared .html still animates. HARD RULE (§6.6 渐进增强): the report is
# fully static-complete without JS — blocks default visible in CSS; this script
# only ADDS motion, is wrapped in try/catch, respects prefers-reduced-motion, and
# restores full visibility on any error.
_ENHANCE_JS = """
(function(){
  function showAll(){ try{ [].forEach.call(document.querySelectorAll('.r-block'),
    function(b){ b.style.opacity=1; b.style.transform='none'; }); }catch(_){} }
  try{
    if (matchMedia('(prefers-reduced-motion: reduce)').matches){ showAll(); return; }
    var blocks = [].slice.call(document.querySelectorAll('.r-block'));
    if (!blocks.length) return;
    if (!('IntersectionObserver' in window)){ showAll(); return; }
    var G = window.gsap || null;
    var ST = window.ScrollTrigger || null;

    // JS is on → start hidden, reveal on scroll-in.
    blocks.forEach(function(b){ b.style.opacity = '0'; });

    // §6.6.2 premium image motion — scroll PARALLAX: each AI image drifts vertically
    // as you scroll past it (depth). Needs ScrollTrigger; ken-burns (continuous zoom)
    // is added per-image on reveal in animate(). Both no-op gracefully without GSAP.
    if (G && ST){
      [].forEach.call(document.querySelectorAll('.r-ai-img'), function(fig){
        try{ G.fromTo(fig, {y:-14}, {y:14, ease:'none', scrollTrigger:{
          trigger:fig, start:'top bottom', end:'bottom top', scrub:0.6}}); }catch(_){}
      });
    }

    function countUp(el){
      var raw = (el.textContent||'').trim();
      var m = raw.match(/-?[\\d,]+(\\.\\d+)?/);
      if (!m) return;
      var target = parseFloat(m[0].replace(/,/g,''));
      if (!isFinite(target)) return;
      var pre = raw.slice(0, m.index), suf = raw.slice(m.index + m[0].length);
      var dec = m[1] ? (m[1].length - 1) : 0, grp = m[0].indexOf(',') >= 0;
      function fmt(v){
        var s = grp ? v.toLocaleString('en-US',{minimumFractionDigits:dec,maximumFractionDigits:dec})
                    : v.toFixed(dec);
        return pre + s + suf;
      }
      var t0 = null, dur = 1100;
      function step(t){
        if (t0===null) t0 = t;
        var p = Math.min(1, (t - t0) / dur);
        el.textContent = fmt(target * (0.5 - Math.cos(Math.PI * p) / 2));   // ease
        if (p < 1) requestAnimationFrame(step); else el.textContent = raw;  // exact original at end
      }
      requestAnimationFrame(step);
    }

    function animate(b){
      // ── block reveal ──
      if (G){ b.style.transition = 'none'; G.fromTo(b, {opacity:0, y:16}, {opacity:1, y:0, duration:.55, ease:'power3.out'}); }
      else { b.style.transition='opacity .5s ease, transform .5s ease'; b.style.transform='translateY(14px)';
             requestAnimationFrame(function(){ b.style.opacity='1'; b.style.transform='none'; }); }

      // ── bars grow from the baseline ──
      var bars = b.querySelectorAll('.r-bar');
      if (bars.length){
        if (G){ G.from(bars, {scaleY:0, transformOrigin:'bottom', duration:.6, stagger:.06, ease:'power2.out'}); }
        else { [].forEach.call(bars, function(r,i){
                 r.style.transformOrigin='bottom'; r.style.transform='scaleY(0)';
                 r.style.transition='transform .55s cubic-bezier(.2,.7,.2,1)'; r.style.transitionDelay=(i*0.05)+'s';
                 requestAnimationFrame(function(){ requestAnimationFrame(function(){ r.style.transform='scaleY(1)'; }); }); }); }
      }

      // ── donut ring draw-on (segment sweep via stroke-dasharray) ──
      var arcs = b.querySelectorAll('.r-arc');
      if (arcs.length && G){
        [].forEach.call(arcs, function(a,i){
          var da = (a.getAttribute('stroke-dasharray')||'').split(/[ ,]+/).map(parseFloat);
          if (da.length < 2 || !isFinite(da[0])) return;
          var dash = da[0], circ = da[0] + da[1];
          G.fromTo(a, {attr:{'stroke-dasharray':'0 '+circ}},
                      {attr:{'stroke-dasharray':dash+' '+(circ-dash)}, duration:.7, delay:i*0.08, ease:'power1.inOut'});
        });
      } else if (arcs.length){
        [].forEach.call(arcs, function(a){ a.style.opacity='0'; a.style.transition='opacity .6s ease';
          requestAnimationFrame(function(){ a.style.opacity='1'; }); });
      }

      // ── line draw-on (stroke-dash sweep) ──
      var line = b.querySelector('.r-line');
      if (line && G && line.getTotalLength){
        var len = line.getTotalLength();
        G.fromTo(line, {attr:{'stroke-dasharray':len, 'stroke-dashoffset':len}},
                       {attr:{'stroke-dashoffset':0}, duration:.9, ease:'power1.inOut'});
      }

      // ── KPI count-up ──
      [].forEach.call(b.querySelectorAll('.r-kpi-n'), countUp);

      // ── §6.6.2 AI image KEN-BURNS: slow cinematic zoom + drift (premium) ──
      var aimg = b.querySelectorAll('.r-ai-img img');
      if (aimg.length && G){
        [].forEach.call(aimg, function(im){
          G.fromTo(im, {scale:1.05}, {scale:1.12, xPercent:1.5, yPercent:-1.5,
            duration:11, ease:'sine.inOut', repeat:-1, yoyo:true});
        });
      }
    }

    var io = new IntersectionObserver(function(entries){
      entries.forEach(function(e){ if (e.isIntersecting){ animate(e.target); io.unobserve(e.target); } });
    }, {threshold:0.12, rootMargin:'0px 0px -6% 0px'});
    blocks.forEach(function(b){ io.observe(b); });
  }catch(e){ showAll(); }
})();
""".strip()


# §6.6.1 / §6.12 batch 3 — the "Reka Insights" footer signature band. mascot.js +
# pixel.js are injected (viewer / export) like GSAP, so window.Mascot exists; this
# mounts THIS report's pet from the embedded gene with a light "presenting"
# celebrate then idle. Progressive enhancement: the band's wordmark + tagline are
# pure CSS (always visible) — only the sprite needs JS, so the band is never blank.
_REKA_SIGN_JS = """
(function(){
  try{
    var g = window.__REKA_GENE__;
    var el = document.getElementById('reka-sign-pet');
    if (!g || !el || !window.Mascot) return;
    var opts = {skin:g.skin, emblem:g.emblem, emblemColor:g.emblemColor,
      head:g.head||'none', leftItem:g.leftItem||'none', rightItem:g.rightItem||'none',
      carrier:g.carrier||'none', aura:g.aura||'soft', scale:3};
    var m = window.Mascot.mount(el, opts);
    if (matchMedia('(prefers-reduced-motion: reduce)').matches){ m.setState('idle'); return; }
    try{ m.set({eyes:'happy', mouth:'celebrate'}); m.setState('celebrate');
      setTimeout(function(){ try{ m.set({eyes:'normal', mouth:'idle'}); m.setState('idle'); }catch(e){} }, 1600);
    }catch(e){ try{ m.setState('idle'); }catch(_){} }
  }catch(e){}
})();
""".strip()


def _reka_band(pet_gene: Optional[dict]) -> str:
    """Footer signature band HTML. Always shows the 'Reka Insights' wordmark +
    tagline; the pet mount div is present only when there's a gene to render."""
    pet = '<div class="r-sign-pet" id="reka-sign-pet"></div>' if pet_gene else ""
    return (
        '<footer class="r-sign r-block">'
        f'{pet}'
        '<div class="r-sign-txt">'
        '<div class="r-sign-mark">Reka Insights</div>'
        '<div class="r-sign-tag">由你的 REKA 为你整理 · eureka.app</div>'
        '</div></footer>'
    )


_SIGN_CSS = (
    ".r-sign{display:flex;align-items:center;gap:12px;margin-top:34px;padding-top:18px;"
    "border-top:1px solid var(--line);}"
    ".r-sign-pet{width:48px;height:48px;flex:0 0 48px;}"
    ".r-sign-pet canvas{width:100%;height:100%;image-rendering:pixelated;}"
    ".r-sign-mark{font-weight:800;color:var(--hi);font-size:15px;letter-spacing:.3px;}"
    ".r-sign-tag{color:var(--lo);font-size:11px;margin-top:3px;}"
    # §6.6.2 — AI illustration inside the 「Eureka Moment」 band (never data).
    ".r-moment{margin:10px 0 22px;}"
    ".r-moment-tag{font-size:11px;letter-spacing:.16em;text-transform:uppercase;"
    "color:var(--lo);font-weight:600;margin:0 0 10px;}"
    ".r-moment-imgs{display:grid;gap:10px;}"
    ".r-moment-1{grid-template-columns:1fr;}"
    ".r-moment-2{grid-template-columns:1fr 1fr;}"
    # overflow:hidden + radius on the figure → the ken-burns zoom/drift stays clipped
    # inside rounded corners (no bleed). Natural image height (no forced crop); the
    # transform-scale clips against the figure frame, which is the ken-burns effect.
    ".r-ai-img{margin:0;border-radius:14px;overflow:hidden;will-change:transform;}"
    ".r-ai-img img{width:100%;height:auto;display:block;will-change:transform;}"
)


def render_report(
    content_md: str,
    seed_key: Optional[str] = None,
    *,
    palette: Optional[str] = None,
    surface: Optional[str] = None,
    seed: Optional[int] = None,
    pet_gene: Optional[dict] = None,
) -> dict:
    """Annotated Markdown → single-file HTML. Deterministic by seed.

    Overrides (for 换装 / re-render, §6.7): pass `seed` (int) to pick a fresh
    palette+surface combo deterministically, or pin `palette` / `surface`
    explicitly. Same content_md in → same look out, so re-render is reproducible.
    """
    meta, body = _parse_frontmatter(content_md)
    genre = (meta.get("genre") or "digest").strip()
    title = (meta.get("title") or "报告").strip()
    # Designed-render path (ported design handoff). Only ported genres use it;
    # every other genre falls through to the legacy renderer below (zero regression).
    from agents.report_render_designed import has_variant, render_designed
    if has_variant(genre):
        return render_designed(content_md, seed_key=seed_key, palette=palette,
                               surface=surface, seed=seed, pet_gene=pet_gene)
    seed = seed if seed is not None else _seed(seed_key or f"{title}|{genre}")
    palette_key = palette if palette in _PALETTES else _PALETTE_KEYS[seed % len(_PALETTE_KEYS)]
    pal = _PALETTES[palette_key]
    if surface not in _SURFACES:
        surface = _GENRE_SURFACE.get(genre, "magazine-lite")
    surf = _SURFACES[surface]

    blocks = _split_blocks(body)
    inner = _render_body(blocks, pal)

    # Masthead eyebrow (genre label · date range) — makes a report read as
    # intentional even when sparse. Placed above the body's title h1.
    eyebrow_label = {
        "data-report": "数据复盘", "idea-synthesis": "灵感综合",
        "proposal": "提案", "digest": "概览",
    }.get(genre, "报告")
    dates = re.findall(r"\d{4}-\d{2}-\d{2}", meta.get("time_range", "") or "")
    if len(dates) >= 2:
        date_str = f'{dates[0].replace("-", ".")} – {dates[1][5:].replace("-", ".")}'
    elif len(dates) == 1:
        date_str = dates[0].replace("-", ".")
    else:
        date_str = ""
    eyebrow = (
        f'<div class="r-eyebrow">{_esc(eyebrow_label)}'
        f'{(" · " + _esc(date_str)) if date_str else ""}</div>'
    )
    inner = eyebrow + inner
    css = _css(pal, surf) + _SIGN_CSS
    band = _reka_band(pet_gene)
    # Embedded gene + mount script (self-contained: the gene travels in the HTML,
    # so an exported file animates as long as mascot.js is present/inlined).
    gene_js = ""
    if pet_gene:
        gene_js = (
            f"<script>window.__REKA_GENE__={json.dumps(pet_gene, ensure_ascii=False)};</script>"
            f"<script>{_REKA_SIGN_JS}</script>"
        )

    html_doc = (
        "<!doctype html><html lang=\"zh\"><head><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
        f"<title>{_esc(title)}</title><style>{css}</style></head>"
        f"<body><div class=\"r-wrap\">{inner}{band}</div>"
        f"<script>{_ENHANCE_JS}</script>{gene_js}</body></html>"
    )
    return {
        "html": html_doc,
        "title": title,
        "genre": genre,
        "surface": surface,
        "palette": palette_key,
        "seed": seed,
    }
