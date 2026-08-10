from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db.base import utc_now
from app.db.models import Asset, UserSkill
from app.domains.assets.indexing import rebuild_asset_fields
from app.domains.assets.schemas import AssetCreate
from app.domains.assets.validation import AssetWriteProfile, validate_asset_payload
from app.domains.sessions.provenance import validate_owned_provenance
from app.domains.triggers.service import on_asset_created


def _utc_naive(value: datetime | None) -> datetime | None:
    if value is None or value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


async def persist_asset(
    session: AsyncSession,
    user_id: str,
    *,
    skill: UserSkill,
    command: AssetCreate,
    write_profile: AssetWriteProfile,
    timezone_name: str | None = None,
) -> Asset:
    validate_asset_payload(
        command.payload,
        skill.schema_json,
        profile=write_profile,
    )
    provenance = await validate_owned_provenance(
        session,
        user_id,
        session_id=command.session_id,
        input_turn_id=command.source_input_turn_id,
    )
    asset = Asset(
        user_id=user_id,
        user_skill_id=skill.id,
        payload_json=dict(command.payload),
        domain=command.domain or skill.domain,
        effective_at=_utc_naive(command.effective_at),
        period=command.period,
        occurred_at=_utc_naive(command.occurred_at),
        session_id=provenance.session_id,
        source_input_turn_id=provenance.input_turn_id,
    )
    session.add(asset)
    await session.flush()
    await rebuild_asset_fields(
        session,
        asset=asset,
        skill=skill,
        clear_existing=False,
    )
    await on_asset_created(
        session,
        asset=asset,
        now=utc_now(),
        timezone_name=timezone_name or get_settings().default_user_timezone,
    )
    return asset
