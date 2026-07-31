import json
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import case, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset, Event, UserSkill
from app.domains.reports.schemas import TimeRange


class PlannerToolModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class PlannerSkill(PlannerToolModel):
    id: str
    user_id: str
    display_name: str
    description: str | None
    domain: str | None
    capabilities: list[str] = Field(default_factory=list)


class PlannerAssetRecord(PlannerToolModel):
    id: str
    user_skill_id: str
    effective_at: datetime | None
    payload: dict


class PlannerAssetSummary(PlannerToolModel):
    id: str
    user_skill_id: str
    effective_at: datetime | None
    fields: dict[str, Any]


class PlannerEvent(PlannerToolModel):
    id: str
    title: str
    description: str | None
    location: str | None
    start_at: datetime
    end_at: datetime
    all_day: bool


@dataclass(frozen=True)
class PlannerLimits:
    max_candidate_skills: int = 20
    max_summaries_per_skill: int = 20
    max_total_summaries: int = 100
    max_serialized_context_bytes: int = 64 * 1024

    def __post_init__(self) -> None:
        for field_name in (
            "max_candidate_skills",
            "max_summaries_per_skill",
            "max_total_summaries",
            "max_serialized_context_bytes",
        ):
            if getattr(self, field_name) <= 0:
                raise ValueError(f"{field_name} must be positive")


def _capabilities(schema: dict) -> set[str]:
    explicit = schema.get("x-data-capabilities", schema.get("capabilities", []))
    capabilities = {
        str(item) for item in explicit if isinstance(item, str) and item.strip()
    }
    properties = schema.get("properties", {})
    if not isinstance(properties, dict):
        return capabilities
    if properties:
        capabilities.add("daily_log")
    for name, definition in properties.items():
        if not isinstance(definition, dict):
            continue
        lowered = name.lower()
        field_type = definition.get("type")
        if field_type in {"number", "integer"}:
            capabilities.add("time_series_measurement")
        if definition.get("enum"):
            capabilities.add("categorical_log")
        if field_type == "string":
            capabilities.add("free_text")
        if any(token in lowered for token in ("outcome", "result", "score", "status")):
            capabilities.add("outcome_record")
        if any(
            token in lowered
            for token in ("counterparty", "client", "vendor", "opponent", "attendee")
        ):
            capabilities.add("counterparty")
        if any(token in lowered for token in ("location", "address", "venue")):
            capabilities.add("location")
    return capabilities


def _utc_naive(value: datetime | None) -> datetime | None:
    if value is None or value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def _summarize(value: Any, *, depth: int = 0) -> Any:
    if depth >= 3:
        return "[nested]"
    if isinstance(value, str):
        return value[:240]
    if isinstance(value, (int, float, bool)) or value is None:
        return value
    if isinstance(value, list):
        return [_summarize(item, depth=depth + 1) for item in value[:5]]
    if isinstance(value, dict):
        return {
            str(key)[:100]: _summarize(item, depth=depth + 1)
            for key, item in list(value.items())[:20]
        }
    return str(value)[:240]


class PlannerTools:
    PUBLIC_METHODS = (
        "list_user_skills",
        "get_skill_schema",
        "query_assets",
        "get_asset_summaries",
        "get_event",
        "get_event_attendees",
        "get_event_files",
        "get_related_sessions",
    )

    def __init__(
        self,
        session: AsyncSession,
        *,
        user_id: str,
        limits: PlannerLimits | None = None,
    ) -> None:
        self._session = session
        self.user_id = user_id
        self.limits = limits or PlannerLimits()
        self._summaries_used = 0
        self._summaries_by_skill: dict[str, int] = {}
        self._context_bytes_used = 0

    async def list_user_skills(
        self,
        preferred_ids: list[str] | None = None,
    ) -> list[PlannerSkill]:
        preferred = list(dict.fromkeys(preferred_ids or []))
        order_by = []
        if preferred:
            order_by.append(
                case(
                    {skill_id: index for index, skill_id in enumerate(preferred)},
                    value=UserSkill.id,
                    else_=len(preferred),
                )
            )
        order_by.extend((UserSkill.created_at.desc(), UserSkill.id.desc()))
        rows = list(
            await self._session.scalars(
                select(UserSkill)
                .where(UserSkill.user_id == self.user_id)
                .order_by(*order_by)
                .limit(self.limits.max_candidate_skills)
            )
        )
        return [
            PlannerSkill(
                id=row.id,
                user_id=row.user_id,
                display_name=row.display_name,
                description=row.description,
                domain=row.domain,
                capabilities=sorted(_capabilities(row.schema_json)),
            )
            for row in rows
        ]

    async def get_skill_schema(self, skill_id: str) -> dict | None:
        value = await self._session.scalar(
            select(UserSkill.schema_json).where(
                UserSkill.id == skill_id,
                UserSkill.user_id == self.user_id,
            )
        )
        return dict(value) if value is not None else None

    async def query_assets(
        self,
        skill_id: str,
        *,
        time_range: TimeRange | None = None,
        limit: int | None = None,
    ) -> list[PlannerAssetRecord]:
        bounded_limit = min(
            max(1, limit or self.limits.max_summaries_per_skill),
            self.limits.max_summaries_per_skill,
        )
        observed_at = func.coalesce(Asset.effective_at, Asset.created_at)
        query = select(Asset).where(
            Asset.user_id == self.user_id,
            Asset.user_skill_id == skill_id,
        )
        if time_range is not None and time_range.from_at is not None:
            query = query.where(observed_at >= _utc_naive(time_range.from_at))
        if time_range is not None and time_range.to_at is not None:
            query = query.where(observed_at <= _utc_naive(time_range.to_at))
        rows = list(
            await self._session.scalars(
                query.order_by(observed_at.desc(), Asset.id.desc()).limit(bounded_limit)
            )
        )
        return [
            PlannerAssetRecord(
                id=row.id,
                user_skill_id=row.user_skill_id,
                effective_at=row.effective_at or row.created_at,
                payload=row.payload_json,
            )
            for row in rows
        ]

    async def get_asset_summaries(
        self,
        skill_id: str,
        *,
        time_range: TimeRange | None = None,
        limit: int | None = None,
    ) -> list[PlannerAssetSummary]:
        remaining = self.limits.max_total_summaries - self._summaries_used
        remaining_for_skill = (
            self.limits.max_summaries_per_skill
            - self._summaries_by_skill.get(skill_id, 0)
        )
        if remaining <= 0 or remaining_for_skill <= 0:
            return []
        records = await self.query_assets(
            skill_id,
            time_range=time_range,
            limit=min(
                limit or self.limits.max_summaries_per_skill,
                remaining_for_skill,
                remaining,
            ),
        )
        accepted: list[PlannerAssetSummary] = []
        for record in records:
            summary = PlannerAssetSummary(
                id=record.id,
                user_skill_id=record.user_skill_id,
                effective_at=record.effective_at,
                fields=_summarize(record.payload),
            )
            encoded = json.dumps(
                summary.model_dump(mode="json"),
                ensure_ascii=False,
                separators=(",", ":"),
            ).encode("utf-8")
            if self._context_bytes_used + len(encoded) > self.limits.max_serialized_context_bytes:
                break
            accepted.append(summary)
            self._summaries_used += 1
            self._summaries_by_skill[skill_id] = (
                self._summaries_by_skill.get(skill_id, 0) + 1
            )
            self._context_bytes_used += len(encoded)
        return accepted

    async def get_event(self, event_id: str) -> PlannerEvent | None:
        row = await self._session.scalar(
            select(Event).where(
                Event.id == event_id,
                Event.user_id == self.user_id,
            )
        )
        if row is None:
            return None
        return PlannerEvent(
            id=row.id,
            title=row.title,
            description=row.description,
            location=row.location,
            start_at=row.start_at,
            end_at=row.end_at,
            all_day=row.all_day,
        )

    async def get_event_attendees(self, event_id: str) -> list[dict]:
        await self.get_event(event_id)
        return []

    async def get_event_files(self, event_id: str) -> list[dict]:
        await self.get_event(event_id)
        return []

    async def get_related_sessions(self, event_id: str) -> list[dict]:
        await self.get_event(event_id)
        return []
