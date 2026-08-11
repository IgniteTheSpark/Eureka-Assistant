import asyncio
import re
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field

from app.domains.reports.presentation import (
    PresentationRequest,
    PresentationResult,
    render_presentation,
)
from app.domains.reports.providers import GeneratedImage, IllustrationProvider
from app.domains.reports.providers_image import sanitize_illustration_prompt
from app.domains.reports.schemas import CapabilityExecution, ReportSuggestedAction


MEDIA_REFERENCE_RE = re.compile(r"\(media:([A-Za-z0-9_-]+)\)")
PENDING_ILLUSTRATION_SLOT_RE = re.compile(
    r'<figure id="reka-report-illustration" '
    r'class="r-illustration r-illustration--pending" '
    r'data-illustration-status="pending" '
    r'aria-label="报告配图生成中">'
    r'<div class="r-illustration-placeholder"></div>'
    r'</figure>'
)
OWNED_FILE_URL_RE = re.compile(r"/api/files/[A-Za-z0-9_-]+")


@dataclass(frozen=True)
class IllustrationOutcome:
    execution: CapabilityExecution
    file_id: str | None = None
    image: GeneratedImage | None = None
    warnings: list[str] = field(default_factory=list)


def replace_pending_illustration_slot(html: str, file_url: str) -> str:
    if OWNED_FILE_URL_RE.fullmatch(file_url) is None:
        raise ValueError("illustration URL is not owned")
    matches = list(PENDING_ILLUSTRATION_SLOT_RE.finditer(html))
    if len(matches) != 1:
        raise ValueError("pending illustration slot must appear exactly once")
    replacement = (
        '<figure id="reka-report-illustration" class="r-illustration" '
        'data-illustration-status="ready">'
        f'<img src="{file_url}" alt="报告插图" loading="lazy">'
        "</figure>"
    )
    return PENDING_ILLUSTRATION_SLOT_RE.sub(replacement, html, count=1)


def remove_pending_illustration_slot(html: str) -> str:
    matches = list(PENDING_ILLUSTRATION_SLOT_RE.finditer(html))
    if len(matches) != 1:
        raise ValueError("pending illustration slot must appear exactly once")
    return PENDING_ILLUSTRATION_SLOT_RE.sub("", html, count=1)


def _illustration_url(
    *,
    content_md: str,
    media_urls: dict[str, str],
    illustration_file_id: str | None,
) -> str | None:
    if illustration_file_id:
        return media_urls.get(illustration_file_id)
    for match in MEDIA_REFERENCE_RE.finditer(content_md):
        url = media_urls.get(match.group(1))
        if url:
            return url
    return None


def render_report_presentation(
    *,
    title: str,
    content_md: str,
    chart_svgs: dict[str, str],
    media_urls: dict[str, str],
    base_family: str = "briefing_research",
    seed: int = 0,
    external_sources: list[dict] | None = None,
    suggested_actions: list[ReportSuggestedAction] | None = None,
    illustration_file_id: str | None = None,
    illustration_status: str = "not_required",
) -> PresentationResult:
    return render_presentation(
        PresentationRequest(
            title=title,
            content_md=content_md,
            base_family=base_family,
            seed=seed,
            chart_svgs=chart_svgs,
            illustration_url=_illustration_url(
                content_md=content_md,
                media_urls=media_urls,
                illustration_file_id=illustration_file_id,
            ),
            illustration_status=illustration_status,
            external_sources=external_sources or [],
            suggested_actions=suggested_actions or [],
        )
    )


def render_report_html(
    *,
    title: str,
    content_md: str,
    chart_svgs: dict[str, str],
    media_urls: dict[str, str],
) -> str:
    return render_report_presentation(
        title=title,
        content_md=content_md,
        chart_svgs=chart_svgs,
        media_urls=media_urls,
        base_family="briefing_research",
        seed=0,
        external_sources=[],
        suggested_actions=[],
        illustration_file_id=None,
        illustration_status="not_required",
    ).html


async def generate_optional_illustration(
    *,
    policy: str,
    prompt: str | None,
    provider: IllustrationProvider,
    store_image: Callable[[GeneratedImage], Awaitable[str]] | None,
    sensitive_values: list[str] | None = None,
    optional_timeout_seconds: float | None = None,
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
        if policy == "optional" and optional_timeout_seconds is not None:
            try:
                async with asyncio.timeout(optional_timeout_seconds):
                    image = await provider.generate(sanitized)
            except TimeoutError:
                return IllustrationOutcome(
                    execution=CapabilityExecution(
                        policy=policy,
                        status="failed_degraded",
                    ),
                    warnings=["illustration exceeded optional time budget"],
                )
        else:
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
