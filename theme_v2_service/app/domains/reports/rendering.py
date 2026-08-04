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


@dataclass(frozen=True)
class IllustrationOutcome:
    execution: CapabilityExecution
    file_id: str | None = None
    image: GeneratedImage | None = None
    warnings: list[str] = field(default_factory=list)


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
    ).html


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
