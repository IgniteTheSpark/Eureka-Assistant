"""Onboarding backend service (§6).

Implements idempotent Skill creation from a curated category, an
extraction-only preview that never persists, and idempotent first-Asset
confirmation plus Skip. The hardware capture path is stubbed (typed-only for M2).
"""
from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import CHAR, String, UniqueConstraint, select
from sqlalchemy.dialects import mysql
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, new_uuid, utc_now
from app.db.models import Asset, UserSkill
from app.domains.assets.schemas import AssetCreate, UserSkillCreate
from app.domains.assets.service import create_asset, create_user_skill
from app.domains.assets.validation import AssetPayloadInvalid, AssetWriteProfile
from app.domains.onboarding.catalog import get_category


class OnboardingError(Exception):
    pass


class SkillNotOwned(OnboardingError):
    pass


class IdempotencyConflict(OnboardingError):
    pass


class AssetResultMarker(Base):
    __tablename__ = "onboarding_asset_results"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "idempotency_key",
            name="uq_onboarding_asset_results_user_key",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(255), nullable=False)
    asset_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    request_fingerprint: Mapped[str | None] = mapped_column(
        String(64), nullable=True
    )
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
    """Fingerprint the identity-relevant field shape.

    Includes the normalized key, type, and label so that two field sets with
    the same keys but different types or labels produce distinct skill
    identities (§6 custom-field invariant).
    """
    entries = []
    for field in fields:
        key = _normalize(str(field.get("key", "")))
        if not key:
            continue
        field_type = _normalize(str(field.get("type", "text")))
        label = _normalize(str(field.get("label", "")))
        entries.append(f"{key}:{field_type}:{label}")
    return "|".join(sorted(entries))


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


def _catalog_fields(category: str, field_keys: list[str]) -> tuple[dict, list[dict]]:
    catalog_entry = get_category(category)
    if catalog_entry is None:
        raise OnboardingError("记录类型不在预制目录中")
    if not field_keys:
        raise OnboardingError("请至少选择一个记录字段")
    if len(field_keys) != len(set(field_keys)):
        raise OnboardingError("记录字段不能重复")

    fields_by_key = {field["key"]: field for field in catalog_entry["fields"]}
    if any(key not in fields_by_key for key in field_keys):
        raise OnboardingError("记录字段不属于所选类型")
    selected = set(field_keys)
    fields = [field for field in catalog_entry["fields"] if field["key"] in selected]
    return catalog_entry, fields


async def create_onboarding_skill(
    session: AsyncSession,
    user_id: str,
    *,
    category: str,
    field_keys: list[str],
) -> tuple[UserSkill, bool]:
    catalog_entry, fields = _catalog_fields(category, field_keys)
    display_name = catalog_entry["label"]
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
        description=catalog_entry["description"],
        domain=catalog_entry["id"],
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


def _extract_by_type(source_text: str, field: dict):
    """Extract a field value typed per the schema field type.

    number/duration return int/float (matching the JSON-schema "number"),
    time returns "HH:MM", text returns the raw string or None.
    """
    field_type = str(field.get("type", "text"))
    if field_type == "number":
        match = _NUMBER_RE.search(source_text)
        return float(match.group(1)) if match else None
    if field_type == "duration":
        match = _DURATION_RE.search(source_text)
        if match:
            value = float(match.group(1))
            unit = match.group(2).lower()
            if unit in {"小时", "hour", "hours", "hrs"}:
                value = value * 60
            return float(value)
        fallback = _NUMBER_RE.search(source_text)
        return float(fallback.group(1)) if fallback else None
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
    # §6: an all-empty confirmation must never mint an Asset; guard sits
    # before the idempotency lookup so `{}` cannot be accepted even on retry.
    if not isinstance(payload, dict) or not payload:
        raise AssetPayloadInvalid("onboarding payload must not be empty")

    fingerprint = _confirmation_fingerprint(skill_id, payload)

    existing = await session.scalar(
        select(AssetResultMarker).where(
            AssetResultMarker.user_id == user_id,
            AssetResultMarker.idempotency_key == idempotency_key,
        )
    )
    if existing is not None:
        return await _replay_confirmation(
            session,
            user_id=user_id,
            marker=existing,
            request_fingerprint=fingerprint,
        )

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
            idempotency_key=idempotency_key,
            asset_id=asset.id,
            user_id=user_id,
            request_fingerprint=fingerprint,
        )
    )
    # §4.4: confirming the preview creates the first Asset and marks onboarding
    # completed server-side, so a fresh login does not re-enter onboarding.
    from app.auth.models import ONBOARDING_COMPLETED, UserAccount

    user = await session.scalar(
        select(UserAccount).where(UserAccount.id == user_id)
    )
    if user is not None and user.onboarding_status != ONBOARDING_COMPLETED:
        user.onboarding_status = ONBOARDING_COMPLETED
    try:
        await session.flush()
    except IntegrityError:
        # Concurrent duplicate submission with the same (user, key): roll back
        # and return the already-created Asset instead of failing.
        await session.rollback()
        existing = await session.scalar(
            select(AssetResultMarker).where(
                AssetResultMarker.user_id == user_id,
                AssetResultMarker.idempotency_key == idempotency_key,
            )
        )
        if existing is not None:
            return await _replay_confirmation(
                session,
                user_id=user_id,
                marker=existing,
                request_fingerprint=fingerprint,
            )
        raise
    return ConfirmationResult(asset_id=asset.id, created=True)


def _confirmation_fingerprint(skill_id: str, payload: dict) -> str:
    canonical = json.dumps(
        {"skill_id": skill_id, "payload": payload},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


async def _replay_confirmation(
    session: AsyncSession,
    *,
    user_id: str,
    marker: AssetResultMarker,
    request_fingerprint: str,
) -> ConfirmationResult:
    stored_fingerprint = marker.request_fingerprint
    if stored_fingerprint is None:
        asset = await session.scalar(
            select(Asset).where(
                Asset.id == marker.asset_id,
                Asset.user_id == user_id,
            )
        )
        if asset is None:
            raise IdempotencyConflict("幂等记录对应的数据不存在")
        stored_fingerprint = _confirmation_fingerprint(
            asset.user_skill_id,
            asset.payload_json,
        )
        if stored_fingerprint == request_fingerprint:
            marker.request_fingerprint = stored_fingerprint
            await session.flush()

    if stored_fingerprint != request_fingerprint:
        raise IdempotencyConflict("同一个幂等键不能用于不同的记录内容")
    return ConfirmationResult(asset_id=marker.asset_id, created=False)


async def skip_onboarding(session: AsyncSession, user_id: str) -> str:
    from app.auth.models import ONBOARDING_COMPLETED, ONBOARDING_SKIPPED, UserAccount

    user = await session.scalar(
        select(UserAccount).where(UserAccount.id == user_id)
    )
    if user is None:
        raise OnboardingError("account not found")
    if user.onboarding_status == ONBOARDING_COMPLETED:
        return user.onboarding_status
    user.onboarding_status = ONBOARDING_SKIPPED
    await session.flush()
    return user.onboarding_status
