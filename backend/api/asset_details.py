"""Canonical detail envelope for every entity rendered as an Asset Detail."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
import uuid

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select

from api.assets import _resync_asset_fields
from core.auth import get_current_user_id
from core.contacts_meta import clean_socials, notes_to_list
from db.database import AsyncSessionLocal
from mcp_server.tools import _event_attendee_to_dict
from db.models import (
    Asset,
    Contact,
    Event,
    EventAttendee,
    GlobalSkill,
    InputTurn,
    Session,
    UserSkill,
)

router = APIRouter()


class AssetDetailUpdate(BaseModel):
    expected_version: str
    values_patch: dict[str, Any] = Field(default_factory=dict)


_EVENT_FIELDS = (
    ("title", "标题", "string", True, False),
    ("start_at", "开始", "datetime", True, False),
    ("end_at", "结束", "datetime", False, False),
    ("all_day", "全天", "boolean", False, False),
    ("location", "地点", "string", False, False),
    ("description", "描述", "string", False, True),
    ("recurrence_rule", "重复", "string", False, False),
    ("status", "状态", "string", False, False),
    ("attendees", "参会人", "array", False, False),
)

_CONTACT_FIELDS = (
    ("name", "姓名", "string", True, False),
    ("company", "公司", "string", False, False),
    ("title", "职位", "string", False, False),
    ("phone", "电话", "string", False, False),
    ("email", "邮箱", "string", False, False),
    ("socials", "社交账号", "object", False, False),
    ("notes", "备注", "string", False, True),
)


def _iso(value: Any) -> str | None:
    return value.isoformat() if value is not None else None


def _version(entity: Asset | Event | Contact) -> str:
    return _iso(entity.updated_at or entity.created_at) or ""


def _assert_version(
    entity: Asset | Event | Contact,
    expected_version: str,
) -> None:
    if expected_version != _version(entity):
        raise HTTPException(status_code=409, detail="stale asset detail version")


def _assert_known_fields(values_patch: dict, allowed: set[str]) -> None:
    unknown = sorted(set(values_patch) - allowed)
    if unknown:
        raise HTTPException(
            status_code=400,
            detail=f"unknown asset detail fields: {', '.join(unknown)}",
        )


def _parse_datetime(value: Any, field_id: str) -> datetime | None:
    if value is None or value == "":
        return None
    if not isinstance(value, str):
        raise HTTPException(status_code=400, detail=f"{field_id} must be ISO8601")
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise HTTPException(
            status_code=400,
            detail=f"{field_id} must be ISO8601",
        ) from error


def _field_rows(schema: dict | None) -> list[dict]:
    rows: list[tuple[int, int, dict]] = []
    for fallback_order, (field_id, raw) in enumerate((schema or {}).items()):
        meta = dict(raw) if isinstance(raw, dict) else {}
        order = meta.get("order")
        resolved_order = order if isinstance(order, int) else fallback_order
        rows.append(
            (
                resolved_order,
                fallback_order,
                {
                    "id": field_id,
                    "label": str(meta.get("label") or field_id),
                    "type": str(meta.get("type") or "string"),
                    "required": bool(meta.get("required")),
                    "long": bool(meta.get("long")),
                    "order": resolved_order,
                },
            )
        )
    rows.sort(key=lambda row: (row[0], row[1]))
    return [row[2] for row in rows]


def _static_fields(definitions: tuple[tuple[str, str, str, bool, bool], ...]) -> list[dict]:
    return [
        {
            "id": field_id,
            "label": label,
            "type": field_type,
            "required": required,
            "long": long,
            "order": order,
        }
        for order, (field_id, label, field_type, required, long) in enumerate(
            definitions
        )
    ]


def _display(
    render_spec: dict | None,
    *,
    primary: str,
    secondary: list[str],
) -> dict:
    spec = dict(render_spec or {})
    raw = spec.get("card_display")
    card_display = dict(raw) if isinstance(raw, dict) else {}
    primary_id = str(card_display.get("primary_field_id") or primary)
    secondary_ids = card_display.get("secondary_field_ids")
    if not isinstance(secondary_ids, list):
        secondary_ids = secondary
    return {
        "primary_field_id": primary_id,
        "secondary_field_ids": [
            str(field_id) for field_id in secondary_ids if str(field_id).strip()
        ][:3],
    }


async def _event_attendees(
    db,
    event_id: uuid.UUID,
    user_id: str,
) -> list[dict]:
    attendees = (
        await db.execute(
            select(EventAttendee)
            .where(EventAttendee.event_id == event_id)
            .order_by(EventAttendee.created_at.asc(), EventAttendee.id.asc())
        )
    ).scalars().all()
    contact_ids = {
        attendee.contact_id for attendee in attendees if attendee.contact_id
    }
    contacts_by_id = {}
    if contact_ids:
        contacts = (
            await db.execute(
                select(Contact).where(
                    Contact.id.in_(contact_ids),
                    Contact.user_id == user_id,
                )
            )
        ).scalars().all()
        contacts_by_id = {contact.id: contact for contact in contacts}
    return [
        _event_attendee_to_dict(
            attendee,
            contacts_by_id.get(attendee.contact_id),
        )
        for attendee in attendees
    ]


async def _source(db, user_id: str, turn_id: uuid.UUID | None) -> dict:
    if turn_id is None:
        return {
            "kind": "manual",
            "label": "手动创建",
            "session_id": None,
            "input_turn_id": None,
        }
    row = (
        await db.execute(
            select(InputTurn, Session)
            .join(Session, Session.id == InputTurn.session_id)
            .where(InputTurn.id == turn_id, InputTurn.user_id == user_id)
        )
    ).first()
    if row is None:
        return {
            "kind": "manual",
            "label": "来源不可用",
            "session_id": None,
            "input_turn_id": None,
        }
    turn, session = row
    is_flash = session.session_type == "flash"
    return {
        "kind": "flash" if is_flash else "session",
        "label": "来自闪念" if is_flash else "来自会话",
        "session_id": str(session.id),
        "input_turn_id": str(turn.id),
    }


def _envelope(
    *,
    kind: str,
    entity_id: uuid.UUID,
    version: str,
    skill: dict,
    fields: list[dict],
    values: dict,
    display: dict,
    source: dict,
) -> dict:
    return {
        "entity": {
            "kind": kind,
            "id": str(entity_id),
            "version": version,
        },
        "skill": skill,
        "fields": fields,
        "values": values,
        "display": display,
        "source": source,
        "capabilities": {
            "editable": True,
            "deletable": True,
        },
    }


@router.get("/asset-details/{kind}/{entity_id}")
async def get_asset_detail(
    kind: str,
    entity_id: str,
    user_id: str = Depends(get_current_user_id),
):
    if kind not in {"asset", "event", "contact"}:
        raise HTTPException(status_code=400, detail="unsupported asset detail kind")
    try:
        resolved_id = uuid.UUID(entity_id)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="invalid asset detail id") from error

    async with AsyncSessionLocal() as db:
        if kind == "asset":
            row = (
                await db.execute(
                    select(Asset, UserSkill, GlobalSkill)
                    .join(UserSkill, UserSkill.id == Asset.user_skill_id)
                    .join(GlobalSkill, GlobalSkill.id == UserSkill.skill_id)
                    .where(Asset.id == resolved_id, Asset.user_id == user_id)
                )
            ).first()
            if row is None:
                raise HTTPException(status_code=404, detail="asset not found")
            asset, user_skill, global_skill = row
            render_spec = dict(user_skill.render_spec or {})
            fields = _field_rows(user_skill.payload_schema)
            primary = fields[0]["id"] if fields else "content"
            return _envelope(
                kind=kind,
                entity_id=asset.id,
                version=_version(asset),
                skill={
                    "id": str(user_skill.id),
                    "machine_name": global_skill.name,
                    "display_name": user_skill.display_name or global_skill.name,
                    "icon": str(render_spec.get("icon") or "•"),
                },
                fields=fields,
                values=dict(asset.payload or {}),
                display=_display(
                    render_spec,
                    primary=primary,
                    secondary=[],
                ),
                source=await _source(db, user_id, asset.source_input_turn_id),
            )

        if kind == "event":
            event = (
                await db.execute(
                    select(Event).where(
                        Event.id == resolved_id,
                        Event.user_id == user_id,
                    )
                )
            ).scalar_one_or_none()
            if event is None:
                raise HTTPException(status_code=404, detail="event not found")
            values = {
                "title": event.title,
                "start_at": _iso(event.start_at),
                "end_at": _iso(event.end_at),
                "all_day": bool(event.all_day),
                "location": event.location,
                "description": event.description,
                "recurrence_rule": event.recurrence_rule,
                "status": event.status,
                "attendees": await _event_attendees(db, event.id, user_id),
            }
            return _envelope(
                kind=kind,
                entity_id=event.id,
                version=_version(event),
                skill={
                    "id": None,
                    "machine_name": "event",
                    "display_name": "事件",
                    "icon": "▣",
                },
                fields=_static_fields(_EVENT_FIELDS),
                values=values,
                display=_display(
                    None,
                    primary="title",
                    secondary=["start_at", "location"],
                ),
                source=await _source(db, user_id, event.source_input_turn_id),
            )

        contact = (
            await db.execute(
                select(Contact).where(
                    Contact.id == resolved_id,
                    Contact.user_id == user_id,
                )
            )
        ).scalar_one_or_none()
        if contact is None:
            raise HTTPException(status_code=404, detail="contact not found")
        notes = notes_to_list(contact.notes)
        values = {
            "name": contact.name,
            "company": contact.company,
            "title": contact.title,
            "phone": contact.phone,
            "email": contact.email,
            "socials": clean_socials(contact.socials),
            "notes": "\n\n".join(notes),
        }
        return _envelope(
            kind=kind,
            entity_id=contact.id,
            version=_version(contact),
            skill={
                "id": None,
                "machine_name": "contact",
                "display_name": "联系人",
                "icon": "♙",
            },
            fields=_static_fields(_CONTACT_FIELDS),
            values=values,
            display=_display(
                None,
                primary="name",
                secondary=["company", "title", "phone"],
            ),
            source=await _source(db, user_id, contact.source_input_turn_id),
        )


@router.put("/asset-details/{kind}/{entity_id}")
async def update_asset_detail(
    kind: str,
    entity_id: str,
    body: AssetDetailUpdate,
    user_id: str = Depends(get_current_user_id),
):
    if kind not in {"asset", "event", "contact"}:
        raise HTTPException(status_code=400, detail="unsupported asset detail kind")
    if not body.values_patch:
        raise HTTPException(status_code=400, detail="empty values patch")
    try:
        resolved_id = uuid.UUID(entity_id)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="invalid asset detail id") from error

    async with AsyncSessionLocal() as db:
        if kind == "asset":
            row = (
                await db.execute(
                    select(Asset, UserSkill)
                    .join(UserSkill, UserSkill.id == Asset.user_skill_id)
                    .where(Asset.id == resolved_id, Asset.user_id == user_id)
                    .with_for_update()
                )
            ).first()
            if row is None:
                raise HTTPException(status_code=404, detail="asset not found")
            asset, user_skill = row
            _assert_version(asset, body.expected_version)
            schema = dict(user_skill.payload_schema or {})
            _assert_known_fields(body.values_patch, set(schema))
            values = dict(asset.payload or {})
            values.update(body.values_patch)
            missing_required = [
                field_id
                for field_id, raw in schema.items()
                if isinstance(raw, dict)
                and raw.get("required")
                and values.get(field_id) in (None, "")
            ]
            if missing_required:
                raise HTTPException(
                    status_code=400,
                    detail=f"required asset fields missing: {', '.join(missing_required)}",
                )
            asset.payload = values
            asset.updated_at = datetime.now(timezone.utc)
            await _resync_asset_fields(db, asset, values)

        elif kind == "event":
            event = (
                await db.execute(
                    select(Event)
                    .where(Event.id == resolved_id, Event.user_id == user_id)
                    .with_for_update()
                )
            ).scalar_one_or_none()
            if event is None:
                raise HTTPException(status_code=404, detail="event not found")
            _assert_version(event, body.expected_version)
            allowed = {
                field_id
                for field_id, *_ in _EVENT_FIELDS
                if field_id != "attendees"
            }
            _assert_known_fields(body.values_patch, allowed)
            for field_id, value in body.values_patch.items():
                if field_id in {"start_at", "end_at"}:
                    value = _parse_datetime(value, field_id)
                elif field_id == "all_day":
                    value = int(bool(value))
                elif field_id == "title" and not str(value or "").strip():
                    raise HTTPException(status_code=400, detail="title required")
                setattr(event, field_id, value)
            if event.start_at is None:
                raise HTTPException(status_code=400, detail="start_at required")
            event.updated_at = datetime.now(timezone.utc)

        else:
            contact = (
                await db.execute(
                    select(Contact)
                    .where(Contact.id == resolved_id, Contact.user_id == user_id)
                    .with_for_update()
                )
            ).scalar_one_or_none()
            if contact is None:
                raise HTTPException(status_code=404, detail="contact not found")
            _assert_version(contact, body.expected_version)
            allowed = {field_id for field_id, *_ in _CONTACT_FIELDS}
            _assert_known_fields(body.values_patch, allowed)
            for field_id, value in body.values_patch.items():
                if field_id == "notes":
                    if not isinstance(value, str):
                        raise HTTPException(
                            status_code=400,
                            detail="notes must be Markdown text",
                        )
                    value = [value.strip()] if value.strip() else []
                elif field_id == "socials":
                    value = clean_socials(value)
                elif field_id == "name" and not str(value or "").strip():
                    raise HTTPException(status_code=400, detail="name required")
                setattr(contact, field_id, value)
            contact.updated_at = datetime.now(timezone.utc)

        await db.commit()

    return await get_asset_detail(kind, entity_id, user_id)
