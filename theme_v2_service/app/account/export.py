"""Account data export (§9).

Adopts the mature legacy interaction: selective per-type export to Markdown or
CSV, user-scoped, streaming via paged queries. The CSV contract is the legacy
flat heterogeneous table `kind,type,title,domain,created_at,detail_json`.
"""
from __future__ import annotations

import csv
import io
import json
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset, Contact, Event, UserSkill

_BEIJING = timezone(timedelta(hours=8))
_PAGE_SIZE = 200

# payload plumbing keys never worth exporting.
_SKIP_KEYS = {
    "contact_id", "asset_id", "event_id", "id", "user_id", "user_skill_name",
    "session_id", "source_input_turn_id", "status", "ok", "card_type",
}


def _fmt_dt(value: Any) -> str:
    if not value:
        return ""
    if isinstance(value, datetime):
        return value.astimezone(_BEIJING).strftime("%Y-%m-%d %H:%M")
    try:
        return (
            datetime.fromisoformat(str(value).replace("Z", "+00:00"))
            .astimezone(_BEIJING)
            .strftime("%Y-%m-%d %H:%M")
        )
    except (ValueError, TypeError):
        return str(value)


def _clean_payload(payload: dict) -> dict:
    return {k: v for k, v in payload.items() if k not in _SKIP_KEYS}


async def export_options(session: AsyncSession, user_id: str) -> dict:
    """Per-type available record counts; zero-count types are hidden."""
    options: list[dict] = []

    skill_counts = (
        await session.execute(
            select(UserSkill.id, UserSkill.display_name, func.count(Asset.id))
            .join(Asset, Asset.user_skill_id == UserSkill.id)
            .where(Asset.user_id == user_id)
            .group_by(UserSkill.id, UserSkill.display_name)
        )
    ).all()
    for skill_id, name, count in skill_counts:
        options.append({"type": f"skill:{skill_id}", "name": name, "count": int(count)})

    event_count = (
        await session.scalar(
            select(func.count(Event.id)).where(Event.user_id == user_id)
        )
    ) or 0
    if event_count:
        options.append({"type": "event", "name": "事件", "count": int(event_count)})

    contact_count = (
        await session.scalar(
            select(func.count(Contact.id)).where(Contact.user_id == user_id)
        )
    ) or 0
    if contact_count:
        options.append({"type": "contact", "name": "名片", "count": int(contact_count)})

    return {"options": options}


async def _skill_id_map(session: AsyncSession, user_id: str) -> dict[str, str]:
    rows = (
        await session.execute(
            select(UserSkill.id, UserSkill.display_name).where(
                UserSkill.user_id == user_id
            )
        )
    ).all()
    return {skill_id: display_name for skill_id, display_name in rows}


async def _rows_assets(
    session: AsyncSession, user_id: str, skill_id: str | None = None
) -> list[dict]:
    stmt = select(Asset).where(Asset.user_id == user_id)
    if skill_id:
        stmt = stmt.where(Asset.user_skill_id == skill_id)
    rows = list((await session.scalars(stmt)).all())
    return [
        {
            "kind": "asset",
            "type": "asset",
            "title": row.payload_json.get("title") or "未命名",
            "domain": row.domain or "",
            "created_at": row.created_at,
            "detail_json": json.dumps(_clean_payload(row.payload_json), ensure_ascii=False),
        }
        for row in rows
    ]


async def _rows_events(session: AsyncSession, user_id: str) -> list[dict]:
    rows = list(
        (
            await session.scalars(
                select(Event).where(Event.user_id == user_id)
            )
        ).all()
    )
    return [
        {
            "kind": "event",
            "type": "event",
            "title": row.title,
            "domain": "",
            "created_at": row.created_at,
            "detail_json": json.dumps(
                {
                    "start_at": _fmt_dt(row.start_at),
                    "end_at": _fmt_dt(row.end_at),
                    "location": row.location or "",
                    "description": row.description or "",
                },
                ensure_ascii=False,
            ),
        }
        for row in rows
    ]


async def _rows_contacts(session: AsyncSession, user_id: str) -> list[dict]:
    rows = list(
        (
            await session.scalars(
                select(Contact).where(Contact.user_id == user_id)
            )
        ).all()
    )
    return [
        {
            "kind": "contact",
            "type": "contact",
            "title": row.name,
            "domain": "",
            "created_at": row.created_at,
            "detail_json": json.dumps(
                {
                    "phone": row.phone or "",
                    "company": row.company or "",
                    "email": row.email or "",
                    "notes": row.notes_json or [],
                },
                ensure_ascii=False,
            ),
        }
        for row in rows
    ]


async def _gather_rows(
    session: AsyncSession,
    user_id: str,
    selected_types: list[str],
) -> list[dict]:
    """Gather rows for the selected export types (all if none specified)."""
    rows: list[dict] = []
    skill_ids: list[str] = []

    selected_skill_ids = {
        value.removeprefix("skill:")
        for value in selected_types
        if value.startswith("skill:") and value.removeprefix("skill:")
    }
    if selected_skill_ids or not selected_types:
        skill_map = await _skill_id_map(session, user_id)
        skill_ids = [
            skill_id
            for skill_id in skill_map
            if not selected_skill_ids or skill_id in selected_skill_ids
        ]

    for skill_id in skill_ids:
        rows.extend(await _rows_assets(session, user_id, skill_id))

    if "event" in selected_types or not selected_types:
        rows.extend(await _rows_events(session, user_id))
    if "contact" in selected_types or not selected_types:
        rows.extend(await _rows_contacts(session, user_id))

    rows.sort(key=lambda r: str(r["created_at"]), reverse=True)
    return rows


def to_markdown(rows: list[dict]) -> str:
    if not rows:
        return "没有可导出的数据。"
    lines = [
        f"# UReka 数据导出",
        f"导出时间: {datetime.now(_BEIJING).strftime('%Y-%m-%d %H:%M')}",
        "",
    ]
    asset_rows = [r for r in rows if r["kind"] == "asset"]
    event_rows = [r for r in rows if r["kind"] == "event"]
    contact_rows = [r for r in rows if r["kind"] == "contact"]

    if asset_rows:
        lines.append(f"## 记录 ({len(asset_rows)})")
        for row in asset_rows:
            lines.append(f"- **{row['title']}** ({_fmt_dt(row['created_at'])})")
            try:
                detail = json.loads(row["detail_json"])
            except (json.JSONDecodeError, TypeError):
                detail = {}
            for key, value in detail.items():
                if value not in (None, ""):
                    lines.append(f"  - {key}: {value}")
    if event_rows:
        lines.append(f"## 事件 ({len(event_rows)})")
        for row in event_rows:
            lines.append(f"- {row['title']} ({_fmt_dt(row['created_at'])})")
    if contact_rows:
        lines.append(f"## 名片 ({len(contact_rows)})")
        for row in contact_rows:
            lines.append(f"- {row['title']} ({_fmt_dt(row['created_at'])})")
    return "\n".join(lines) + "\n"


def to_csv(rows: list[dict]) -> str:
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(["kind", "type", "title", "domain", "created_at", "detail_json"])
    for row in rows:
        writer.writerow(
            [
                row["kind"],
                row["type"],
                row["title"],
                row["domain"],
                _fmt_dt(row["created_at"]),
                row["detail_json"],
            ]
        )
    return buffer.getvalue()


async def build_export(
    session: AsyncSession,
    user_id: str,
    *,
    selected_types: list[str],
    output_format: str,
) -> str:
    rows = await _gather_rows(session, user_id, selected_types)
    if output_format == "csv":
        return to_csv(rows)
    return to_markdown(rows)


def suggested_filename(output_format: str) -> str:
    today = datetime.now(_BEIJING).strftime("%Y%m%d")
    return f"ureka_export_{today}.{output_format}"
