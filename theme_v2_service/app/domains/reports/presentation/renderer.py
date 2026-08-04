from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from jinja2 import Environment, FileSystemLoader, select_autoescape

from app.domains.reports.presentation.blocks import escape, render_blocks
from app.domains.reports.presentation.catalog import ColorScheme, select_variant
from app.domains.reports.presentation.styles import stylesheet
from app.domains.reports.schemas import ReportSuggestedAction


TEMPLATE_ROOT = Path(__file__).resolve().parents[3] / "templates"
OWNED_IMAGE_PREFIXES = ("/api/files/", "/r/")
FAMILY_LABELS = {
    "data_trend": "数据复盘",
    "theme_synthesis": "主题综合",
    "professional_evaluation": "专业评估",
    "briefing_research": "调研简报",
}


@dataclass(frozen=True)
class PresentationRequest:
    title: str
    content_md: str
    base_family: str
    seed: int
    chart_svgs: dict[str, str] = field(default_factory=dict)
    illustration_url: str | None = None
    external_sources: list[dict[str, Any]] = field(default_factory=list)
    suggested_actions: list[ReportSuggestedAction] = field(default_factory=list)


@dataclass(frozen=True)
class PresentationResult:
    html: str
    surface: str
    palette: str
    color_scheme: ColorScheme
    warnings: list[str] = field(default_factory=list)


def _environment() -> Environment:
    return Environment(
        loader=FileSystemLoader(TEMPLATE_ROOT),
        autoescape=select_autoescape(("html", "xml")),
        keep_trailing_newline=True,
    )


def _masthead(title: str, base_family: str) -> str:
    label = FAMILY_LABELS.get(base_family, "报告")
    return (
        '<header class="r-masthead">'
        f'<p class="r-eyebrow">REKA INSIGHTS · {escape(label)}</p>'
        f'<h1 class="r-h1">{escape(title)}</h1>'
        "</header>"
    )


def _illustration(url: str | None, warnings: list[str]) -> str:
    if not url:
        return ""
    if not url.startswith(OWNED_IMAGE_PREFIXES):
        warnings.append("illustration URL was not owned")
        return ""
    return (
        '<figure class="r-illustration">'
        f'<img src="{escape(url)}" alt="报告插图" loading="lazy">'
        "</figure>"
    )


def _date_label(value: datetime | None) -> str:
    if value is None:
        return ""
    return value.isoformat(timespec="minutes")


def _actions(actions: list[ReportSuggestedAction]) -> str:
    if not actions:
        return ""
    rows: list[str] = []
    for action in actions[:5]:
        due_at = _date_label(action.due_at)
        due_html = (
            f'<span class="r-action-due">{escape(due_at)}</span>' if due_at else ""
        )
        rows.append(
            f'<div class="r-action" data-action-id="{escape(action.id)}">'
            '<span class="r-action-check" aria-hidden="true"></span>'
            f'<span class="r-action-title">{escape(action.title)}</span>'
            f"{due_html}</div>"
        )
    return (
        '<section class="r-actions" aria-labelledby="report-actions-title">'
        '<h2 class="r-section-label" id="report-actions-title">接下来</h2>'
        f'<div class="r-action-list">{"".join(rows)}</div></section>'
    )


def _accessed_date(value: object) -> str:
    if not value:
        return ""
    text = str(value)
    return text[:10] if len(text) >= 10 else text


def _sources(sources: list[dict[str, Any]]) -> str:
    rows: list[str] = []
    seen: set[str] = set()
    for source in sources:
        url = str(source.get("url") or "").strip()
        parsed = urlsplit(url)
        if parsed.scheme != "https" or not parsed.netloc or url in seen:
            continue
        seen.add(url)
        title = str(source.get("title") or parsed.netloc).strip()
        accessed = _accessed_date(source.get("accessed_at"))
        meta = parsed.netloc + (f" · {accessed}" if accessed else "")
        rows.append(
            '<li class="r-source">'
            f'<a href="{escape(url)}" rel="noreferrer noopener">{escape(title)}</a>'
            f'<div class="r-source-meta">{escape(meta)}</div></li>'
        )
    if not rows:
        return ""
    return (
        '<section class="r-sources" aria-labelledby="report-sources-title">'
        '<h2 class="r-section-label" id="report-sources-title">参考来源</h2>'
        f'<ul class="r-source-list">{"".join(rows)}</ul></section>'
    )


def render_presentation(request: PresentationRequest) -> PresentationResult:
    variant, used_fallback = select_variant(request.base_family, request.seed)
    warnings = ["unknown base family used briefing fallback"] if used_fallback else []
    illustration_html = _illustration(request.illustration_url, warnings)
    body_html = render_blocks(request.content_md, chart_svgs=request.chart_svgs)
    template = _environment().get_template("report.html.j2")
    rendered = template.render(
        title=request.title,
        report_css=stylesheet(variant, variant.color_scheme),
        color_scheme=variant.color_scheme,
        palette=variant.palette,
        surface=variant.surface,
        masthead_html=_masthead(request.title, request.base_family),
        body_html=illustration_html + body_html,
        actions_html=_actions(request.suggested_actions),
        sources_html=_sources(request.external_sources),
    )
    return PresentationResult(
        html=rendered,
        surface=variant.surface,
        palette=variant.palette,
        color_scheme=variant.color_scheme,
        warnings=warnings,
    )
