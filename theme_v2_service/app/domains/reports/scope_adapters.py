from __future__ import annotations

import hashlib
import json
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from pydantic import Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset, Event, UserSkill
from app.domains.reports.schemas import (
    EvidenceReference,
    ReportScopeDraft,
    ScopeAdapterKind,
    StrictModel,
    TimeRange,
)


class ScopeEventCandidate(StrictModel):
    reference: EvidenceReference
    title: str
    local_date: str
    local_start: str
    local_end: str
    location: str | None = None
    notes: str | None = None


class ScopeRecordCandidate(StrictModel):
    reference: EvidenceReference
    title: str
    effective_at: datetime
    preview: dict = Field(default_factory=dict)
    default_selected: bool = True


class ScopeRecordGroup(StrictModel):
    skill_id: str
    label: str
    count: int
    default_selected: bool = True
    records: list[ScopeRecordCandidate] = Field(default_factory=list)


class ReportScopeCandidateResponse(StrictModel):
    adapter_kind: ScopeAdapterKind
    events: list[ScopeEventCandidate] = Field(default_factory=list)
    record_groups: list[ScopeRecordGroup] = Field(default_factory=list)
    default_scope: ReportScopeDraft


def _aware_utc(value: datetime) -> datetime:
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return aware.astimezone(timezone.utc)


def _utc_naive(value: datetime) -> datetime:
    return _aware_utc(value).replace(tzinfo=None)


def infer_scope_adapter(intent: str) -> ScopeAdapterKind:
    normalized = intent.casefold()
    pre_event_markers = (
        "会前",
        "会议准备",
        "会议的背景",
        "meeting brief",
        "pre-event",
        "pre event",
    )
    summary_markers = ("汇总", "总结", "复盘", "统计", "趋势")
    period_markers = (
        "这周",
        "本周",
        "这个星期",
        "本月",
        "这个月",
        "最近",
        "过去",
    )
    if any(marker in normalized for marker in pre_event_markers):
        return "pre_event_briefing"
    if any(marker in normalized for marker in summary_markers) and any(
        marker in normalized for marker in period_markers
    ):
        return "period_summary"
    return "generic"


def resolve_report_period(
    intent: str,
    *,
    now: datetime,
    timezone_name: str,
) -> TimeRange:
    zone = ZoneInfo(timezone_name)
    local_now = _aware_utc(now).astimezone(zone)
    normalized = intent.casefold()
    if "本月" in normalized or "这个月" in normalized:
        start = datetime.combine(
            local_now.date().replace(day=1),
            time.min,
            tzinfo=zone,
        )
        if start.month == 12:
            end = start.replace(year=start.year + 1, month=1)
        else:
            end = start.replace(month=start.month + 1)
        return TimeRange(from_at=start, to_at=end)
    if any(marker in normalized for marker in ("这周", "本周", "这个星期")):
        monday = local_now.date() - timedelta(days=local_now.weekday())
        start = datetime.combine(monday, time.min, tzinfo=zone)
        return TimeRange(from_at=start, to_at=start + timedelta(days=7))
    end = local_now
    return TimeRange(from_at=end - timedelta(days=7), to_at=end)


def initial_scope(
    intent: str,
    *,
    now: datetime,
    timezone_name: str,
    trigger_event_id: str | None = None,
) -> ReportScopeDraft:
    adapter_kind: ScopeAdapterKind = (
        "pre_event_briefing"
        if trigger_event_id is not None
        else infer_scope_adapter(intent)
    )
    return ReportScopeDraft(
        adapter_kind=adapter_kind,
        primary_reference=(
            EvidenceReference(kind="event", id=trigger_event_id)
            if trigger_event_id is not None
            else None
        ),
        time_range=(
            resolve_report_period(intent, now=now, timezone_name=timezone_name)
            if adapter_kind == "period_summary"
            else None
        ),
    )


def scope_digest(
    draft: ReportScopeDraft,
    *,
    primary_version: str | None,
) -> str:
    canonical = draft.model_dump(mode="json", by_alias=True)
    canonical["primary_version"] = primary_version
    encoded = json.dumps(
        canonical,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _aggregatable_skill(skill: UserSkill) -> bool:
    properties = (skill.schema_json or {}).get("properties", {})
    if not isinstance(properties, dict):
        return False
    for definition in properties.values():
        if not isinstance(definition, dict):
            continue
        if definition.get("type") in {"number", "integer", "boolean"}:
            return True
        if isinstance(definition.get("enum"), list) and definition["enum"]:
            return True
    return False


def _record_title(skill: UserSkill, asset: Asset) -> str:
    payload = asset.payload_json or {}
    for key in ("title", "name", "summary"):
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()[:160]
    return skill.display_name


def _preview(payload: dict) -> dict:
    return {
        str(key)[:100]: value
        for key, value in list(payload.items())[:4]
        if isinstance(value, (str, int, float, bool)) or value is None
    }


async def _future_events(
    session: AsyncSession,
    *,
    user_id: str,
    now: datetime,
    timezone_name: str,
) -> list[ScopeEventCandidate]:
    rows = list(
        await session.scalars(
            select(Event)
            .where(
                Event.user_id == user_id,
                Event.start_at > _utc_naive(now),
                Event.status.not_in(("cancelled", "deleted", "completed")),
            )
            .order_by(Event.start_at.asc(), Event.id.asc())
            .limit(3)
        )
    )
    zone = ZoneInfo(timezone_name)
    return [
        ScopeEventCandidate(
            reference=EvidenceReference(kind="event", id=row.id),
            title=row.title,
            local_date=_aware_utc(row.start_at).astimezone(zone).date().isoformat(),
            local_start=_aware_utc(row.start_at).astimezone(zone).strftime("%H:%M"),
            local_end=_aware_utc(row.end_at).astimezone(zone).strftime("%H:%M"),
            location=row.location,
            notes=row.description,
        )
        for row in rows
    ]


async def _period_records(
    session: AsyncSession,
    *,
    user_id: str,
    period: TimeRange,
    timezone_name: str,
) -> list[ScopeRecordGroup]:
    observed_at = func.coalesce(Asset.effective_at, Asset.created_at)
    query = (
        select(UserSkill, Asset)
        .join(Asset, Asset.user_skill_id == UserSkill.id)
        .where(
            UserSkill.user_id == user_id,
            UserSkill.enabled.is_(True),
            Asset.user_id == user_id,
        )
        .order_by(UserSkill.id.asc(), observed_at.asc(), Asset.id.asc())
    )
    if period.from_at is not None:
        query = query.where(observed_at >= _utc_naive(period.from_at))
    if period.to_at is not None:
        query = query.where(observed_at < _utc_naive(period.to_at))
    rows = (await session.execute(query)).all()
    zone = ZoneInfo(timezone_name)
    grouped: dict[str, ScopeRecordGroup] = {}
    for skill, asset in rows:
        if not _aggregatable_skill(skill):
            continue
        group = grouped.get(skill.id)
        if group is None:
            group = ScopeRecordGroup(
                skill_id=skill.id,
                label=skill.display_name,
                count=0,
                records=[],
            )
            grouped[skill.id] = group
        effective_at = _aware_utc(asset.effective_at or asset.created_at).astimezone(zone)
        group.records.append(
            ScopeRecordCandidate(
                reference=EvidenceReference(kind="asset", id=asset.id),
                title=_record_title(skill, asset),
                effective_at=effective_at,
                preview=_preview(asset.payload_json or {}),
            )
        )
        group.count += 1
    return list(grouped.values())


async def list_scope_candidates(
    session: AsyncSession,
    *,
    user_id: str,
    adapter_kind: ScopeAdapterKind,
    intent: str,
    now: datetime,
    timezone_name: str,
) -> ReportScopeCandidateResponse:
    draft = initial_scope(
        intent,
        now=now,
        timezone_name=timezone_name,
    ).model_copy(update={"adapter_kind": adapter_kind})
    events: list[ScopeEventCandidate] = []
    record_groups: list[ScopeRecordGroup] = []
    if adapter_kind == "pre_event_briefing":
        events = await _future_events(
            session,
            user_id=user_id,
            now=now,
            timezone_name=timezone_name,
        )
    elif adapter_kind == "period_summary":
        period = draft.time_range or resolve_report_period(
            intent,
            now=now,
            timezone_name=timezone_name,
        )
        record_groups = await _period_records(
            session,
            user_id=user_id,
            period=period,
            timezone_name=timezone_name,
        )
        draft = draft.model_copy(
            update={
                "skill_ids": [group.skill_id for group in record_groups],
                "supporting_references": [
                    record.reference
                    for group in record_groups
                    for record in group.records
                ],
            }
        )
    return ReportScopeCandidateResponse(
        adapter_kind=adapter_kind,
        events=events,
        record_groups=record_groups,
        default_scope=draft,
    )
