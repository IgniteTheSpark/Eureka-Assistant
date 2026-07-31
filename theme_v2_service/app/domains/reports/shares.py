import hashlib
import secrets
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from html import escape
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import utc_now
from app.domains.reports.models import File, Report, ReportShare
from app.domains.reports.rendering import render_report_html
from app.domains.reports.schemas import ShareCardSpec
from app.domains.reports.share_cards import RenderedShareCard, render_share_card
from app.domains.reports.storage import Storage, persist_owned_file
from app.observability import metrics


TEMPLATE_ROOT = Path(__file__).resolve().parents[2] / "templates"


@dataclass(frozen=True)
class CreatedShare:
    share: ReportShare
    token: str


def issue_share_token() -> str:
    return secrets.token_urlsafe(32)


def hash_share_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _utc_naive(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def _replace_internal_ids(value: str | None, replacements: dict[str, str]) -> str | None:
    if value is None:
        return None
    sanitized = value
    for internal_id in sorted(replacements, key=len, reverse=True):
        sanitized = sanitized.replace(internal_id, replacements[internal_id])
    return sanitized


def _safe_external_sources(raw_sources: list[dict]) -> list[dict]:
    sources = []
    for raw in raw_sources:
        if not isinstance(raw, dict):
            continue
        sources.append(
            {
                key: raw.get(key)
                for key in ("title", "url", "accessed_at", "authoritative")
                if raw.get(key) is not None
            }
        )
    return sources


async def create_report_share(
    session: AsyncSession,
    *,
    user_id: str,
    report_id: str,
    now: datetime | None = None,
    expires_in_days: int = 30,
) -> CreatedShare | None:
    report = await session.scalar(
        select(Report).where(
            Report.id == report_id,
            Report.user_id == user_id,
        )
    )
    if report is None:
        return None
    spec = dict(report.spec_json or {})
    requested_file_ids = list(
        dict.fromkeys(
            [
                *spec.get("generated_file_ids", []),
                *(
                    [report.share_card_spec.get("illustration_file_id")]
                    if report.share_card_spec.get("illustration_file_id")
                    else []
                ),
            ]
        )
    )
    owned_files = []
    if requested_file_ids:
        owned_files = list(
            await session.scalars(
                select(File).where(
                    File.id.in_(requested_file_ids),
                    File.user_id == user_id,
                )
            )
        )
    by_id = {file.id: file for file in owned_files}
    media_map: dict[str, str] = {}
    file_to_media: dict[str, str] = {}
    for file_id in requested_file_ids:
        if file_id not in by_id:
            continue
        media_key = secrets.token_urlsafe(16)
        while media_key in media_map:
            media_key = secrets.token_urlsafe(16)
        media_map[media_key] = file_id
        file_to_media[file_id] = media_key

    snapshot_content = report.content_md
    snapshot_html = report.html
    for file_id, media_key in file_to_media.items():
        snapshot_content = snapshot_content.replace(
            f"media:{file_id}",
            f"media:{media_key}",
        )
        if snapshot_html is not None:
            snapshot_html = snapshot_html.replace(
                f"/api/files/{file_id}",
                f"share-media:{media_key}",
            )

    internal_ids = [
        report.id,
        report.generation_run_id,
        *spec.get("source_asset_ids", []),
        *spec.get("unavailable_asset_ids", []),
        *requested_file_ids,
    ]
    replacements = {
        internal_id: f"evidence-{index + 1}"
        for index, internal_id in enumerate(
            item for item in dict.fromkeys(internal_ids) if item
        )
    }
    snapshot_content = _replace_internal_ids(snapshot_content, replacements) or ""
    snapshot_html = _replace_internal_ids(snapshot_html, replacements)

    share_card = ShareCardSpec.model_validate(report.share_card_spec).model_copy(
        update={"illustration_file_id": None}
    )
    illustration_media_key = file_to_media.get(
        report.share_card_spec.get("illustration_file_id")
    )
    public_spec = {
        "surface": spec.get("surface", "report"),
        "palette": spec.get("palette", "calm"),
        "time_range": spec.get("time_range"),
        "web_policy": spec.get("web_policy", "none"),
        "external_sources": _safe_external_sources(
            spec.get("external_sources", [])
        ),
        "share_card": share_card.model_dump(mode="json"),
        "illustration_media_key": illustration_media_key,
    }
    issued_at = _utc_naive(now or utc_now())
    token = issue_share_token()
    share = ReportShare(
        report_id=report.id,
        user_id=user_id,
        token_hash=hash_share_token(token),
        status="active",
        expires_at=issued_at + timedelta(days=expires_in_days),
        snapshot_content_md=snapshot_content,
        snapshot_spec_json=public_spec,
        snapshot_html=snapshot_html,
        media_map_json=media_map,
        share_card_file_id=None,
        created_at=issued_at,
    )
    session.add(share)
    await session.flush()
    metrics.increment("share_created_total")
    return CreatedShare(share=share, token=token)


async def generate_share_card_for_share(
    session: AsyncSession,
    *,
    share: ReportShare,
    token: str,
    public_base_url: str,
    storage: Storage,
    renderer: Callable[..., RenderedShareCard] = render_share_card,
) -> File | None:
    if share.share_card_file_id:
        existing = await session.scalar(
            select(File).where(
                File.id == share.share_card_file_id,
                File.user_id == share.user_id,
            )
        )
        if existing is not None:
            return existing
    spec = ShareCardSpec.model_validate(
        share.snapshot_spec_json.get("share_card", {})
    )
    illustration_bytes = None
    illustration_key = share.snapshot_spec_json.get("illustration_media_key")
    if illustration_key:
        illustration_file = await get_share_media_file(
            session,
            share=share,
            media_key=illustration_key,
        )
        if illustration_file is not None:
            try:
                illustration_bytes = await storage.get(
                    illustration_file.storage_key
                )
            except (FileNotFoundError, ValueError):
                illustration_bytes = None
    public_url = f"{public_base_url.rstrip('/')}/r/{token}"
    try:
        rendered = renderer(
            spec,
            public_url=public_url,
            illustration_bytes=illustration_bytes,
            forbidden_ids={
                share.id,
                share.report_id,
                *share.media_map_json.values(),
            },
        )
        file = await persist_owned_file(
            session,
            storage=storage,
            user_id=share.user_id,
            purpose="report_share_card",
            key=f"report-shares/{share.user_id}/{share.id}/card.png",
            content=rendered.png_bytes,
            mime_type="image/png",
        )
    except Exception:
        snapshot = dict(share.snapshot_spec_json)
        warnings = list(snapshot.get("warnings", []))
        if "share card generation failed" not in warnings:
            warnings.append("share card generation failed")
        snapshot["warnings"] = warnings
        share.snapshot_spec_json = snapshot
        await session.flush()
        return None

    media_map = dict(share.media_map_json or {})
    media_key = secrets.token_urlsafe(16)
    while media_key in media_map:
        media_key = secrets.token_urlsafe(16)
    media_map[media_key] = file.id
    share.media_map_json = media_map
    share.share_card_file_id = file.id
    snapshot = dict(share.snapshot_spec_json)
    warnings = [
        warning
        for warning in snapshot.get("warnings", [])
        if warning != "share card generation failed"
    ]
    if warnings:
        snapshot["warnings"] = warnings
    else:
        snapshot.pop("warnings", None)
    share.snapshot_spec_json = snapshot
    await session.flush()
    metrics.increment("share_card_generated_total")
    return file


async def get_active_share(
    session: AsyncSession,
    *,
    token: str,
    now: datetime | None = None,
) -> ReportShare | None:
    checked_at = _utc_naive(now or utc_now())
    return await session.scalar(
        select(ReportShare).where(
            ReportShare.token_hash == hash_share_token(token),
            ReportShare.status == "active",
            (ReportShare.expires_at.is_(None) | (ReportShare.expires_at > checked_at)),
        )
    )


async def revoke_report_share(
    session: AsyncSession,
    *,
    user_id: str,
    share_id: str,
    now: datetime | None = None,
) -> bool:
    share = await session.scalar(
        select(ReportShare)
        .where(
            ReportShare.id == share_id,
            ReportShare.user_id == user_id,
        )
        .with_for_update()
    )
    if share is None:
        return False
    if share.status != "revoked":
        share.status = "revoked"
        share.revoked_at = _utc_naive(now or utc_now())
        await session.flush()
        metrics.increment("share_revoked_total")
    return True


async def get_share_media_file(
    session: AsyncSession,
    *,
    share: ReportShare,
    media_key: str,
) -> File | None:
    file_id = (share.media_map_json or {}).get(media_key)
    if file_id is None:
        return None
    return await session.scalar(
        select(File).where(
            File.id == file_id,
            File.user_id == share.user_id,
        )
    )


def serialize_public_share(share: ReportShare, *, token: str) -> dict:
    share_card_key = next(
        (
            media_key
            for media_key, file_id in (share.media_map_json or {}).items()
            if file_id == share.share_card_file_id
        ),
        None,
    )
    return {
        "content_md": share.snapshot_content_md,
        "html": public_share_html(share, token=token),
        "spec": share.snapshot_spec_json,
        "media": [
            {
                "key": media_key,
                "url": f"/r/{token}/media/{media_key}",
            }
            for media_key in (share.media_map_json or {})
        ],
        "share_card_url": (
            f"/r/{token}/media/{share_card_key}" if share_card_key else None
        ),
        "expires_at": (
            share.expires_at.replace(tzinfo=timezone.utc)
            .isoformat()
            .replace("+00:00", "Z")
            if share.expires_at
            else None
        ),
    }


def public_share_html(share: ReportShare, *, token: str) -> str:
    media_urls = {
        media_key: f"/r/{token}/media/{media_key}"
        for media_key in (share.media_map_json or {})
    }
    if share.snapshot_html:
        snapshot = share.snapshot_html
        for media_key, url in media_urls.items():
            snapshot = snapshot.replace(f"share-media:{media_key}", url)
    else:
        share_card = share.snapshot_spec_json.get("share_card", {})
        snapshot = render_report_html(
            title=share_card.get("headline", "Eureka Report"),
            content_md=share.snapshot_content_md,
            chart_svgs={},
            media_urls=media_urls,
        )
    share_card_key = next(
        (
            media_key
            for media_key, file_id in (share.media_map_json or {}).items()
            if file_id == share.share_card_file_id
        ),
        None,
    )
    if share_card_key:
        og_image_url = escape(
            f"/r/{token}/media/{share_card_key}",
            quote=True,
        )
        og_meta = f'<meta property="og:image" content="{og_image_url}">\n'
        head_end = snapshot.lower().find("</head>")
        if head_end >= 0:
            snapshot = f"{snapshot[:head_end]}{og_meta}{snapshot[head_end:]}"
        else:
            snapshot = f"{og_meta}{snapshot}"
    environment = Environment(
        loader=FileSystemLoader(TEMPLATE_ROOT),
        autoescape=select_autoescape(("html", "xml")),
    )
    return environment.get_template("public_report.html.j2").render(
        snapshot_html=snapshot
    )
