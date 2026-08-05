import re
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.config import get_settings
from app.db.base import utc_now
from app.db.models import Asset, Event, EventAttendee, GlobalSkill, UserSkill
from app.domains.assets.schemas import (
    AssetCreate,
    AssetUpdate,
    EventCreate,
    EventUpdate,
    UserSkillCreate,
    UserSkillUpdate,
)
from app.domains.assets.indexing import rebuild_asset_fields
from app.domains.assets.validation import AssetWriteProfile, validate_asset_payload
from app.domains.triggers.service import on_asset_created
from app.domains.sessions.provenance import (
    ProvenanceNotOwned,
    validate_owned_provenance,
)


class UserSkillNotFound(Exception):
    pass


class ChatSessionNotFound(Exception):
    pass


class EventNotFound(Exception):
    pass


class ContactNotFound(Exception):
    pass


class EventAttendeeNotFound(Exception):
    pass


_LEGACY_ATTENDEE_PATTERN = re.compile(
    r"(?:和|与)(?P<name>[\u4e00-\u9fffA-Za-z0-9·]{1,40}?)"
    r"(?=一起参加|共同参加|参加|出席)(?:一起参加|共同参加|参加|出席)"
)


BASELINE_CAPTURE_SKILLS: tuple[dict, ...] = (
    {
        "machine_name": "todo",
        "display_name": "待办",
        "description": "需要完成、提醒或跟进的事项",
        "domain": "productivity",
        "schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "content": {"type": "string"},
                "due_date": {"type": "string"},
                "period": {"type": "string"},
                "occurred_at": {"type": "string"},
                "status": {"type": "string"},
                "domain": {"type": "string"},
            },
            "required": ["title"],
            "additionalProperties": False,
            "x-capture-enabled": True,
        },
    },
    {
        "machine_name": "expense",
        "display_name": "消费",
        "description": "消费、付款或报销记录",
        "domain": "finance",
        "schema": {
            "type": "object",
            "properties": {
                "amount": {"type": "number"},
                "currency": {"type": "string"},
                "category": {"type": "string"},
                "merchant": {"type": "string"},
                "date": {"type": "string"},
                "description": {"type": "string"},
                "period": {"type": "string"},
                "occurred_at": {"type": "string"},
                "domain": {"type": "string"},
            },
            "required": ["amount", "currency"],
            "additionalProperties": False,
            "x-capture-enabled": True,
        },
    },
    {
        "machine_name": "contact",
        "display_name": "联系人",
        "description": "人物及其明确提供的联系信息",
        "domain": "people",
        "schema": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "phone": {"type": "string"},
                "company": {"type": "string"},
                "title": {"type": "string"},
                "email": {"type": "string"},
                "notes": {"type": "string"},
                "domain": {"type": "string"},
            },
            "required": ["name"],
            "additionalProperties": False,
            "x-capture-enabled": True,
        },
    },
    {
        "machine_name": "notes",
        "display_name": "随记",
        "description": "无法归入结构化技能时，忠于原文保存的自由文本内容",
        "domain": "knowledge",
        "schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "content": {"type": "string"},
                "domain": {"type": "string"},
            },
            "required": ["title", "content"],
            "additionalProperties": False,
            "x-capture-enabled": True,
        },
    },
)


async def ensure_capture_skills(
    session: AsyncSession,
    user_id: str,
) -> list[UserSkill]:
    machine_names = [item["machine_name"] for item in BASELINE_CAPTURE_SKILLS]
    existing = list(
        await session.scalars(
            select(UserSkill).where(
                UserSkill.user_id == user_id,
                UserSkill.machine_name.in_(machine_names),
            )
        )
    )
    by_name = {skill.machine_name: skill for skill in existing}
    global_skills = {
        skill.machine_name: skill
        for skill in await session.scalars(
            select(GlobalSkill).where(GlobalSkill.machine_name.in_(machine_names))
        )
    }
    for definition in BASELINE_CAPTURE_SKILLS:
        machine_name = definition["machine_name"]
        if machine_name in by_name:
            if by_name[machine_name].global_skill_id is None:
                global_skill = global_skills.get(machine_name)
                if global_skill is not None:
                    by_name[machine_name].global_skill_id = global_skill.id
            continue
        skill = UserSkill(
            user_id=user_id,
            global_skill_id=(
                global_skills[machine_name].id
                if machine_name in global_skills
                else None
            ),
            machine_name=machine_name,
            display_name=definition["display_name"],
            description=definition["description"],
            domain=definition["domain"],
            schema_json=definition["schema"],
            queryable_fields_json=list(
                (definition["schema"].get("properties") or {}).keys()
            ),
        )
        session.add(skill)
        by_name[machine_name] = skill
    await session.flush()
    return [by_name[machine_name] for machine_name in machine_names]


def _utc_naive(value: datetime | None) -> datetime | None:
    if value is None or value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


async def create_user_skill(
    session: AsyncSession,
    user_id: str,
    command: UserSkillCreate,
) -> UserSkill:
    global_skill = await session.scalar(
        select(GlobalSkill).where(
            GlobalSkill.machine_name == command.machine_name,
            GlobalSkill.system_enabled.is_(True),
        )
    )
    skill = UserSkill(
        user_id=user_id,
        global_skill_id=global_skill.id if global_skill is not None else None,
        machine_name=command.machine_name,
        display_name=command.display_name,
        description=command.description,
        domain=command.domain,
        schema_json=command.schema_definition,
        render_spec_json=command.render_spec,
        chat_starters_json=command.chat_starters,
        queryable_fields_json=command.queryable_fields,
        position=command.position,
        enabled=command.enabled,
    )
    session.add(skill)
    await session.flush()
    return skill


async def list_user_skills(
    session: AsyncSession,
    user_id: str,
) -> list[UserSkill]:
    result = await session.scalars(
        select(UserSkill)
        .where(UserSkill.user_id == user_id)
        .order_by(UserSkill.created_at.desc(), UserSkill.id.desc())
    )
    return list(result)


async def get_user_skill(
    session: AsyncSession,
    user_id: str,
    skill_id: str,
) -> UserSkill | None:
    return await session.scalar(
        select(UserSkill).where(
            UserSkill.id == skill_id,
            UserSkill.user_id == user_id,
        )
    )


async def update_user_skill(
    session: AsyncSession,
    user_id: str,
    skill_id: str,
    command: UserSkillUpdate,
) -> UserSkill | None:
    skill = await get_user_skill(session, user_id, skill_id)
    if skill is None:
        return None
    for field in ("display_name", "description", "domain"):
        if field in command.model_fields_set:
            setattr(skill, field, getattr(command, field))
    if (
        "schema_definition" in command.model_fields_set
        and command.schema_definition is not None
    ):
        skill.schema_json = command.schema_definition
    if "render_spec" in command.model_fields_set and command.render_spec is not None:
        skill.render_spec_json = command.render_spec
    if "chat_starters" in command.model_fields_set and command.chat_starters is not None:
        skill.chat_starters_json = command.chat_starters
    if (
        "queryable_fields" in command.model_fields_set
        and command.queryable_fields is not None
    ):
        skill.queryable_fields_json = command.queryable_fields
    if "position" in command.model_fields_set and command.position is not None:
        skill.position = command.position
    if "enabled" in command.model_fields_set and command.enabled is not None:
        skill.enabled = command.enabled
    skill.updated_at = utc_now()
    await session.flush()
    return skill


async def list_recent_manual_skill_names(
    session: AsyncSession,
    user_id: str,
    *,
    limit: int = 4,
) -> list[str]:
    rows = (
        await session.execute(
            select(UserSkill.machine_name, Asset.created_at)
            .join(Asset, Asset.user_skill_id == UserSkill.id)
            .where(UserSkill.user_id == user_id, Asset.user_id == user_id)
            .order_by(Asset.created_at.desc(), Asset.id.desc())
            .limit(100)
        )
    ).all()
    names = []
    seen = set()
    for name, _ in rows:
        if name in seen:
            continue
        seen.add(name)
        names.append(name)
        if len(names) == limit:
            break
    return names


async def create_asset(
    session: AsyncSession,
    user_id: str,
    command: AssetCreate,
    *,
    write_profile: AssetWriteProfile = AssetWriteProfile.manual,
) -> Asset:
    skill = await session.scalar(
        select(UserSkill).where(
            UserSkill.id == command.user_skill_id,
            UserSkill.user_id == user_id,
        )
    )
    if skill is None:
        raise UserSkillNotFound()
    validate_asset_payload(
        command.payload,
        skill.schema_json,
        profile=write_profile,
    )

    try:
        provenance = await validate_owned_provenance(
            session,
            user_id,
            session_id=command.session_id,
            input_turn_id=command.source_input_turn_id,
        )
    except ProvenanceNotOwned as exc:
        raise ChatSessionNotFound() from exc

    asset = Asset(
        user_id=user_id,
        user_skill_id=skill.id,
        payload_json=command.payload,
        domain=command.domain or skill.domain,
        effective_at=_utc_naive(command.effective_at),
        period=command.period,
        occurred_at=_utc_naive(command.occurred_at),
        session_id=provenance.session_id,
        source_input_turn_id=provenance.input_turn_id,
    )
    session.add(asset)
    await session.flush()
    await rebuild_asset_fields(session, asset=asset, skill=skill)
    await on_asset_created(
        session,
        asset=asset,
        now=utc_now(),
        timezone_name=get_settings().default_user_timezone,
    )
    return asset


async def get_asset(
    session: AsyncSession,
    user_id: str,
    asset_id: str,
) -> Asset | None:
    asset = await session.scalar(
        select(Asset).where(Asset.id == asset_id, Asset.user_id == user_id)
    )
    if asset is not None:
        await attach_report_sources(session, user_id, [asset])
        await _attach_capture_source(session, user_id, "asset", asset.id, asset)
    return asset


async def list_assets(
    session: AsyncSession,
    user_id: str,
    *,
    user_skill_id: str | None = None,
    created_from: datetime | None = None,
    created_to: datetime | None = None,
    limit: int = 50,
) -> list[Asset]:
    query = select(Asset).where(Asset.user_id == user_id)
    if user_skill_id is not None:
        query = query.where(Asset.user_skill_id == user_skill_id)
    if created_from is not None:
        query = query.where(Asset.created_at >= _utc_naive(created_from))
    if created_to is not None:
        query = query.where(Asset.created_at < _utc_naive(created_to))
    result = await session.scalars(
        query.order_by(Asset.created_at.desc(), Asset.id.desc()).limit(limit)
    )
    assets = list(result)
    await attach_report_sources(session, user_id, assets)
    return assets


async def attach_report_sources(
    session: AsyncSession,
    user_id: str,
    assets: list[Asset],
) -> None:
    from app.domains.reports.models import Report

    report_ids = {
        asset.source_report_id for asset in assets if asset.source_report_id
    }
    titles: dict[str, str] = {}
    if report_ids:
        rows = await session.execute(
            select(Report.id, Report.title).where(
                Report.user_id == user_id,
                Report.id.in_(report_ids),
            )
        )
        titles = dict(rows.all())
    for asset in assets:
        asset.source_report_title = titles.get(asset.source_report_id)


async def update_asset(
    session: AsyncSession,
    user_id: str,
    asset_id: str,
    command: AssetUpdate,
    *,
    write_profile: AssetWriteProfile = AssetWriteProfile.manual,
) -> Asset | None:
    asset = await get_asset(session, user_id, asset_id)
    if asset is None:
        return None
    if "payload" in command.model_fields_set and command.payload is not None:
        skill = await session.get(UserSkill, asset.user_skill_id)
        if skill is None:
            raise UserSkillNotFound()
        validate_asset_payload(
            command.payload,
            skill.schema_json,
            profile=write_profile,
        )
        asset.payload_json = command.payload
        await rebuild_asset_fields(session, asset=asset, skill=skill)
    if "effective_at" in command.model_fields_set:
        asset.effective_at = _utc_naive(command.effective_at)
    if "period" in command.model_fields_set:
        asset.period = command.period
    if "occurred_at" in command.model_fields_set:
        asset.occurred_at = _utc_naive(command.occurred_at)
    if "domain" in command.model_fields_set:
        asset.domain = command.domain
    asset.updated_at = utc_now()
    await session.flush()
    return asset


async def delete_asset(
    session: AsyncSession,
    user_id: str,
    asset_id: str,
) -> bool:
    asset = await get_asset(session, user_id, asset_id)
    if asset is None:
        return False
    await session.delete(asset)
    await session.flush()
    return True


async def create_event(
    session: AsyncSession,
    user_id: str,
    command: EventCreate,
) -> Event:
    provenance = await validate_owned_provenance(
        session,
        user_id,
        session_id=None,
        input_turn_id=command.source_input_turn_id,
    )
    event = Event(
        user_id=user_id,
        title=command.title,
        description=command.description,
        location=command.location,
        start_at=_utc_naive(command.start_at),
        end_at=_utc_naive(command.end_at),
        all_day=command.all_day,
        status=command.status,
        recurrence_rule=command.recurrence_rule,
        source_input_turn_id=provenance.input_turn_id,
    )
    event.attendees = []
    for attendee in command.attendees:
        if not attendee.name.strip() and not attendee.contact_id:
            continue
        resolved_contact = await _resolve_attendee_contact(
            session,
            user_id,
            name=attendee.name,
            contact_id=attendee.contact_id,
        )
        if attendee.contact_id and resolved_contact is None:
            raise ContactNotFound()
        event.attendees.append(
            EventAttendee(
                contact_id=resolved_contact.id if resolved_contact else None,
                name_raw=attendee.name.strip()
                or (resolved_contact.name if resolved_contact else ""),
                role=attendee.role,
            )
        )
    session.add(event)
    await session.flush()
    _decorate_event(event)
    return event


async def get_event(
    session: AsyncSession,
    user_id: str,
    event_id: str,
) -> Event | None:
    event = await session.scalar(
        select(Event)
        .options(selectinload(Event.attendees))
        .where(Event.id == event_id, Event.user_id == user_id)
    )
    if event is not None:
        _decorate_event(event)
        await _attach_capture_source(session, user_id, "event", event.id, event)
    return event


async def list_events(
    session: AsyncSession,
    user_id: str,
    *,
    start_from: datetime | None = None,
    start_to: datetime | None = None,
    created_from: datetime | None = None,
    created_to: datetime | None = None,
    limit: int = 50,
) -> list[Event]:
    query = (
        select(Event)
        .options(selectinload(Event.attendees))
        .where(Event.user_id == user_id)
    )
    if start_from is not None:
        query = query.where(Event.start_at >= _utc_naive(start_from))
    if start_to is not None:
        query = query.where(Event.start_at < _utc_naive(start_to))
    if created_from is not None:
        query = query.where(Event.created_at >= _utc_naive(created_from))
    if created_to is not None:
        query = query.where(Event.created_at < _utc_naive(created_to))
    result = await session.scalars(
        query.order_by(Event.start_at, Event.created_at, Event.id).limit(limit)
    )
    events = list(result)
    for event in events:
        _decorate_event(event)
    return events


async def update_event(
    session: AsyncSession,
    user_id: str,
    event_id: str,
    command: EventUpdate,
) -> Event | None:
    event = await get_event(session, user_id, event_id)
    if event is None:
        return None
    for field in (
        "title",
        "description",
        "location",
        "all_day",
        "status",
        "recurrence_rule",
    ):
        if field in command.model_fields_set:
            setattr(event, field, getattr(command, field))
    if "start_at" in command.model_fields_set and command.start_at is not None:
        event.start_at = _utc_naive(command.start_at)
    if "end_at" in command.model_fields_set and command.end_at is not None:
        event.end_at = _utc_naive(command.end_at)
    if "attendees" in command.model_fields_set and command.attendees is not None:
        event.attendees = []
        for attendee in command.attendees:
            if not attendee.name.strip() and not attendee.contact_id:
                continue
            resolved_contact = await _resolve_attendee_contact(
                session,
                user_id,
                name=attendee.name,
                contact_id=attendee.contact_id,
            )
            if attendee.contact_id and resolved_contact is None:
                raise ContactNotFound()
            event.attendees.append(
                EventAttendee(
                    contact_id=resolved_contact.id if resolved_contact else None,
                    name_raw=attendee.name.strip()
                    or (resolved_contact.name if resolved_contact else ""),
                    role=attendee.role,
                )
            )
    event.updated_at = utc_now()
    await session.flush()
    _decorate_event(event)
    return event


async def delete_event(
    session: AsyncSession,
    user_id: str,
    event_id: str,
) -> bool:
    event = await get_event(session, user_id, event_id)
    if event is None:
        return False
    await session.delete(event)
    await session.flush()
    return True


async def add_event_attendee(
    session: AsyncSession,
    user_id: str,
    event_id: str,
    *,
    name: str = "",
    contact_id: str | None = None,
    role: str = "attendee",
) -> EventAttendee:
    event = await get_event(session, user_id, event_id)
    if event is None:
        raise EventNotFound()
    contact = await _resolve_attendee_contact(
        session,
        user_id,
        name=name,
        contact_id=contact_id,
    )
    if contact_id and contact is None:
        raise ContactNotFound()
    display_name = name.strip() or (contact.name if contact is not None else "")
    if not display_name:
        raise ValueError("attendee requires a contact or display name")
    attendee = EventAttendee(
        event_id=event.id,
        contact_id=contact.id if contact is not None else None,
        name_raw=display_name,
        role=role.strip() or "attendee",
    )
    session.add(attendee)
    await session.flush()
    return attendee


async def update_event_attendee(
    session: AsyncSession,
    user_id: str,
    event_id: str,
    attendee_id: str,
    *,
    name: str | None = None,
    contact_id: str | None = None,
    role: str | None = None,
) -> EventAttendee:
    event = await get_event(session, user_id, event_id)
    if event is None:
        raise EventNotFound()
    attendee = await session.scalar(
        select(EventAttendee).where(
            EventAttendee.id == attendee_id,
            EventAttendee.event_id == event.id,
        )
    )
    if attendee is None:
        raise EventAttendeeNotFound()
    contact = None
    if contact_id is not None and contact_id.strip():
        contact = await _resolve_attendee_contact(
            session,
            user_id,
            name=name or attendee.name_raw,
            contact_id=contact_id,
        )
        if contact is None:
            raise ContactNotFound()
        attendee.contact_id = contact.id
    elif contact_id is not None:
        attendee.contact_id = None
    if name is not None:
        attendee.name_raw = name.strip() or (
            contact.name if contact is not None else attendee.name_raw
        )
    if role is not None:
        attendee.role = role.strip() or attendee.role
    if not attendee.name_raw.strip() and attendee.contact_id is None:
        raise ValueError("attendee requires a contact or display name")
    attendee.updated_at = utc_now()
    await session.flush()
    return attendee


async def delete_event_attendee(
    session: AsyncSession,
    user_id: str,
    event_id: str,
    attendee_id: str,
) -> EventAttendee:
    event = await get_event(session, user_id, event_id)
    if event is None:
        raise EventNotFound()
    attendee = await session.scalar(
        select(EventAttendee).where(
            EventAttendee.id == attendee_id,
            EventAttendee.event_id == event.id,
        )
    )
    if attendee is None:
        raise EventAttendeeNotFound()
    await session.delete(attendee)
    await session.flush()
    return attendee


def _decorate_event(event: Event) -> None:
    description = event.description or ""
    legacy_names = [
        match.group("name").strip()
        for match in _LEGACY_ATTENDEE_PATTERN.finditer(description)
        if match.group("name").strip()
    ]
    event.display_description = (
        _LEGACY_ATTENDEE_PATTERN.sub("", description).strip(" ，,。；;") or None
    )
    persisted = [
        {
            "id": attendee.id,
            "contact_id": attendee.contact_id,
            "name_raw": attendee.name_raw,
            "display_name": attendee.name_raw,
            "is_resolved": attendee.contact_id is not None,
            "contact_summary": "",
            "role": attendee.role,
        }
        for attendee in event.attendees
        if attendee.name_raw.strip()
    ]
    if not persisted:
        persisted = [
            {
                "id": None,
                "contact_id": None,
                "name_raw": name,
                "display_name": name,
                "is_resolved": False,
                "contact_summary": "",
                "role": "attendee",
            }
            for name in dict.fromkeys(legacy_names)
        ]
    event.attendee_payload = persisted


async def _resolve_attendee_contact(
    session: AsyncSession,
    user_id: str,
    *,
    name: str,
    contact_id: str | None,
):
    from app.db.models import Contact
    from app.domains.contacts.service import normalize_contact_name

    if contact_id:
        return await session.scalar(
            select(Contact).where(Contact.id == contact_id, Contact.user_id == user_id)
        )
    normalized = normalize_contact_name(name)
    if not normalized:
        return None
    contacts = list(
        await session.scalars(select(Contact).where(Contact.user_id == user_id))
    )
    exact = [
        contact
        for contact in contacts
        if normalize_contact_name(contact.name) == normalized
    ]
    return exact[0] if len(exact) == 1 else None


async def _attach_capture_source(
    session: AsyncSession,
    user_id: str,
    kind: str,
    record_id: str,
    record: Asset | Event,
) -> None:
    from app.domains.capture.models import CaptureRecording, CaptureTurn

    rows = await session.execute(
        select(CaptureRecording, CaptureTurn)
        .outerjoin(CaptureTurn, CaptureTurn.recording_id == CaptureRecording.id)
        .where(CaptureRecording.user_id == user_id)
        .order_by(CaptureRecording.created_at.desc())
        .limit(500)
    )
    id_key = "asset_id" if kind == "asset" else "event_id"
    for recording, turn in rows.all():
        references = recording.result_records_json or []
        if any(
            isinstance(reference, dict)
            and reference.get("kind") == kind
            and str(reference.get(id_key) or "") == record_id
            for reference in references
        ):
            record.source_recording_id = recording.id
            record.source_input_turn_id = (
                recording.input_turn_id
                or (turn.id if turn is not None else None)
            )
            return
    record.source_recording_id = None
    record.source_input_turn_id = None
