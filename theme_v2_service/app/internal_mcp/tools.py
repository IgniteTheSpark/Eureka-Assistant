from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Awaitable, Callable

from sqlalchemy import Text, or_, select
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import utc_now
from app.db.models import (
    AgentToolExecution,
    Asset,
    Contact,
    Event,
    EventAttendee,
    UserSkill,
)
from app.db.session import session_scope
from app.domains.assets import service as asset_service
from app.domains.assets.schemas import AssetCreate, AssetUpdate, EventCreate, EventUpdate
from app.domains.assets.validation import AssetPayloadInvalid, AssetWriteProfile
from app.domains.contacts import service as contact_service
from app.domains.contacts.schemas import ContactCreate
from app.domains.notifications.service import publish_domain_event
# The stdio MCP process does not import the FastAPI report routers. Register the
# Report tables explicitly so Asset.source_report_id can resolve its foreign key
# when SQLAlchemy builds an Asset INSERT inside this isolated process.
from app.domains.reports import models as _report_models  # noqa: F401
from app.domains.sessions.models import InputTurn
from app.domains.sessions.provenance import (
    ProvenanceNotOwned,
    validate_owned_provenance,
)


@dataclass(frozen=True)
class EurekaToolContext:
    user_id: str
    session_id: str | None
    input_turn_id: str | None
    idempotency_prefix: str


ToolHandler = Callable[
    [AsyncSession, dict[str, Any], EurekaToolContext], Awaitable[dict[str, Any]]
]


def _ok(**values: Any) -> dict[str, Any]:
    return {"ok": True, **values}


def _error(message: str) -> dict[str, Any]:
    return {"ok": False, "error": message}


def _json_object(value: Any, *, label: str) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError as exc:
            raise ValueError(f"invalid {label} JSON: {exc}") from exc
        if isinstance(parsed, dict):
            return parsed
    raise ValueError(f"{label} must be a JSON object")


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value is not None else None


def _parse_datetime(value: Any, *, field: str) -> datetime | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"invalid {field}: {raw}") from exc


def _bounded_limit(value: Any, default: int, maximum: int = 100) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = default
    return min(max(parsed, 1), maximum)


async def _owned_provenance(
    database: AsyncSession,
    arguments: dict[str, Any],
    context: EurekaToolContext,
):
    requested_session = str(arguments.get("session_id") or "").strip()
    requested_turn = str(arguments.get("source_input_turn_id") or "").strip()
    return await validate_owned_provenance(
        database,
        context.user_id,
        session_id=requested_session or context.session_id,
        input_turn_id=requested_turn or context.input_turn_id,
    )


def _asset_dict(asset: Asset, skill: UserSkill) -> dict[str, Any]:
    return {
        "asset_id": asset.id,
        "user_skill_name": skill.machine_name,
        "payload": asset.payload_json,
        "domain": asset.domain,
        "session_id": asset.session_id,
        "source_input_turn_id": asset.source_input_turn_id,
        "created_at": _iso(asset.created_at),
        "updated_at": _iso(asset.updated_at),
    }


def _contact_dict(contact: Contact) -> dict[str, Any]:
    return {
        "contact_id": contact.id,
        "name": contact.name,
        "phone": contact.phone,
        "company": contact.company,
        "title": contact.title,
        "email": contact.email,
        "notes": list(contact.notes_json or []),
        "socials": dict(contact.socials_json or {}),
        "session_id": contact.session_id,
        "source_input_turn_id": contact.source_input_turn_id,
        "created_at": _iso(contact.created_at),
        "updated_at": _iso(contact.updated_at),
    }


async def _event_dict(database: AsyncSession, event: Event) -> dict[str, Any]:
    attendees = list(
        await database.scalars(
            select(EventAttendee)
            .where(EventAttendee.event_id == event.id)
            .order_by(EventAttendee.created_at, EventAttendee.id)
        )
    )
    contact_ids = {item.contact_id for item in attendees if item.contact_id}
    contacts: dict[str, Contact] = {}
    if contact_ids:
        owned = list(
            await database.scalars(
                select(Contact).where(
                    Contact.id.in_(contact_ids),
                    Contact.user_id == event.user_id,
                )
            )
        )
        contacts = {item.id: item for item in owned}
    return {
        "event_id": event.id,
        "title": event.title,
        "description": event.description,
        "location": event.location,
        "start_at": _iso(event.start_at),
        "end_at": _iso(event.end_at),
        "all_day": bool(event.all_day),
        "status": event.status,
        "recurrence_rule": event.recurrence_rule,
        "source_input_turn_id": event.source_input_turn_id,
        "created_at": _iso(event.created_at),
        "updated_at": _iso(event.updated_at),
        "attendees": [
            {
                "id": attendee.id,
                "contact_id": attendee.contact_id,
                "name_raw": attendee.name_raw,
                "display_name": contacts[attendee.contact_id].name
                if attendee.contact_id in contacts
                else attendee.name_raw,
                "role": attendee.role,
                "is_resolved": attendee.contact_id in contacts,
                "contact_summary": " · ".join(
                    value
                    for value in (
                        contacts[attendee.contact_id].company,
                        contacts[attendee.contact_id].title,
                    )
                    if value
                )
                if attendee.contact_id in contacts
                else "",
            }
            for attendee in attendees
        ],
    }


async def _publish_change(
    database: AsyncSession,
    context: EurekaToolContext,
    *,
    entity_type: str,
    entity_id: str,
    operation: str,
) -> None:
    await publish_domain_event(
        database,
        event_type=f"{entity_type}.{operation}",
        aggregate_type=entity_type,
        aggregate_id=entity_id,
        user_id=context.user_id,
        payload={
            f"{entity_type}_id": entity_id,
            "operation": operation,
            "session_id": context.session_id,
            "input_turn_id": context.input_turn_id,
        },
    )


async def _create_asset(
    database: AsyncSession,
    arguments: dict[str, Any],
    context: EurekaToolContext,
) -> dict[str, Any]:
    machine_name = str(arguments.get("user_skill_name") or "").strip()
    skill = await database.scalar(
        select(UserSkill).where(
            UserSkill.user_id == context.user_id,
            UserSkill.machine_name == machine_name,
            UserSkill.enabled.is_(True),
        )
    )
    if skill is None:
        return _error(f"skill not registered for user: {machine_name}")
    try:
        payload = _json_object(arguments.get("payload") or {}, label="payload")
        provenance = await _owned_provenance(database, arguments, context)
        asset = await asset_service.create_asset(
            database,
            context.user_id,
            AssetCreate(
                user_skill_id=skill.id,
                payload=payload,
                session_id=provenance.session_id,
                source_input_turn_id=provenance.input_turn_id,
                effective_at=arguments.get("effective_at") or None,
                period=arguments.get("period") or None,
                occurred_at=arguments.get("occurred_at") or None,
                domain=str(arguments.get("domain") or "").strip() or None,
            ),
            write_profile=AssetWriteProfile.agent,
        )
    except (AssetPayloadInvalid, ProvenanceNotOwned, ValueError) as exc:
        return _error(str(exc))
    await _publish_change(
        database,
        context,
        entity_type="asset",
        entity_id=asset.id,
        operation="created",
    )
    return _ok(**_asset_dict(asset, skill))


async def _create_todo(database, arguments, context):
    title = str(arguments.get("title") or arguments.get("content") or "").strip()
    content = str(arguments.get("content") or title).strip()
    if not title:
        return _error("todo title is required")
    payload: dict[str, Any] = {"title": title, "content": content, "status": "pending"}
    due_date = str(arguments.get("due_date") or "").strip()
    if due_date:
        payload["due_date"] = due_date
    return await _create_asset(
        database,
        {**arguments, "user_skill_name": "todo", "payload": payload},
        context,
    )


async def _create_note(database, arguments, context):
    content = str(arguments.get("content") or "").strip()
    if not content:
        return _error("note content is required")
    payload: dict[str, Any] = {"content": content}
    title = str(arguments.get("title") or "").strip()
    if title:
        payload["title"] = title
    tags = arguments.get("tags") or []
    if isinstance(tags, str):
        tags = [item.strip() for item in tags.split(",") if item.strip()]
    if isinstance(tags, list) and tags:
        payload["tags"] = [str(item).strip() for item in tags if str(item).strip()][:3]
    return await _create_asset(
        database,
        {**arguments, "user_skill_name": "notes", "payload": payload},
        context,
    )


async def _query_asset(database, arguments, context):
    machine_name = str(arguments.get("user_skill_name") or "").strip()
    contains = str(arguments.get("contains") or "").strip()
    domain = str(arguments.get("domain") or "").strip()
    query = (
        select(Asset, UserSkill)
        .join(UserSkill, UserSkill.id == Asset.user_skill_id)
        .where(
            Asset.user_id == context.user_id,
            UserSkill.user_id == context.user_id,
            Asset.migrated_contact_id.is_(None),
        )
    )
    if machine_name:
        query = query.where(UserSkill.machine_name == machine_name)
    if domain:
        query = query.where(Asset.domain == domain)
    if contains:
        query = query.where(Asset.payload_json.cast(Text).contains(contains))
    try:
        from_date = _parse_datetime(arguments.get("from_date"), field="from_date")
        to_date = _parse_datetime(arguments.get("to_date"), field="to_date")
    except ValueError as exc:
        return _error(str(exc))
    if from_date is not None:
        query = query.where(Asset.created_at >= asset_service._utc_naive(from_date))
    if to_date is not None:
        query = query.where(Asset.created_at <= asset_service._utc_naive(to_date))
    rows = (
        await database.execute(
            query.order_by(Asset.created_at.desc(), Asset.id.desc()).limit(
                _bounded_limit(arguments.get("limit"), 100)
            )
        )
    ).all()
    return _ok(assets=[_asset_dict(asset, skill) for asset, skill in rows])


async def _query_digest(database, arguments, context):
    queried = await _query_asset(database, {**arguments, "limit": 500}, context)
    if not queried.get("ok"):
        return queried
    by_type: dict[str, list] = {}
    for asset in queried["assets"]:
        by_type.setdefault(asset["user_skill_name"], []).append(asset["payload"])
    event_query = select(Event).where(Event.user_id == context.user_id)
    try:
        from_date = _parse_datetime(arguments.get("from_date"), field="from_date")
        to_date = _parse_datetime(arguments.get("to_date"), field="to_date")
    except ValueError as exc:
        return _error(str(exc))
    if from_date is not None:
        event_query = event_query.where(Event.start_at >= asset_service._utc_naive(from_date))
    if to_date is not None:
        event_query = event_query.where(Event.start_at <= asset_service._utc_naive(to_date))
    events = []
    if not str(arguments.get("domain") or "").strip():
        rows = list(await database.scalars(event_query.order_by(Event.start_at)))
        events = [
            {
                "title": event.title,
                "start_at": _iso(event.start_at),
                "end_at": _iso(event.end_at),
                "location": event.location,
                "all_day": bool(event.all_day),
            }
            for event in rows
        ]
    return _ok(
        counts={name: len(values) for name, values in by_type.items()},
        by_type=by_type,
        events=events,
    )


async def _update_asset(database, arguments, context):
    asset_id = str(arguments.get("asset_id") or "").strip()
    row = (
        await database.execute(
            select(Asset, UserSkill)
            .join(UserSkill, UserSkill.id == Asset.user_skill_id)
            .where(
                Asset.id == asset_id,
                Asset.user_id == context.user_id,
                Asset.migrated_contact_id.is_(None),
            )
        )
    ).first()
    if row is None:
        return _error(f"asset not found: {asset_id}")
    asset, skill = row
    try:
        patch = _json_object(arguments.get("payload_patch") or {}, label="payload_patch")
        merged = {**(asset.payload_json or {}), **patch}
        changed = await asset_service.update_asset(
            database,
            context.user_id,
            asset.id,
            AssetUpdate(payload=merged),
            write_profile=AssetWriteProfile.agent,
        )
    except (AssetPayloadInvalid, ValueError) as exc:
        return _error(str(exc))
    assert changed is not None
    await _publish_change(
        database,
        context,
        entity_type="asset",
        entity_id=asset.id,
        operation="updated",
    )
    return _ok(**_asset_dict(changed, skill))


async def _delete_asset(database, arguments, context):
    asset_id = str(arguments.get("asset_id") or "").strip()
    if not await asset_service.delete_asset(database, context.user_id, asset_id):
        return _error(f"asset not found: {asset_id}")
    await _publish_change(
        database,
        context,
        entity_type="asset",
        entity_id=asset_id,
        operation="deleted",
    )
    return _ok(asset_id=asset_id, status="deleted")


async def _create_contact(database, arguments, context):
    name = str(arguments.get("name") or "").strip()
    if not name:
        return _error("name is required")
    try:
        provenance = await _owned_provenance(database, arguments, context)
        notes = arguments.get("notes") or []
        if isinstance(notes, str):
            notes = [notes] if notes.strip() else []
        contact = await contact_service.create_contact(
            database,
            context.user_id,
            ContactCreate(
                name=name,
                phone=str(arguments.get("phone") or "").strip() or None,
                company=str(arguments.get("company") or "").strip() or None,
                title=str(arguments.get("title") or "").strip() or None,
                email=str(arguments.get("email") or "").strip() or None,
                notes=notes,
                socials=arguments.get("socials") or {},
                session_id=provenance.session_id,
                source_input_turn_id=provenance.input_turn_id,
            ),
        )
    except (ProvenanceNotOwned, ValueError) as exc:
        return _error(str(exc))
    await _publish_change(
        database,
        context,
        entity_type="contact",
        entity_id=contact.id,
        operation="created",
    )
    return _ok(contact_action="created", **_contact_dict(contact))


async def _query_contact(database, arguments, context):
    name_query = str(arguments.get("name_query") or "").strip()
    contacts = await contact_service.list_contacts(
        database,
        context.user_id,
        name_query=name_query,
        limit=_bounded_limit(arguments.get("limit"), 50),
    )
    serialized = [_contact_dict(contact) for contact in contacts]
    normalized = contact_service.normalize_contact_name(name_query)
    exact = [
        contact
        for contact in serialized
        if normalized
        and contact_service.normalize_contact_name(contact["name"]) == normalized
    ]
    return _ok(contacts=serialized, exact_contacts=exact)


async def _update_contact(database, arguments, context):
    contact_id = str(arguments.get("contact_id") or "").strip()
    field = str(arguments.get("field") or "").strip()
    value = str(arguments.get("value") or "")
    try:
        contact = await contact_service.update_contact_field(
            database,
            context.user_id,
            contact_id,
            field=field,
            value=value,
        )
    except ValueError as exc:
        return _error(str(exc))
    if contact is None:
        return _error(f"contact not found: {contact_id}")
    await _publish_change(
        database,
        context,
        entity_type="contact",
        entity_id=contact.id,
        operation="updated",
    )
    return _ok(contact_action="updated", field=field, value=value, **_contact_dict(contact))


async def _delete_contact(database, arguments, context):
    contact_id = str(arguments.get("contact_id") or "").strip()
    contact = await contact_service.delete_contact(
        database,
        context.user_id,
        contact_id,
    )
    if contact is None:
        return _error(f"contact not found: {contact_id}")
    await _publish_change(
        database,
        context,
        entity_type="contact",
        entity_id=contact_id,
        operation="deleted",
    )
    return _ok(contact_id=contact_id, contact_action="deleted", name=contact.name)


async def _query_input_turn(database, arguments, context):
    query = select(InputTurn).where(InputTurn.user_id == context.user_id)
    contains = str(arguments.get("contains") or "").strip()
    source = str(arguments.get("source") or "").strip()
    if contains:
        query = query.where(InputTurn.text.contains(contains))
    if source:
        query = query.where(InputTurn.source == source)
    turns = list(
        await database.scalars(
            query.order_by(InputTurn.created_at.desc(), InputTurn.id.desc()).limit(
                _bounded_limit(arguments.get("limit"), 50)
            )
        )
    )
    return _ok(
        input_turns=[
            {
                "input_turn_id": turn.id,
                "session_id": turn.session_id,
                "source": turn.source,
                "snippet": turn.text[:200] + ("…" if len(turn.text) > 200 else ""),
                "full_text_len": len(turn.text),
                "file_id": turn.file_id,
                "created_at": _iso(turn.created_at),
            }
            for turn in turns
        ]
    )


async def _get_input_turn(database, arguments, context):
    turn_id = str(arguments.get("input_turn_id") or "").strip()
    turn = await database.scalar(
        select(InputTurn).where(
            InputTurn.id == turn_id,
            InputTurn.user_id == context.user_id,
        )
    )
    if turn is None:
        return _error(f"input_turn not found: {turn_id}")
    return _ok(
        input_turn_id=turn.id,
        session_id=turn.session_id,
        index=turn.turn_index,
        source=turn.source,
        text=turn.text,
        segments=turn.segments_json,
        file_id=turn.file_id,
        recording_id=turn.recording_id,
        source_file_offset=turn.source_file_offset_ms,
        asr_provider=turn.asr_provider,
        language=turn.language,
        created_at=_iso(turn.created_at),
    )


async def _create_event(database, arguments, context):
    title = str(arguments.get("title") or "").strip()
    if not title:
        return _error("title is required")
    try:
        start = _parse_datetime(arguments.get("start_at"), field="start_at")
        end = _parse_datetime(arguments.get("end_at"), field="end_at")
        all_day = bool(arguments.get("all_day", False))
        if start is None:
            return _error("start_at is required")
        if end is None:
            if not all_day:
                return _error(
                    "event missing time span: needs end_at OR all_day=1"
                )
            end = start + timedelta(days=1)
        if end <= start:
            return _error("end_at must be after start_at")
        provenance = await _owned_provenance(database, arguments, context)
        event = await asset_service.create_event(
            database,
            context.user_id,
            EventCreate(
                title=title,
                start_at=start,
                end_at=end,
                location=str(arguments.get("location") or "").strip() or None,
                description=str(arguments.get("description") or "").strip() or None,
                all_day=all_day,
                status="scheduled",
                recurrence_rule=str(arguments.get("recurrence_rule") or "").strip()
                or None,
                source_input_turn_id=provenance.input_turn_id,
            ),
        )
    except (ProvenanceNotOwned, ValueError) as exc:
        return _error(str(exc))
    await _publish_change(
        database,
        context,
        entity_type="event",
        entity_id=event.id,
        operation="created",
    )
    return _ok(**(await _event_dict(database, event)))


async def _query_event(database, arguments, context):
    query = select(Event).where(Event.user_id == context.user_id)
    contains = str(arguments.get("contains") or "").strip()
    status = str(arguments.get("status") or "").strip()
    if contains:
        keyword = f"%{contains}%"
        query = query.where(
            or_(
                Event.title.like(keyword),
                Event.location.like(keyword),
                Event.description.like(keyword),
            )
        )
    if status:
        query = query.where(Event.status == status)
    try:
        from_date = _parse_datetime(arguments.get("from_date"), field="from_date")
        to_date = _parse_datetime(arguments.get("to_date"), field="to_date")
    except ValueError as exc:
        return _error(str(exc))
    if from_date is not None:
        query = query.where(Event.start_at >= asset_service._utc_naive(from_date))
    if to_date is not None:
        query = query.where(Event.start_at <= asset_service._utc_naive(to_date))
    events = list(
        await database.scalars(
            query.order_by(Event.start_at.desc(), Event.id.desc()).limit(
                _bounded_limit(arguments.get("limit"), 50)
            )
        )
    )
    return _ok(events=[await _event_dict(database, event) for event in events])


async def _get_event(database, arguments, context):
    event_id = str(arguments.get("event_id") or "").strip()
    event = await asset_service.get_event(database, context.user_id, event_id)
    if event is None:
        return _error(f"event not found: {event_id}")
    return _ok(**(await _event_dict(database, event)))


async def _update_event(database, arguments, context):
    event_id = str(arguments.get("event_id") or "").strip()
    event = await asset_service.get_event(database, context.user_id, event_id)
    if event is None:
        return _error(f"event not found: {event_id}")
    try:
        patch = _json_object(arguments.get("patch") or {}, label="patch")
        command_values: dict[str, Any] = {}
        for key in {
            "title",
            "description",
            "location",
            "status",
            "all_day",
            "recurrence_rule",
        }:
            if key in patch:
                command_values[key] = patch[key]
        for key in {"start_at", "end_at"}:
            if key in patch:
                command_values[key] = _parse_datetime(patch[key], field=key)
        proposed_start = command_values.get("start_at") or event.start_at
        proposed_end = command_values.get("end_at") or event.end_at
        proposed_start = asset_service._utc_naive(proposed_start)
        proposed_end = asset_service._utc_naive(proposed_end)
        if proposed_end <= proposed_start:
            return _error("end_at must be after start_at")
        changed = await asset_service.update_event(
            database,
            context.user_id,
            event_id,
            EventUpdate(**command_values),
        )
    except ValueError as exc:
        return _error(str(exc))
    assert changed is not None
    await _publish_change(
        database,
        context,
        entity_type="event",
        entity_id=event_id,
        operation="updated",
    )
    return _ok(**(await _event_dict(database, changed)))


async def _delete_event(database, arguments, context):
    event_id = str(arguments.get("event_id") or "").strip()
    if not await asset_service.delete_event(database, context.user_id, event_id):
        return _error(f"event not found: {event_id}")
    await _publish_change(
        database,
        context,
        entity_type="event",
        entity_id=event_id,
        operation="deleted",
    )
    return _ok(event_id=event_id, status="deleted")


async def _add_event_attendee(database, arguments, context):
    event_id = str(arguments.get("event_id") or "").strip()
    try:
        attendee = await asset_service.add_event_attendee(
            database,
            context.user_id,
            event_id,
            name=str(arguments.get("name") or ""),
            contact_id=str(arguments.get("contact_id") or "").strip() or None,
            role=str(arguments.get("role") or "attendee"),
        )
    except asset_service.EventNotFound:
        return _error(f"event not found: {event_id}")
    except asset_service.ContactNotFound:
        return _error(f"contact not found: {arguments.get('contact_id')}")
    except ValueError as exc:
        return _error(str(exc))
    event = await asset_service.get_event(database, context.user_id, event_id)
    assert event is not None
    payload = await _event_dict(database, event)
    serialized = next(item for item in payload["attendees"] if item["id"] == attendee.id)
    await _publish_change(
        database,
        context,
        entity_type="event",
        entity_id=event_id,
        operation="attendee_added",
    )
    return _ok(event_id=event_id, attendee_id=attendee.id, attendee=serialized)


async def _update_event_attendee(database, arguments, context):
    event_id = str(arguments.get("event_id") or "").strip()
    attendee_id = str(arguments.get("attendee_id") or "").strip()
    try:
        attendee = await asset_service.update_event_attendee(
            database,
            context.user_id,
            event_id,
            attendee_id,
            name=arguments.get("name"),
            contact_id=arguments.get("contact_id"),
            role=arguments.get("role"),
        )
    except asset_service.EventNotFound:
        return _error(f"event not found: {event_id}")
    except asset_service.EventAttendeeNotFound:
        return _error(f"attendee not found: {attendee_id}")
    except asset_service.ContactNotFound:
        return _error(f"contact not found: {arguments.get('contact_id')}")
    except ValueError as exc:
        return _error(str(exc))
    event = await asset_service.get_event(database, context.user_id, event_id)
    assert event is not None
    payload = await _event_dict(database, event)
    serialized = next(item for item in payload["attendees"] if item["id"] == attendee.id)
    await _publish_change(
        database,
        context,
        entity_type="event",
        entity_id=event_id,
        operation="attendee_updated",
    )
    return _ok(event_id=event_id, attendee_id=attendee.id, attendee=serialized)


async def _delete_event_attendee(database, arguments, context):
    event_id = str(arguments.get("event_id") or "").strip()
    attendee_id = str(arguments.get("attendee_id") or "").strip()
    try:
        attendee = await asset_service.delete_event_attendee(
            database,
            context.user_id,
            event_id,
            attendee_id,
        )
    except asset_service.EventNotFound:
        return _error(f"event not found: {event_id}")
    except asset_service.EventAttendeeNotFound:
        return _error(f"attendee not found: {attendee_id}")
    await _publish_change(
        database,
        context,
        entity_type="event",
        entity_id=event_id,
        operation="attendee_deleted",
    )
    return _ok(
        event_id=event_id,
        attendee_id=attendee_id,
        status="deleted",
        attendee={
            "id": attendee.id,
            "contact_id": attendee.contact_id,
            "name_raw": attendee.name_raw,
            "display_name": attendee.name_raw,
            "role": attendee.role,
        },
    )


TOOL_HANDLERS: dict[str, ToolHandler] = {
    "tool_create_asset": _create_asset,
    "tool_create_todo": _create_todo,
    "tool_create_note": _create_note,
    "tool_query_asset": _query_asset,
    "tool_query_digest": _query_digest,
    "tool_update_asset": _update_asset,
    "tool_delete_asset": _delete_asset,
    "tool_create_contact": _create_contact,
    "tool_query_contact": _query_contact,
    "tool_update_contact": _update_contact,
    "tool_delete_contact": _delete_contact,
    "tool_query_input_turn": _query_input_turn,
    "tool_get_input_turn": _get_input_turn,
    "tool_create_event": _create_event,
    "tool_query_event": _query_event,
    "tool_get_event": _get_event,
    "tool_update_event": _update_event,
    "tool_delete_event": _delete_event,
    "tool_add_event_attendee": _add_event_attendee,
    "tool_update_event_attendee": _update_event_attendee,
    "tool_delete_event_attendee": _delete_event_attendee,
}


MUTATION_TOOLS = {
    name
    for name in TOOL_HANDLERS
    if name.startswith(("tool_create_", "tool_update_", "tool_delete_", "tool_add_"))
}


def _arguments_hash(name: str, arguments: dict[str, Any]) -> str:
    raw = json.dumps(
        {"tool": name, "arguments": arguments},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    )
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


async def _execute_mutation(
    database: AsyncSession,
    *,
    name: str,
    arguments: dict[str, Any],
    context: EurekaToolContext,
    tool_call_id: str | None,
) -> dict[str, Any]:
    try:
        provenance = await validate_owned_provenance(
            database,
            context.user_id,
            session_id=context.session_id,
            input_turn_id=context.input_turn_id,
        )
    except ProvenanceNotOwned as exc:
        return _error(str(exc))
    arguments_hash = _arguments_hash(name, arguments)
    call_key = (tool_call_id or arguments_hash[:24]).strip()
    idempotency_key = f"{context.idempotency_prefix}:{call_key}"[:255]
    execution = await database.scalar(
        select(AgentToolExecution)
        .where(
            AgentToolExecution.user_id == context.user_id,
            AgentToolExecution.idempotency_key == idempotency_key,
        )
        .with_for_update()
    )
    if execution is not None:
        if execution.tool_name != name or execution.arguments_hash != arguments_hash:
            return _error("idempotency key already used with different arguments")
        if execution.result_json is not None:
            return dict(execution.result_json)
        return _error("tool execution is already running")

    execution = AgentToolExecution(
        user_id=context.user_id,
        session_id=provenance.session_id,
        input_turn_id=provenance.input_turn_id,
        idempotency_key=idempotency_key,
        tool_name=name,
        arguments_hash=arguments_hash,
        status="running",
    )
    database.add(execution)
    await database.flush()
    result = await TOOL_HANDLERS[name](database, arguments, context)
    execution.status = "done" if result.get("ok") else "rejected"
    execution.result_json = result
    execution.error_message = None if result.get("ok") else str(result.get("error") or "")
    execution.updated_at = utc_now()
    await database.flush()
    return result


async def execute_tool(
    name: str,
    arguments: dict[str, Any] | None,
    *,
    context: EurekaToolContext,
    tool_call_id: str | None = None,
) -> dict[str, Any]:
    handler = TOOL_HANDLERS.get(name)
    if handler is None:
        return _error(f"unsupported internal MCP tool: {name}")
    sanitized = dict(arguments or {})
    sanitized.pop("user_id", None)
    attempts = 3 if name in MUTATION_TOOLS else 1
    for attempt in range(attempts):
        try:
            async with session_scope() as database:
                if name in MUTATION_TOOLS:
                    return await _execute_mutation(
                        database,
                        name=name,
                        arguments=sanitized,
                        context=context,
                        tool_call_id=tool_call_id,
                    )
                return await handler(database, sanitized, context)
        except OperationalError as exc:
            error_code = exc.orig.args[0] if getattr(exc, "orig", None) else None
            if attempt + 1 == attempts or error_code not in {1205, 1213}:
                raise
        except IntegrityError as exc:
            is_idempotency_race = (
                getattr(exc, "orig", None)
                and exc.orig.args[0] == 1062
                and "uq_agent_tool_executions_user_key" in str(exc)
            )
            if attempt + 1 == attempts or not is_idempotency_race:
                raise
    raise RuntimeError("unreachable internal MCP retry state")
