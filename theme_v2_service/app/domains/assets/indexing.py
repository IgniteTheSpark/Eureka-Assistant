from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation

from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset, AssetField, UserSkill


def queryable_field_names(skill: UserSkill) -> list[str]:
    declared = skill.queryable_fields_json or []
    if declared:
        return list(dict.fromkeys(str(name).strip() for name in declared if str(name).strip()))
    properties = (skill.schema_json or {}).get("properties") or {}
    if not isinstance(properties, dict):
        return []
    return [str(name) for name in properties]


def _date_value(value: object, field_schema: dict) -> datetime | None:
    if not isinstance(value, str):
        return None
    if field_schema.get("format") not in {"date", "date-time"}:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
    return parsed


def _number_value(value: object) -> Decimal | None:
    if isinstance(value, bool) or not isinstance(value, (int, float, Decimal)):
        return None
    try:
        return Decimal(str(value))
    except InvalidOperation:
        return None


async def rebuild_asset_fields(
    session: AsyncSession,
    *,
    asset: Asset,
    skill: UserSkill,
    clear_existing: bool = True,
) -> None:
    if clear_existing:
        await session.execute(
            delete(AssetField).where(AssetField.asset_id == asset.id)
        )
    properties = (skill.schema_json or {}).get("properties") or {}
    payload = asset.payload_json or {}
    for field_name in queryable_field_names(skill):
        if field_name not in payload:
            continue
        value = payload[field_name]
        if value is None or isinstance(value, (dict, list)):
            continue
        field_schema = properties.get(field_name) or {}
        number = _number_value(value)
        date_value = _date_value(value, field_schema)
        text_value = None
        if number is None and date_value is None:
            if isinstance(value, bool):
                text_value = "true" if value else "false"
            else:
                text_value = str(value)[:500]
        session.add(
            AssetField(
                asset_id=asset.id,
                user_id=asset.user_id,
                field_name=field_name,
                value_text=text_value,
                value_number=number,
                value_date=date_value,
            )
        )
    await session.flush()
