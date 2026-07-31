import hashlib
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import utc_now
from app.domains.reports.models import File, Report, ReportShare
from app.domains.reports.rendering import render_report_html
from app.domains.reports.schemas import ShareCardSpec


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
    public_spec = {
        "surface": spec.get("surface", "report"),
        "palette": spec.get("palette", "calm"),
        "time_range": spec.get("time_range"),
        "web_policy": spec.get("web_policy", "none"),
        "external_sources": _safe_external_sources(
            spec.get("external_sources", [])
        ),
        "share_card": share_card.model_dump(mode="json"),
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
    return CreatedShare(share=share, token=token)


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
    environment = Environment(
        loader=FileSystemLoader(TEMPLATE_ROOT),
        autoescape=select_autoescape(("html", "xml")),
    )
    return environment.get_template("public_report.html.j2").render(
        snapshot_html=snapshot
    )
