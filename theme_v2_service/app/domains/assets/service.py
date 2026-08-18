import hashlib
import re
from copy import deepcopy
from datetime import datetime, timezone

from sqlalchemy import func, select, text
from sqlalchemy.dialects.mysql import insert as mysql_insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.config import get_settings
from app.db.base import new_uuid, utc_now
from app.db.models import Asset, Event, EventAttendee, GlobalSkill, UserSkill
from app.domains.assets.schemas import (
    AssetCreate,
    AssetUpdate,
    EventCreate,
    EventUpdate,
    SkillDeletionImpact,
    SkillDeletionResult,
    UserSkillCreate,
    UserSkillUpdate,
)
from app.domains.assets.skill_schema import (
    SkillUpdateConflict,
    is_system_skill,
    normalized_custom_skill_schema,
    validate_custom_skill_create_schema,
    validate_custom_skill_update,
)
from app.domains.assets.persistence import persist_asset
from app.domains.assets.indexing import rebuild_asset_fields
from app.domains.assets.todo_deadline import (
    normalize_new_todo_payload,
    normalize_todo_reminder_preferences,
)
from app.domains.assets.validation import AssetWriteProfile, validate_asset_payload
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
                "title": {"type": "string", "title": "标题"},
                "content": {"type": "string", "title": "内容"},
                "due_date": {"type": "string", "title": "截止时间"},
                "period": {"type": "string", "title": "时段"},
                "occurred_at": {"type": "string", "title": "发生时间"},
                "status": {"type": "string", "title": "完成状态"},
                "reminder_offsets_minutes": {
                    "type": "array",
                    "items": {"type": "integer"},
                    "title": "提醒",
                },
                "domain": {"type": "string", "title": "领域"},
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
                "amount": {"type": "number", "title": "金额"},
                "currency": {"type": "string", "title": "币种"},
                "category": {"type": "string", "title": "类别"},
                "merchant": {"type": "string", "title": "商户"},
                "date": {"type": "string", "title": "日期"},
                "description": {"type": "string", "title": "备注"},
                "period": {"type": "string", "title": "时段"},
                "occurred_at": {"type": "string", "title": "发生时间"},
                "domain": {"type": "string", "title": "领域"},
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
                "name": {"type": "string", "title": "姓名"},
                "phone": {"type": "string", "title": "电话"},
                "company": {"type": "string", "title": "公司"},
                "title": {"type": "string", "title": "职位"},
                "email": {"type": "string", "title": "邮箱"},
                "notes": {"type": "string", "title": "备注"},
                "domain": {"type": "string", "title": "领域"},
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
                "title": {"type": "string", "title": "标题"},
                "content": {"type": "string", "title": "内容"},
                "domain": {"type": "string", "title": "领域"},
            },
            "required": ["title", "content"],
            "additionalProperties": False,
            "x-capture-enabled": True,
        },
    },
    {
        "machine_name": "event",
        "display_name": "事件",
        "description": "具有开始和结束时间的日程事件",
        "domain": "productivity",
        "schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "title": "标题"},
                "start_at": {
                    "type": "string",
                    "format": "date-time",
                    "title": "开始时间",
                },
                "end_at": {
                    "type": "string",
                    "format": "date-time",
                    "title": "结束时间",
                },
                "location": {"type": "string", "title": "地点"},
                "attendees": {
                    "type": "array",
                    "items": {"type": "string"},
                    "title": "参与人",
                },
                "description": {
                    "type": "string",
                    "title": "备注",
                    "x-long": True,
                },
            },
            "required": ["title", "start_at", "end_at"],
            "additionalProperties": False,
            "x-capture-enabled": True,
        },
    },
)


def _merge_baseline_schema(current: dict | None, baseline: dict) -> dict:
    if not current:
        return deepcopy(baseline)
    current_schema = dict(current or {})
    baseline_properties = baseline.get("properties") or {}
    raw_properties = current_schema.get("properties")
    if isinstance(raw_properties, dict):
        current_properties = dict(raw_properties)
        for field in set(current_properties).intersection(baseline_properties):
            existing_metadata = current_properties[field]
            if not isinstance(existing_metadata, dict):
                continue
            current_properties[field] = {
                **dict(baseline_properties[field]),
                **dict(existing_metadata),
            }
        current_schema["properties"] = current_properties
        return current_schema

    for field in set(current_schema).intersection(baseline_properties):
        existing_metadata = current_schema[field]
        if not isinstance(existing_metadata, dict):
            continue
        current_schema[field] = {
            **dict(baseline_properties[field]),
            **dict(existing_metadata),
        }
    return current_schema


async def ensure_capture_skills(
    session: AsyncSession,
    user_id: str,
) -> list[UserSkill]:
    """Provision baseline Skills once per user without first-use races."""
    digest = hashlib.sha256(user_id.encode("utf-8")).hexdigest()[:32]
    lock_name = f"eureka:baseline:{digest}"
    acquired = await session.scalar(
        text("SELECT GET_LOCK(:lock_name, 5)"),
        {"lock_name": lock_name},
    )
    if acquired != 1:
        raise TimeoutError("baseline skill provisioning lock timed out")
    try:
        return await _ensure_capture_skills_locked(session, user_id)
    finally:
        await session.scalar(
            text("SELECT RELEASE_LOCK(:lock_name)"),
            {"lock_name": lock_name},
        )


async def _ensure_capture_skills_locked(
    session: AsyncSession,
    user_id: str,
) -> list[UserSkill]:
    machine_names = [item["machine_name"] for item in BASELINE_CAPTURE_SKILLS]
    global_skills = {
        skill.machine_name: skill
        for skill in await session.scalars(
            select(GlobalSkill).where(GlobalSkill.machine_name.in_(machine_names))
        )
    }
    now = utc_now()
    rows = []
    for definition in BASELINE_CAPTURE_SKILLS:
        machine_name = definition["machine_name"]
        rows.append(
            {
                "id": new_uuid(),
                "user_id": user_id,
                "global_skill_id": (
                    global_skills[machine_name].id
                    if machine_name in global_skills
                    else None
                ),
                "machine_name": machine_name,
                "display_name": definition["display_name"],
                "description": definition["description"],
                "domain": definition["domain"],
                "schema_json": deepcopy(definition["schema"]),
                "render_spec_json": {},
                "chat_starters_json": [],
                "queryable_fields_json": list(
                    (definition["schema"].get("properties") or {}).keys()
                ),
                "position": 0,
                "enabled": True,
                "created_at": now,
                "updated_at": now,
            }
        )

    # Match the unique-index key order so concurrent first-use transactions
    # acquire row/gap locks in the same deterministic sequence.
    rows.sort(key=lambda item: str(item["machine_name"]))
    statement = mysql_insert(UserSkill).values(rows)
    await session.execute(statement.on_duplicate_key_update(id=UserSkill.id))
    existing = list(
        await session.scalars(
            select(UserSkill).where(
                UserSkill.user_id == user_id,
                UserSkill.machine_name.in_(machine_names),
            ).with_for_update()
        )
    )
    by_name = {skill.machine_name: skill for skill in existing}
    for definition in BASELINE_CAPTURE_SKILLS:
        machine_name = definition["machine_name"]
        existing_skill = by_name[machine_name]
        if existing_skill.global_skill_id is None:
            global_skill = global_skills.get(machine_name)
            if global_skill is not None:
                existing_skill.global_skill_id = global_skill.id
        merged_schema = _merge_baseline_schema(
            existing_skill.schema_json,
            definition["schema"],
        )
        if merged_schema != existing_skill.schema_json:
            existing_skill.schema_json = merged_schema
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
    validate_custom_skill_create_schema(command.schema_definition)
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
    await ensure_capture_skills(session, user_id)
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
    # Serialize revision validation with the write so two stale writers cannot
    # both pass the optimistic-concurrency check.
    skill = await session.scalar(
        select(UserSkill)
        .where(UserSkill.id == skill_id, UserSkill.user_id == user_id)
        .with_for_update()
    )
    if skill is None:
        return None
    validate_custom_skill_update(skill, command)
    for field in ("display_name", "description", "domain"):
        if field in command.model_fields_set:
            setattr(skill, field, getattr(command, field))
    if (
        "schema_definition" in command.model_fields_set
        and command.schema_definition is not None
    ):
        skill.schema_json = normalized_custom_skill_schema(command.schema_definition)
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


def _require_custom_skill(skill: UserSkill) -> None:
    if is_system_skill(skill):
        raise SkillUpdateConflict(
            "system_skill_protected",
            "系统 Skill 不能删除",
        )


def _deletion_confirmation_token(skill: UserSkill, asset_count: int) -> str:
    updated_at = _utc_naive(getattr(skill, "updated_at", None))
    revision = updated_at.isoformat(timespec="microseconds") if updated_at else ""
    payload = f"{skill.id}:{revision}:{asset_count}".encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


async def skill_deletion_impact(
    session: AsyncSession,
    user_id: str,
    skill_id: str,
) -> SkillDeletionImpact | None:
    skill = await get_user_skill(session, user_id, skill_id)
    if skill is None:
        return None
    _require_custom_skill(skill)
    asset_count = await session.scalar(
        select(func.count(Asset.id)).where(
            Asset.user_id == user_id,
            Asset.user_skill_id == skill_id,
        )
    )
    return SkillDeletionImpact(
        skill_id=skill_id,
        asset_count=int(asset_count or 0),
        confirmation_token=_deletion_confirmation_token(
            skill, int(asset_count or 0)
        ),
        revision=_deletion_confirmation_token(skill, int(asset_count or 0)),
    )


async def delete_user_skill(
    session: AsyncSession,
    user_id: str,
    skill_id: str,
    confirmation_token: str,
) -> SkillDeletionResult | None:
    skill = await session.scalar(
        select(UserSkill)
        .where(UserSkill.id == skill_id, UserSkill.user_id == user_id)
        .with_for_update()
    )
    if skill is None:
        return None
    _require_custom_skill(skill)
    asset_count = int(
        await session.scalar(
            select(func.count(Asset.id)).where(
                Asset.user_id == user_id,
                Asset.user_skill_id == skill_id,
            )
        )
        or 0
    )
    actual_token = _deletion_confirmation_token(skill, asset_count)
    if confirmation_token != actual_token:
        raise SkillUpdateConflict(
            "stale_delete_confirmation",
            "Skill 删除影响已变化，请重新确认",
        )
    await session.delete(skill)
    await session.flush()
    return SkillDeletionResult(
        skill_id=skill_id,
        deleted_asset_count=asset_count,
    )


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
            .where(
                UserSkill.user_id == user_id,
                Asset.user_id == user_id,
                Asset.migrated_contact_id.is_(None),
            )
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

    payload = command.payload
    if skill.machine_name == "todo":
        reference = utc_now()
        if reference.tzinfo is None:
            reference = reference.replace(tzinfo=timezone.utc)
        payload = normalize_new_todo_payload(
            payload,
            period=command.period,
            effective_at=command.effective_at,
            occurred_at=command.occurred_at,
            reference_datetime=reference,
            timezone_name=get_settings().default_user_timezone,
        )
    try:
        return await persist_asset(
            session,
            user_id,
            skill=skill,
            command=command.model_copy(update={"payload": payload}),
            write_profile=write_profile,
        )
    except ProvenanceNotOwned as exc:
        raise ChatSessionNotFound() from exc


async def get_asset(
    session: AsyncSession,
    user_id: str,
    asset_id: str,
) -> Asset | None:
    asset = await session.scalar(
        select(Asset).where(
            Asset.id == asset_id,
            Asset.user_id == user_id,
            Asset.migrated_contact_id.is_(None),
        )
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
    query = select(Asset).where(
        Asset.user_id == user_id,
        Asset.migrated_contact_id.is_(None),
    )
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
        payload = command.payload
        if skill.machine_name == "todo":
            payload = normalize_todo_reminder_preferences(payload)
        validate_asset_payload(
            payload,
            skill.schema_json,
            profile=write_profile,
        )
        asset.payload_json = payload
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
        reminder_offsets_json=command.reminder_offsets_minutes,
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
    if (
        "reminder_offsets_minutes" in command.model_fields_set
        and command.reminder_offsets_minutes is not None
    ):
        event.reminder_offsets_json = command.reminder_offsets_minutes
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
    for recording, turn in rows.all():
        references = recording.result_records_json or []
        if any(
            isinstance(reference, dict)
            and reference.get("entity_kind") == kind
            and str(reference.get("entity_id") or "") == record_id
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
