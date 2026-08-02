from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db.base import utc_now
from app.db.models import Asset, Event, UserSkill
from app.domains.assets.schemas import (
    AssetCreate,
    AssetUpdate,
    EventCreate,
    EventUpdate,
    UserSkillCreate,
)
from app.domains.triggers.service import on_asset_created


class UserSkillNotFound(Exception):
    pass


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
        "machine_name": "idea",
        "display_name": "想法",
        "description": "灵感、产品想法和待探索方向",
        "domain": "knowledge",
        "schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "content": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}},
                "domain": {"type": "string"},
            },
            "required": ["title", "content", "tags"],
            "additionalProperties": False,
            "x-capture-enabled": True,
        },
    },
    {
        "machine_name": "notes",
        "display_name": "随记",
        "description": "忠于原文的自由文本笔记",
        "domain": "knowledge",
        "schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "content": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}},
                "domain": {"type": "string"},
            },
            "required": ["title", "content", "tags"],
            "additionalProperties": False,
            "x-capture-enabled": True,
        },
    },
    {
        "machine_name": "misc",
        "display_name": "其他",
        "description": "无法归入更具体类型的记录",
        "domain": "knowledge",
        "schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "content": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}},
                "domain": {"type": "string"},
            },
            "required": ["title", "content", "tags"],
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
    for definition in BASELINE_CAPTURE_SKILLS:
        machine_name = definition["machine_name"]
        if machine_name in by_name:
            continue
        skill = UserSkill(
            user_id=user_id,
            machine_name=machine_name,
            display_name=definition["display_name"],
            description=definition["description"],
            domain=definition["domain"],
            schema_json=definition["schema"],
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
    skill = UserSkill(
        user_id=user_id,
        machine_name=command.machine_name,
        display_name=command.display_name,
        description=command.description,
        domain=command.domain,
        schema_json=command.schema_definition,
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


async def create_asset(
    session: AsyncSession,
    user_id: str,
    command: AssetCreate,
) -> Asset:
    skill = await session.scalar(
        select(UserSkill).where(
            UserSkill.id == command.user_skill_id,
            UserSkill.user_id == user_id,
        )
    )
    if skill is None:
        raise UserSkillNotFound()

    asset = Asset(
        user_id=user_id,
        user_skill_id=skill.id,
        payload_json=command.payload,
        effective_at=_utc_naive(command.effective_at),
    )
    session.add(asset)
    await session.flush()
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
    return await session.scalar(
        select(Asset).where(Asset.id == asset_id, Asset.user_id == user_id)
    )


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
    return list(result)


async def update_asset(
    session: AsyncSession,
    user_id: str,
    asset_id: str,
    command: AssetUpdate,
) -> Asset | None:
    asset = await get_asset(session, user_id, asset_id)
    if asset is None:
        return None
    if "payload" in command.model_fields_set and command.payload is not None:
        asset.payload_json = command.payload
    if "effective_at" in command.model_fields_set:
        asset.effective_at = _utc_naive(command.effective_at)
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
    event = Event(
        user_id=user_id,
        title=command.title,
        description=command.description,
        location=command.location,
        start_at=_utc_naive(command.start_at),
        end_at=_utc_naive(command.end_at),
        all_day=command.all_day,
        status=command.status,
    )
    session.add(event)
    await session.flush()
    return event


async def get_event(
    session: AsyncSession,
    user_id: str,
    event_id: str,
) -> Event | None:
    return await session.scalar(
        select(Event).where(Event.id == event_id, Event.user_id == user_id)
    )


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
    query = select(Event).where(Event.user_id == user_id)
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
    return list(result)


async def update_event(
    session: AsyncSession,
    user_id: str,
    event_id: str,
    command: EventUpdate,
) -> Event | None:
    event = await get_event(session, user_id, event_id)
    if event is None:
        return None
    for field in ("title", "description", "location", "all_day", "status"):
        if field in command.model_fields_set:
            setattr(event, field, getattr(command, field))
    if "start_at" in command.model_fields_set and command.start_at is not None:
        event.start_at = _utc_naive(command.start_at)
    if "end_at" in command.model_fields_set and command.end_at is not None:
        event.end_at = _utc_naive(command.end_at)
    event.updated_at = utc_now()
    await session.flush()
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
