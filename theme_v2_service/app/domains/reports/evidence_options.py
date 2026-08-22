from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset, Contact, Event, UserSkill
from app.domains.reports.schemas import EvidenceReference


_BUILTIN_ICONS = {
    "todo": "📋",
    "expense": "💳",
    "notes": "✍️",
    "event": "📅",
    "contact": "👤",
}


class EvidenceOptionModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class EvidenceOption(EvidenceOptionModel):
    reference: EvidenceReference
    type_label: str
    filter_id: str
    filter_label: str
    title: str
    subtitle: str | None = None
    icon: str
    effective_at: datetime | None = None


class EvidenceOptionPage(EvidenceOptionModel):
    items: list[EvidenceOption]
    next_cursor: str | None = None
    filters: list[dict[str, str]] = Field(default_factory=list)


def _text(value: Any) -> str:
    if isinstance(value, (str, int, float)):
        return str(value).strip()
    return ""


def _card_fields(skill: UserSkill) -> tuple[str, list[str]]:
    render_spec = skill.render_spec_json or {}
    card_display = render_spec.get("card_display")
    if not isinstance(card_display, dict):
        card_display = {}
    primary = str(
        card_display.get("primary_field_id")
        or render_spec.get("primary_field")
        or ""
    ).strip()
    secondary = card_display.get("secondary_field_ids")
    if not isinstance(secondary, list):
        secondary = [render_spec.get("secondary_field")]
        meta_fields = render_spec.get("meta_fields")
        if isinstance(meta_fields, list):
            secondary.extend(
                row.get("field")
                for row in meta_fields
                if isinstance(row, dict)
            )
    return primary, [
        str(field).strip()
        for field in secondary
        if field and str(field).strip() != primary
    ][:3]


def _asset_card_text(asset: Asset, skill: UserSkill) -> tuple[str, str | None]:
    payload = asset.payload_json or {}
    primary, secondary = _card_fields(skill)
    title = _text(payload.get(primary))[:120] if primary else ""
    subtitle_values = [
        value
        for field in secondary
        if (value := _text(payload.get(field)))
    ]

    if not title:
        preferred_fields = (
            "title",
            "name",
            "content",
            "summary",
            "description",
            "merchant",
            "category",
            "amount",
        )
        fallback_values: list[str] = []
        inspected_fields: set[str] = {primary, *secondary}
        for field in (*preferred_fields, *payload.keys()):
            if field in inspected_fields:
                continue
            inspected_fields.add(field)
            value = _text(payload.get(field))
            if value:
                fallback_values.append(value)
        if fallback_values:
            title = fallback_values.pop(0)[:120]
            subtitle_values.extend(fallback_values[:3])

    skill_name = _text(getattr(skill, "display_name", ""))
    if not title:
        title = skill_name or "未命名资产"
    if not subtitle_values and title != skill_name and skill_name:
        subtitle_values.append(skill_name)
    subtitle = " · ".join(subtitle_values)
    return title, subtitle[:120] or None


def _asset_icon(skill: UserSkill) -> str:
    return _BUILTIN_ICONS.get(skill.machine_name) or str(
        (skill.render_spec_json or {}).get("icon") or "•"
    )


def _decode_cursor(cursor: str | None) -> int:
    if cursor is None:
        return 0
    try:
        return max(0, int(cursor))
    except ValueError:
        return 0


async def list_evidence_options(
    session: AsyncSession,
    *,
    user_id: str,
    query: str = "",
    type_filter: Literal["all", "asset", "event", "contact"] = "all",
    skill_filter: str | None = None,
    cursor: str | None = None,
    limit: int = 50,
) -> EvidenceOptionPage:
    normalized_query = query.strip()
    bounded_limit = min(max(limit, 1), 100)
    candidates: list[EvidenceOption] = []

    skills = list(
        await session.scalars(
            select(UserSkill)
            .where(UserSkill.user_id == user_id, UserSkill.enabled.is_(True))
            .order_by(UserSkill.position, UserSkill.created_at, UserSkill.id)
        )
    )
    skills_by_id = {skill.id: skill for skill in skills}

    if type_filter in {"all", "asset"}:
        asset_query = select(Asset).where(
            Asset.user_id == user_id,
            Asset.migrated_contact_id.is_(None),
        )
        if skill_filter:
            asset_query = asset_query.where(Asset.user_skill_id == skill_filter)
        assets = list(
            await session.scalars(
                asset_query.order_by(
                    Asset.effective_at.desc(),
                    Asset.created_at.desc(),
                    Asset.id.desc(),
                ).limit(500)
            )
        )
        for asset in assets:
            skill = skills_by_id.get(asset.user_skill_id)
            if skill is None:
                continue
            title, subtitle = _asset_card_text(asset, skill)
            haystack = f"{title} {subtitle or ''} {skill.display_name}".casefold()
            if normalized_query and normalized_query.casefold() not in haystack:
                continue
            candidates.append(
                EvidenceOption(
                    reference=EvidenceReference(kind="asset", id=asset.id),
                    type_label=skill.display_name,
                    filter_id=skill.id,
                    filter_label=skill.display_name,
                    title=title,
                    subtitle=subtitle,
                    icon=_asset_icon(skill),
                    effective_at=asset.effective_at or asset.created_at,
                )
            )

    if type_filter in {"all", "event"} and not skill_filter:
        event_query = select(Event).where(
            Event.user_id == user_id,
            Event.status != "cancelled",
        )
        if normalized_query:
            pattern = f"%{normalized_query}%"
            event_query = event_query.where(
                or_(
                    Event.title.like(pattern),
                    Event.description.like(pattern),
                    Event.location.like(pattern),
                )
            )
        events = list(
            await session.scalars(
                event_query.order_by(Event.start_at.desc(), Event.id.desc()).limit(500)
            )
        )
        candidates.extend(
            EvidenceOption(
                reference=EvidenceReference(kind="event", id=event.id),
                type_label="日程",
                filter_id="event",
                filter_label="日程",
                title=event.title,
                subtitle=event.location,
                icon=_BUILTIN_ICONS["event"],
                effective_at=event.start_at,
            )
            for event in events
        )

    if type_filter in {"all", "contact"} and not skill_filter:
        contact_query = select(Contact).where(Contact.user_id == user_id)
        if normalized_query:
            pattern = f"%{normalized_query}%"
            contact_query = contact_query.where(
                or_(
                    Contact.name.like(pattern),
                    Contact.company.like(pattern),
                    Contact.title.like(pattern),
                )
            )
        contacts = list(
            await session.scalars(
                contact_query.order_by(Contact.created_at.desc(), Contact.id.desc()).limit(500)
            )
        )
        candidates.extend(
            EvidenceOption(
                reference=EvidenceReference(kind="contact", id=contact.id),
                type_label="联系人",
                filter_id="contact",
                filter_label="联系人",
                title=contact.name,
                subtitle=" · ".join(
                    value for value in (contact.company, contact.title) if value
                )
                or None,
                icon=_BUILTIN_ICONS["contact"],
                effective_at=contact.created_at,
            )
            for contact in contacts
        )

    candidates.sort(
        key=lambda item: (
            item.effective_at or datetime.min,
            item.reference.kind,
            item.reference.id,
        ),
        reverse=True,
    )
    offset = _decode_cursor(cursor)
    page = candidates[offset : offset + bounded_limit]
    next_offset = offset + len(page)
    filters = [
        {"id": "all", "label": "全部"},
        {"id": "event", "label": "日程"},
        {"id": "contact", "label": "联系人"},
        *(
            {"id": skill.id, "label": skill.display_name}
            for skill in skills
            if skill.machine_name not in {"event", "contact"}
        ),
    ]
    return EvidenceOptionPage(
        items=page,
        next_cursor=str(next_offset) if next_offset < len(candidates) else None,
        filters=filters,
    )
