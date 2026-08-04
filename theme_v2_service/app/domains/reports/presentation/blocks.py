import html
import re
from collections.abc import Callable


DIRECTIVE_RE = re.compile(r"^:::([a-zA-Z]+)(\{[^}]*\})?\s*(.*)$")
CHART_RE = re.compile(r"^\[\[chart:([A-Za-z0-9_-]+)\]\]$")
IMAGE_RE = re.compile(r"!\[[^\]]*\]\([^)]+\)")
BLOCK_START_RE = re.compile(
    r"^(?:#{1,4}\s+|:::|```|>|(?:\d+\.|[-*])\s+|\[\[chart:)"
)


def escape(value: object) -> str:
    return html.escape(str(value), quote=True)


def inline(text: str) -> str:
    rendered = escape(text)
    rendered = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", rendered)
    rendered = re.sub(r"`(.+?)`", r"<code>\1</code>", rendered)
    rendered = re.sub(
        r"(?<![\*\w])\*(?!\s)(.+?)(?<!\s)\*(?![\*\w])",
        r"<em>\1</em>",
        rendered,
    )
    return rendered


def _directive_lines(content: str) -> list[str]:
    return [line.strip() for line in content.splitlines() if line.strip()]


def render_kpi(_options: str, content: str) -> str:
    items: list[str] = []
    for line in _directive_lines(content):
        separator = "：" if "：" in line else (":" if ":" in line else None)
        if separator is None:
            continue
        label, value = (part.strip() for part in line.split(separator, 1))
        items.append(
            '<div class="r-kpi-item">'
            f'<div class="r-kpi-label">{escape(label)}</div>'
            f'<div class="r-kpi-n">{escape(value)}</div>'
            "</div>"
        )
    if not items:
        return ""
    return '<section class="r-block r-kpi" data-block="kpi">' + "".join(items) + "</section>"


def render_timeline(_options: str, content: str) -> str:
    items: list[str] = []
    for line in _directive_lines(content):
        match = re.match(r"^(.+?)\s*[—–-]\s*(.+)$", line)
        date, detail = (
            (match.group(1).strip(), match.group(2).strip())
            if match
            else ("", line)
        )
        items.append(
            '<div class="r-tl-item">'
            f'<div class="r-tl-date">{escape(date)}</div>'
            f'<div class="r-tl-text">{inline(detail)}</div>'
            "</div>"
        )
    if not items:
        return ""
    return '<section class="r-block r-timeline" data-block="timeline">' + "".join(items) + "</section>"


def render_rank(_options: str, content: str) -> str:
    items: list[str] = []
    for index, line in enumerate(_directive_lines(content), start=1):
        if not re.match(r"^(?:\d+\.|[-*])\s+", line):
            continue
        value = re.sub(r"^(?:\d+\.|[-*])\s+", "", line)
        items.append(
            f'<li><span class="r-rank-i">{index:02d}</span>'
            f'<span class="r-rank-lbl">{inline(value)}</span></li>'
        )
    if not items:
        return ""
    return '<section class="r-block"><ol class="r-rank" data-block="rank">' + "".join(items) + "</ol></section>"


def render_callout(options: str, content: str) -> str:
    match = re.search(r"tone\s*=\s*([a-zA-Z]+)", options)
    tone = match.group(1).lower() if match else "insight"
    tone = tone if tone in {"insight", "success", "warn"} else "insight"
    labels = {"insight": "洞察", "success": "方向", "warn": "注意"}
    return (
        f'<section class="r-block r-callout {tone}" data-block="callout">'
        f'<div class="r-callout-tag">{labels[tone]}</div>'
        f"<p>{inline(' '.join(_directive_lines(content)))}</p></section>"
    )


def render_quote(_options: str, content: str) -> str:
    lines = _directive_lines(content)
    source = ""
    if lines and re.match(r"^[—–-]\s*", lines[-1]):
        source = re.sub(r"^[—–-]\s*", "", lines.pop())
    cite = f"<cite>— {escape(source)}</cite>" if source else ""
    return (
        '<section class="r-block"><blockquote class="r-quote" data-block="quote">'
        f"{inline(' '.join(lines))}{cite}</blockquote></section>"
    )


def render_compare(_options: str, content: str) -> str:
    rows = [line for line in _directive_lines(content) if line.startswith("|")]
    if len(rows) < 2:
        return ""

    def cells(row: str) -> list[str]:
        return [cell.strip() for cell in row.strip("|").split("|")]

    header = cells(rows[0])
    data = [
        cells(row)
        for row in rows[1:]
        if not set(row.replace("|", "").strip()) <= set("-: ")
    ]
    headings = "".join(f"<th>{escape(cell)}</th>" for cell in header)
    body = "".join(
        "<tr>" + "".join(f"<td>{inline(cell)}</td>" for cell in row) + "</tr>"
        for row in data
    )
    return (
        '<section class="r-block r-table-wrap"><table class="r-compare" '
        f'data-block="compare"><thead><tr>{headings}</tr></thead>'
        f"<tbody>{body}</tbody></table></section>"
    )


BLOCK_RENDERERS: dict[str, Callable[[str, str], str]] = {
    "kpi": render_kpi,
    "timeline": render_timeline,
    "rank": render_rank,
    "callout": render_callout,
    "quote": render_quote,
    "compare": render_compare,
}


def render_blocks(content_md: str, *, chart_svgs: dict[str, str]) -> str:
    content_md = re.sub(
        r"<\s*(script|style)\b[^>]*>.*?<\s*/\s*\1\s*>",
        "",
        content_md,
        flags=re.IGNORECASE | re.DOTALL,
    )
    content_md = IMAGE_RE.sub("", content_md)
    content_md = re.sub(r"<[^>]+>", "", content_md)
    content_md = re.sub(
        r"(?m)^[ \t]*`+[ \t]*(:::[^`\n]*?)[ \t]*`+[ \t]*$",
        r"\1",
        content_md,
    )
    lines = content_md.splitlines()
    output: list[str] = []
    index = 0
    while index < len(lines):
        stripped = lines[index].strip()
        if not stripped:
            index += 1
            continue
        chart = CHART_RE.match(stripped)
        if chart:
            trusted_svg = chart_svgs.get(chart.group(1))
            if trusted_svg:
                output.append(
                    '<section class="r-block r-chart" data-block="chart">'
                    f"{trusted_svg}</section>"
                )
            index += 1
            continue
        directive = DIRECTIVE_RE.match(stripped)
        if directive:
            name = directive.group(1).lower()
            options = directive.group(2) or ""
            trailing = directive.group(3).strip()
            cursor = index + 1
            body: list[str] = []
            while cursor < len(lines) and lines[cursor].strip() != ":::":
                body.append(lines[cursor])
                cursor += 1
            if trailing:
                body.append(trailing)
            raw_body = "\n".join(body)
            renderer = BLOCK_RENDERERS.get(name)
            if renderer:
                output.append(renderer(options, raw_body))
            elif raw_body.strip():
                output.append(
                    '<section class="r-block"><p class="r-p">'
                    f"{inline(' '.join(_directive_lines(raw_body)))}</p></section>"
                )
            index = min(cursor + 1, len(lines))
            continue
        heading = re.match(r"^(#{1,4})\s+(.*)$", stripped)
        if heading:
            level = len(heading.group(1))
            if level > 1:
                output.append(
                    f'<h{level} class="r-h{level}">{inline(heading.group(2))}</h{level}>'
                )
            index += 1
            continue
        if stripped.startswith(">"):
            quoted: list[str] = []
            while index < len(lines) and lines[index].strip().startswith(">"):
                quoted.append(lines[index].strip()[1:].strip())
                index += 1
            output.append(render_quote("", "\n".join(quoted)))
            continue
        if re.match(r"^(?:\d+\.|[-*])\s+", stripped):
            ordered = bool(re.match(r"^\d+\.", stripped))
            items: list[str] = []
            while index < len(lines) and re.match(
                r"^(?:\d+\.|[-*])\s+", lines[index].strip()
            ):
                items.append(
                    re.sub(r"^(?:\d+\.|[-*])\s+", "", lines[index].strip())
                )
                index += 1
            tag = "ol" if ordered else "ul"
            output.append(
                f'<section class="r-block"><{tag} class="r-list">'
                + "".join(f"<li>{inline(item)}</li>" for item in items)
                + f"</{tag}></section>"
            )
            continue
        if stripped.startswith("```"):
            index += 1
            code: list[str] = []
            while index < len(lines) and not lines[index].strip().startswith("```"):
                code.append(lines[index])
                index += 1
            index += 1
            output.append(f"<pre><code>{escape(chr(10).join(code))}</code></pre>")
            continue
        paragraph: list[str] = []
        while index < len(lines):
            candidate = lines[index].strip()
            if not candidate or BLOCK_START_RE.match(candidate):
                break
            paragraph.append(candidate)
            index += 1
        if paragraph:
            output.append(
                '<section class="r-block"><p class="r-p">'
                f"{inline(' '.join(paragraph))}</p></section>"
            )
        else:
            output.append(
                f'<section class="r-block"><p class="r-p">{inline(stripped)}</p></section>'
            )
            index += 1
    return "".join(output)
