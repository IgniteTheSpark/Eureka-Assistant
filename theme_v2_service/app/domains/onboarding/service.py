"""Onboarding backend service (§6).

Implements idempotent Skill creation from a curated/custom category, an
extraction-only preview that never persists, and idempotent first-Asset
confirmation plus Skip. The hardware capture path is stubbed (typed-only for M2).
"""
from __future__ import annotations

import hashlib
import re
import unicodedata
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import CHAR, String, UniqueConstraint, select
from sqlalchemy.dialects import mysql
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, new_uuid, utc_now
from app.db.models import UserSkill
from app.domains.assets.schemas import AssetCreate, UserSkillCreate
from app.domains.assets.service import create_asset, create_user_skill
from app.domains.assets.validation import AssetWriteProfile
from app.domains.onboarding.catalog import get_category


class OnboardingError(Exception):
    pass


class SkillNotOwned(OnboardingError):
    pass


class AssetResultMarker(Base):
    __tablename__ = "onboarding_asset_results"
    __table_args__ = (
        UniqueConstraint("idempotency_key", name="uq_onboarding_asset_results_key"),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(255), nullable=False)
    asset_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6), default=utc_now, nullable=False
    )


@dataclass
class ConfirmationResult:
    asset_id: str
    created: bool


def _normalize(value: str) -> str:
    return unicodedata.normalize("NFKC", value).strip().lower()


def _field_fingerprint(fields: list[dict]) -> str:
    keys = sorted(_normalize(str(f.get("key", ""))) for f in fields)
    return "|".join(k for k in keys if k)


def machine_name_for(category: str, fields: list[dict]) -> str:
    base = _normalize(category) + "::" + _field_fingerprint(fields)
    digest = hashlib.sha256(base.encode("utf-8")).hexdigest()[:24]
    return f"onb_{digest}"


def _schema_from_fields(fields: list[dict]) -> dict:
    properties = {}
    for field in fields:
        key = _normalize(str(field.get("key", "")))
        if not key:
            continue
        field_type = str(field.get("type", "text"))
        json_type = {
            "number": "number",
            "duration": "number",
            "time": "string",
        }.get(field_type, "string")
        properties[key] = {
            "type": json_type,
            "title": str(field.get("label", key)),
            "x-type": field_type,
        }
    # No required fields: onboarding confirms a partially filled card (§6.9).
    return {
        "type": "object",
        "properties": properties,
        "required": [],
        "additionalProperties": True,
    }


async def create_onboarding_skill(
    session: AsyncSession,
    user_id: str,
    *,
    category: str,
    fields: list[dict],
) -> tuple[UserSkill, bool]:
    catalog_entry = get_category(category)
    display_name = (
        catalog_entry["label"] if catalog_entry else _normalize(category).capitalize()
    )
    machine_name = machine_name_for(category, fields)

    existing = await session.scalar(
        select(UserSkill).where(
            UserSkill.user_id == user_id,
            UserSkill.machine_name == machine_name,
        )
    )
    if existing is not None:
        return existing, False

    command = UserSkillCreate(
        machine_name=machine_name,
        display_name=display_name,
        description=(
            catalog_entry["description"] if catalog_entry else "自定义记录类型"
        ),
        domain=catalog_entry["id"] if catalog_entry else "custom",
        schema_definition=_schema_from_fields(fields),
        render_spec={},
        chat_starters=[],
        queryable_fields=[f.get("key", "") for f in fields if f.get("key")],
        enabled=True,
    )
    skill = await create_user_skill(session, user_id, command)
    return skill, True


_NUMBER_RE = re.compile(r"(\d+(?:\.\d+)?)")
_DURATION_RE = re.compile(
    r"(\d+(?:\.\d+)?)\s*(分钟|小时|min|hour|mins|hrs)", re.IGNORECASE
)
_TIME_RE = re.compile(r"(\d{1,2})[:：](\d{2})")


@dataclass
class PreviewResult:
    payload: dict | None
    field_warnings: list[str]
    manual_fields: list[dict]


def _extract_by_type(source_text: str, field: dict) -> str | None:
    field_type = str(field.get("type", "text"))
    if field_type == "number":
        match = _NUMBER_RE.search(source_text)
        return match.group(1) if match else None
    if field_type == "duration":
        match = _DURATION_RE.search(source_text)
        if match:
            value = float(match.group(1))
            unit = match.group(2).lower()
            if unit in {"小时", "hour", "hours", "hrs"}:
                value = value * 60
            return str(int(value))
        fallback = _NUMBER_RE.search(source_text)
        return fallback.group(1) if fallback else None
    if field_type == "time":
        match = _TIME_RE.search(source_text)
        return f"{match.group(1)}:{match.group(2)}" if match else None
    return None


async def extract_preview(
    session: AsyncSession,
    user_id: str,
    *,
    skill_id: str,
    source_text: str,
) -> PreviewResult:
    skill = await session.scalar(
        select(UserSkill).where(
            UserSkill.id == skill_id,
            UserSkill.user_id == user_id,
        )
    )
    if skill is None:
        raise SkillNotOwned("skill not found or not owned")

    properties = (
        skill.schema_json.get("properties", {})
        if isinstance(skill.schema_json, dict)
        else {}
    )
    fields = [
        {
            "key": key,
            "label": value.get("title", key),
            "type": value.get("x-type", "text"),
        }
        for key, value in properties.items()
        if isinstance(value, dict)
    ]

    payload = {}
    warnings = []
    for field in fields:
        key = field["key"]
        value = _extract_by_type(source_text, field)
        if value is not None:
            payload[key] = value
        else:
            warnings.append(f"未能从输入中识别「{field['label']}」")
            field["type"] = "text"

    if not payload:
        return PreviewResult(
            payload=None,
            field_warnings=["未能自动提取内容,请手动填写"],
            manual_fields=fields,
        )
    return PreviewResult(payload=payload, field_warnings=warnings, manual_fields=[])


async def confirm_onboarding_asset(
    session: AsyncSession,
    user_id: str,
    *,
    skill_id: str,
    payload: dict,
    idempotency_key: str,
) -> ConfirmationResult:
    existing = await session.scalar(
        select(AssetResultMarker).where(
            AssetResultMarker.idempotency_key == idempotency_key
        )
    )
    if existing is not None:
        return ConfirmationResult(asset_id=existing.asset_id, created=False)

    skill = await session.scalar(
        select(UserSkill).where(
            UserSkill.id == skill_id,
            UserSkill.user_id == user_id,
        )
    )
    if skill is None:
        raise SkillNotOwned("skill not found or not owned")

    asset = await create_asset(
        session,
        user_id,
        AssetCreate(user_skill_id=skill_id, payload=payload),
        write_profile=AssetWriteProfile.manual,
    )
    session.add(
        AssetResultMarker(
            idempotency_key=idempotency_key, asset_id=asset.id, user_id=user_id
        )
    )
    await session.flush()
    return ConfirmationResult(asset_id=asset.id, created=True)


async def skip_onboarding(session: AsyncSession, user_id: str) -> str:
    from app.auth.models import ONBOARDING_SKIPPED, UserAccount

    user = await session.scalar(
        select(UserAccount).where(UserAccount.id == user_id)
    )
    if user is None:
        raise OnboardingError("account not found")
    user.onboarding_status = ONBOARDING_SKIPPED
    await session.flush()
    return user.onboarding_status
