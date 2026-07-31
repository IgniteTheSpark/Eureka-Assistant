from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.responses import HTMLResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.config import get_settings
from app.db.session import get_session
from app.domains.reports.models import File, Report
from app.domains.reports.rendering import render_report_html
from app.domains.reports.shares import (
    create_report_share,
    get_active_share,
    get_share_media_file,
    public_share_html,
    revoke_report_share,
    serialize_public_share,
)
from app.domains.reports.service import get_owned_report, list_owned_reports
from app.domains.reports.storage import LocalStorage, StorageKeyRejected


router = APIRouter(tags=["reports"])


def _timestamp(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _serialize_report(report: Report) -> dict:
    return {
        "id": report.id,
        "title": report.title,
        "template_id": report.template_id,
        "template_version": report.template_version,
        "base_family": report.base_family,
        "content_md": report.content_md,
        "html": report.html,
        "spec": report.spec_json,
        "share_card": report.share_card_spec,
        "tokens_used": report.tokens_used,
        "gen_ms": report.gen_ms,
        "created_at": _timestamp(report.created_at),
    }


@router.get("/api/reports")
async def list_reports(
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> list[dict]:
    reports = await list_owned_reports(session, user_id=user_id)
    return [_serialize_report(report) for report in reports]


@router.get("/api/reports/{report_id}")
async def get_report(
    report_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    report = await get_owned_report(
        session,
        user_id=user_id,
        report_id=report_id,
    )
    if report is None:
        raise HTTPException(status_code=404, detail="not found")
    return _serialize_report(report)


@router.get("/app/reports/{report_id}", response_class=HTMLResponse)
async def view_report(
    report_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> HTMLResponse:
    report = await get_owned_report(
        session,
        user_id=user_id,
        report_id=report_id,
    )
    if report is None:
        raise HTTPException(status_code=404, detail="not found")
    html = report.html or render_report_html(
        title=report.title,
        content_md=report.content_md,
        chart_svgs={},
        media_urls={},
    )
    return HTMLResponse(
        html,
        headers={"Cache-Control": "private, no-store"},
    )


@router.get("/api/files/{file_id}")
async def get_private_file(
    file_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> Response:
    file = await session.scalar(
        select(File).where(File.id == file_id, File.user_id == user_id)
    )
    if file is None:
        raise HTTPException(status_code=404, detail="not found")
    storage = LocalStorage(Path(get_settings().media_root))
    try:
        content = await storage.get(file.storage_key)
    except (FileNotFoundError, StorageKeyRejected) as exc:
        raise HTTPException(status_code=404, detail="not found") from exc
    return Response(
        content,
        media_type=file.mime_type,
        headers={"Cache-Control": "private, max-age=3600"},
    )


@router.post("/api/reports/{report_id}/shares")
async def create_share(
    report_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    created = await create_report_share(
        session,
        user_id=user_id,
        report_id=report_id,
    )
    if created is None:
        raise HTTPException(status_code=404, detail="not found")
    base_url = get_settings().report_public_base_url.rstrip("/")
    return {
        "share_id": created.share.id,
        "url": f"{base_url}/r/{created.token}",
        "expires_at": _timestamp(created.share.expires_at),
    }


@router.delete("/api/report-shares/{share_id}")
async def revoke_share(
    share_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    revoked = await revoke_report_share(
        session,
        user_id=user_id,
        share_id=share_id,
    )
    if not revoked:
        raise HTTPException(status_code=404, detail="not found")
    return {"ok": True}


@router.get("/api/public/report-shares/{share_token}")
async def get_public_share(
    share_token: str,
    session: AsyncSession = Depends(get_session),
) -> Response:
    share = await get_active_share(session, token=share_token)
    if share is None:
        raise HTTPException(status_code=404, detail="not found")
    import orjson

    return Response(
        orjson.dumps(serialize_public_share(share, token=share_token)),
        media_type="application/json",
        headers={
            "X-Robots-Tag": "noindex",
            "Cache-Control": "no-store",
        },
    )


@router.get("/r/{share_token}", response_class=HTMLResponse)
async def view_public_share(
    share_token: str,
    session: AsyncSession = Depends(get_session),
) -> HTMLResponse:
    share = await get_active_share(session, token=share_token)
    if share is None:
        raise HTTPException(status_code=404, detail="not found")
    return HTMLResponse(
        public_share_html(share, token=share_token),
        headers={
            "X-Robots-Tag": "noindex",
            "Cache-Control": "no-store",
        },
    )


@router.get("/r/{share_token}/media/{media_key}")
async def get_public_share_media(
    share_token: str,
    media_key: str,
    session: AsyncSession = Depends(get_session),
) -> Response:
    share = await get_active_share(session, token=share_token)
    if share is None:
        raise HTTPException(status_code=404, detail="not found")
    file = await get_share_media_file(
        session,
        share=share,
        media_key=media_key,
    )
    if file is None:
        raise HTTPException(status_code=404, detail="not found")
    storage = LocalStorage(Path(get_settings().media_root))
    try:
        content = await storage.get(file.storage_key)
    except (FileNotFoundError, StorageKeyRejected) as exc:
        raise HTTPException(status_code=404, detail="not found") from exc
    return Response(
        content,
        media_type=file.mime_type,
        headers={
            "X-Robots-Tag": "noindex",
            "Cache-Control": "no-store",
        },
    )
