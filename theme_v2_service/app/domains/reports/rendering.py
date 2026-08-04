import re
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from pathlib import Path

import bleach
from jinja2 import Environment, FileSystemLoader, select_autoescape
from markdown_it import MarkdownIt

from app.domains.reports.providers import (
    GeneratedImage,
    IllustrationProvider,
)
from app.domains.reports.providers_image import sanitize_illustration_prompt
from app.domains.reports.schemas import CapabilityExecution


TEMPLATE_ROOT = Path(__file__).resolve().parents[2] / "templates"
REPORT_CSS = (
    Path(__file__).resolve().parents[2] / "static" / "report-v1.css"
).read_text(encoding="utf-8")
SCRIPT_BLOCK_RE = re.compile(
    r"<\s*(script|style)\b[^>]*>.*?<\s*/\s*\1\s*>",
    re.IGNORECASE | re.DOTALL,
)
RAW_TAG_RE = re.compile(r"<[^>]+>")
MEDIA_REFERENCE_RE = re.compile(r"\(media:([A-Za-z0-9_-]+)\)")
CHART_PARAGRAPH_RE = re.compile(
    r"<p>\s*\[\[chart:([A-Za-z0-9_-]+)\]\]\s*</p>"
)
IMAGE_TAG_RE = re.compile(r"<img\s+([^>]*?)>")

ALLOWED_TAGS = {
    "h1",
    "h2",
    "h3",
    "h4",
    "p",
    "ul",
    "ol",
    "li",
    "strong",
    "em",
    "blockquote",
    "code",
    "pre",
    "hr",
    "a",
    "img",
    "table",
    "thead",
    "tbody",
    "tr",
    "th",
    "td",
}


@dataclass(frozen=True)
class IllustrationOutcome:
    execution: CapabilityExecution
    file_id: str | None = None
    image: GeneratedImage | None = None
    warnings: list[str] = field(default_factory=list)


def _template_environment() -> Environment:
    return Environment(
        loader=FileSystemLoader(TEMPLATE_ROOT),
        autoescape=select_autoescape(("html", "xml")),
        keep_trailing_newline=True,
    )


def _replace_media_references(content: str, media_urls: dict[str, str]) -> str:
    def replace(match: re.Match[str]) -> str:
        media_id = match.group(1)
        url = media_urls.get(media_id)
        return f"({url})" if url else "()"

    return MEDIA_REFERENCE_RE.sub(replace, content)


def _sanitize_html(raw_html: str, controlled_urls: set[str]) -> str:
    def allow_attribute(tag: str, name: str, value: str) -> bool:
        if tag == "a":
            return name in {"href", "title"}
        if tag == "img":
            if name == "src":
                return value in controlled_urls and value.startswith(
                    ("/api/files/", "/r/")
                )
            return name in {"alt", "title"}
        if tag in {"th", "td"}:
            return name in {"colspan", "rowspan"}
        return False

    cleaned = bleach.clean(
        raw_html,
        tags=ALLOWED_TAGS,
        attributes=allow_attribute,
        protocols={"http", "https"},
        strip=True,
    )

    def add_lazy_loading(match: re.Match[str]) -> str:
        attributes = match.group(1)
        if "src=" not in attributes:
            return ""
        return f'<img {attributes} loading="lazy">'

    return IMAGE_TAG_RE.sub(add_lazy_loading, cleaned)


def render_report_html(
    *,
    title: str,
    content_md: str,
    chart_svgs: dict[str, str],
    media_urls: dict[str, str],
) -> str:
    without_executable_blocks = SCRIPT_BLOCK_RE.sub("", content_md)
    without_raw_tags = RAW_TAG_RE.sub("", without_executable_blocks)
    prepared = _replace_media_references(without_raw_tags, media_urls)
    markdown = MarkdownIt("commonmark", {"html": False, "linkify": False})
    rendered = markdown.render(prepared)
    safe_body = _sanitize_html(rendered, set(media_urls.values()))

    def replace_chart(match: re.Match[str]) -> str:
        return chart_svgs.get(match.group(1), "")

    safe_body = CHART_PARAGRAPH_RE.sub(replace_chart, safe_body)
    template = _template_environment().get_template("report.html.j2")
    return template.render(
        title=title,
        body_html=safe_body,
        report_css=REPORT_CSS,
    )


async def generate_optional_illustration(
    *,
    policy: str,
    prompt: str | None,
    provider: IllustrationProvider,
    store_image: Callable[[GeneratedImage], Awaitable[str]] | None,
    sensitive_values: list[str] | None = None,
) -> IllustrationOutcome:
    if policy == "none":
        return IllustrationOutcome(
            execution=CapabilityExecution(policy=policy, status="not_requested")
        )
    if not prompt:
        return IllustrationOutcome(
            execution=CapabilityExecution(policy=policy, status="skipped")
        )
    sanitized = sanitize_illustration_prompt(
        prompt,
        sensitive_values=sensitive_values,
    )
    if not sanitized:
        return IllustrationOutcome(
            execution=CapabilityExecution(policy=policy, status="failed_degraded"),
            warnings=["illustration prompt was removed by safety policy"],
        )
    try:
        image = await provider.generate(sanitized)
        if not image.mime_type.startswith("image/"):
            raise ValueError("illustration result is not an image")
        file_id = await store_image(image) if store_image is not None else None
    except Exception:
        return IllustrationOutcome(
            execution=CapabilityExecution(policy=policy, status="failed_degraded"),
            warnings=["illustration generation failed"],
        )
    return IllustrationOutcome(
        execution=CapabilityExecution(
            policy=policy,
            status="succeeded",
            file_ids=[file_id] if file_id else [],
        ),
        file_id=file_id,
        image=image,
    )
