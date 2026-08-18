from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from datetime import datetime, time, timedelta, timezone
from typing import Literal
from zoneinfo import ZoneInfo

from pydantic import Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset, Event, UserSkill
from app.domains.reports.schemas import (
    EvidenceReference,
    ReportAssetSelection,
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


class ScopeMatchTerm(StrictModel):
    value: str
    provenance: Literal["identity", "broad"]
    is_alias: bool = False


class ScopeRecordGroup(StrictModel):
    skill_id: str
    machine_name: str = Field(default="", exclude=True)
    match_terms: list[str] = Field(default_factory=list, exclude=True)
    identity_match_terms: list[str] = Field(default_factory=list, exclude=True)
    match_specs: list[ScopeMatchTerm] = Field(default_factory=list, exclude=True)
    label: str
    count: int
    default_selected: bool = True
    records: list[ScopeRecordCandidate] = Field(default_factory=list)


class TimeRangeOption(StrictModel):
    id: str
    label: str
    time_range: TimeRange | None = None


class ReportScopeCandidateResponse(StrictModel):
    adapter_kind: ScopeAdapterKind
    events: list[ScopeEventCandidate] = Field(default_factory=list)
    record_groups: list[ScopeRecordGroup] = Field(default_factory=list)
    time_range_options: list[TimeRangeOption] = Field(default_factory=list)
    default_scope: ReportScopeDraft


_GENERIC_SKILL_TERMS = {
    "记录",
    "日志",
    "数据",
    "情况",
    "总结",
    "统计",
    "log",
    "record",
    "records",
    "data",
    "tracker",
    "tracking",
    "training",
}
_SKILL_ALIASES = {
    "expense": {"消费", "支出", "花费", "账单", "expense", "spend"},
    "running": {"跑步", "晨跑", "夜跑", "running", "run"},
    "water": {"喝水", "饮水", "water", "hydration"},
    "dance": {"跳舞", "舞蹈", "dance"},
}
_ADDITIVE_RELATION = re.compile(r"(?:以及|还有|和|与|及|跟|、)")


def _normalize_term(value: str | None) -> str:
    return re.sub(r"[\s_\-/]+", "", (value or "").casefold())


def _term_match_spans(term: str, value: str | None) -> list[tuple[int, int]]:
    if term.isascii() and term.isalnum():
        raw = (value or "").casefold()
        words = list(re.finditer(r"[a-z0-9]+", raw))
        spans: list[tuple[int, int]] = []
        for start_index, first in enumerate(words):
            phrase = ""
            for last in words[start_index:]:
                phrase += last.group()
                if phrase == term:
                    spans.append(
                        (
                            len(_normalize_term(raw[: first.start()])),
                            len(_normalize_term(raw[: last.end()])),
                        )
                    )
                    break
                if len(phrase) >= len(term):
                    break
        return spans
    normalized = _normalize_term(value)
    spans: list[tuple[int, int]] = []
    start = normalized.find(term)
    while start >= 0:
        end = start + len(term)
        spans.append((start, end))
        start = normalized.find(term, start + 1)
    return spans


def _term_matches_text(term: str, value: str | None) -> bool:
    return bool(_term_match_spans(term, value))


def _skill_match_terms(
    skill: UserSkill,
) -> tuple[list[str], list[str], list[ScopeMatchTerm]]:
    identity_values = [skill.machine_name, skill.display_name]
    broad_values = [skill.description, skill.domain]
    display = _normalize_term(skill.display_name)
    identity_literals = {
        _normalize_term(skill.machine_name),
        display,
    }
    broad_literals = {
        _normalize_term(skill.description),
        _normalize_term(skill.domain),
    }
    for suffix in ("记录", "日志", "数据", "训练"):
        if display.endswith(suffix) and len(display) > len(suffix):
            identity_literals.add(display[: -len(suffix)])
    for value in identity_values:
        words = re.findall(r"[a-z0-9]+", (value or "").casefold())
        if len(words) > 1 and words[-1] in _GENERIC_SKILL_TERMS:
            identity_literals.add("".join(words[:-1]))
    identity_aliases: set[str] = set()
    broad_aliases: set[str] = set()
    for aliases in _SKILL_ALIASES.values():
        normalized_aliases = {_normalize_term(alias) for alias in aliases}
        if any(
            _term_matches_text(alias, value)
            for alias in normalized_aliases
            for value in identity_values
        ):
            identity_aliases.update(normalized_aliases)
        if any(
            _term_matches_text(alias, value)
            for alias in normalized_aliases
            for value in broad_values
        ):
            broad_aliases.update(normalized_aliases)
    identity = {
        term
        for term in identity_literals | identity_aliases
        if term and term not in _GENERIC_SKILL_TERMS
    }
    broad = {
        term
        for term in broad_literals | broad_aliases
        if term and term not in _GENERIC_SKILL_TERMS
    }
    specs = {
        (term, provenance, is_alias)
        for terms, provenance, is_alias in (
            (identity_literals, "identity", False),
            (identity_aliases, "identity", True),
            (broad_literals, "broad", False),
            (broad_aliases, "broad", True),
        )
        for term in terms
        if term and term not in _GENERIC_SKILL_TERMS
    }
    return (
        sorted(identity | broad),
        sorted(identity),
        [
            ScopeMatchTerm(
                value=term,
                provenance=provenance,
                is_alias=is_alias,
            )
            for term, provenance, is_alias in sorted(specs)
        ],
    )


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
) -> TimeRange | None:
    zone = ZoneInfo(timezone_name)
    local_now = _aware_utc(now).astimezone(zone)
    normalized = intent.casefold()
    if "本月" in normalized or "这个月" in normalized:
        start = datetime.combine(
            local_now.date().replace(day=1),
            time.min,
            tzinfo=zone,
        )
        return TimeRange(from_at=start, to_at=local_now)
    if any(marker in normalized for marker in ("这周", "本周", "这个星期")):
        monday = local_now.date() - timedelta(days=local_now.weekday())
        start = datetime.combine(monday, time.min, tzinfo=zone)
        return TimeRange(from_at=start, to_at=start + timedelta(days=7))
    day_match = re.search(r"(?:最近|近|过去)\s*(7|30)\s*天", normalized)
    if day_match is not None:
        days = int(day_match.group(1))
        return TimeRange(from_at=local_now - timedelta(days=days), to_at=local_now)
    return None


def time_range_options(
    *,
    now: datetime,
    timezone_name: str,
) -> list[TimeRangeOption]:
    zone = ZoneInfo(timezone_name)
    local_now = _aware_utc(now).astimezone(zone)
    month_start = datetime.combine(
        local_now.date().replace(day=1),
        time.min,
        tzinfo=zone,
    )
    week_start = datetime.combine(
        local_now.date() - timedelta(days=local_now.weekday()),
        time.min,
        tzinfo=zone,
    )
    return [
        TimeRangeOption(
            id="last_7_days",
            label="过去 7 天",
            time_range=TimeRange(
                from_at=local_now - timedelta(days=7),
                to_at=local_now,
            ),
        ),
        TimeRangeOption(
            id="last_30_days",
            label="过去 30 天",
            time_range=TimeRange(
                from_at=local_now - timedelta(days=30),
                to_at=local_now,
            ),
        ),
        TimeRangeOption(
            id="current_month",
            label="本月",
            time_range=TimeRange(from_at=month_start, to_at=local_now),
        ),
        TimeRangeOption(
            id="current_week",
            label="本周",
            time_range=TimeRange(
                from_at=week_start,
                to_at=week_start + timedelta(days=7),
            ),
        ),
        TimeRangeOption(id="custom", label="自定义"),
    ]


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
    period = (
        resolve_report_period(intent, now=now, timezone_name=timezone_name)
        if adapter_kind == "period_summary"
        else None
    )
    return ReportScopeDraft(
        adapter_kind=adapter_kind,
        primary_reference=(
            EvidenceReference(kind="event", id=trigger_event_id)
            if trigger_event_id is not None
            else None
        ),
        time_range=period,
        missing_dimensions=(
            ["time_range"]
            if adapter_kind == "period_summary" and period is None
            else []
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
            match_terms, identity_match_terms, match_specs = _skill_match_terms(skill)
            group = ScopeRecordGroup(
                skill_id=skill.id,
                machine_name=skill.machine_name,
                match_terms=match_terms,
                identity_match_terms=identity_match_terms,
                match_specs=match_specs,
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


@dataclass(frozen=True)
class _GroupTermMatch:
    skill_id: str
    term: str
    provenance: Literal["identity", "broad"]
    is_alias: bool
    start: int
    end: int


def _group_term_matches(
    groups: list[ScopeRecordGroup],
    intent: str,
) -> tuple[str, list[_GroupTermMatch]]:
    normalized_intent = _normalize_term(intent)
    matches = [
        _GroupTermMatch(
            skill_id=group.skill_id,
            term=spec.value,
            provenance=spec.provenance,
            is_alias=spec.is_alias,
            start=start,
            end=end,
        )
        for group in groups
        for spec in group.match_specs
        for start, end in _term_match_spans(spec.value, normalized_intent)
    ]
    explicit_identity_spans = [
        match
        for match in matches
        if match.provenance == "identity" and not match.is_alias
    ]
    return normalized_intent, [
        match
        for match in matches
        if not any(
            explicit.start <= match.start
            and match.end <= explicit.end
            and (explicit.end - explicit.start) > (match.end - match.start)
            for explicit in explicit_identity_spans
        )
    ]


def _additively_related(
    first: _GroupTermMatch,
    second: _GroupTermMatch,
    normalized_intent: str,
) -> bool:
    if first.end <= second.start:
        between = normalized_intent[first.end : second.start]
    elif second.end <= first.start:
        between = normalized_intent[second.end : first.start]
    else:
        return False
    return _ADDITIVE_RELATION.search(between) is not None


def _filter_record_groups_for_intent(
    groups: list[ScopeRecordGroup],
    intent: str,
) -> list[ScopeRecordGroup]:
    normalized_intent, matches = _group_term_matches(groups, intent)
    identity_matches = [
        match for match in matches if match.provenance == "identity"
    ]
    broad_matches = [match for match in matches if match.provenance == "broad"]
    if identity_matches:
        selected_ids = {match.skill_id for match in identity_matches}
        selected_ids.update(
            broad.skill_id
            for broad in broad_matches
            if any(
                _additively_related(broad, identity, normalized_intent)
                for identity in identity_matches
            )
        )
    else:
        selected_ids = {match.skill_id for match in broad_matches}
    return [group for group in groups if group.skill_id in selected_ids] or groups


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
    options: list[TimeRangeOption] = []
    if adapter_kind == "pre_event_briefing":
        events = await _future_events(
            session,
            user_id=user_id,
            now=now,
            timezone_name=timezone_name,
        )
    elif adapter_kind == "period_summary":
        options = time_range_options(
            now=now,
            timezone_name=timezone_name,
        )
        period = draft.time_range or options[1].time_range
        assert period is not None
        record_groups = await _period_records(
            session,
            user_id=user_id,
            period=period,
            timezone_name=timezone_name,
        )
        record_groups = _filter_record_groups_for_intent(record_groups, intent)
        auto_references = (
            [
                record.reference
                for group in record_groups
                for record in group.records
            ]
            if draft.time_range is not None
            else []
        )
        draft = draft.model_copy(
            update={
                "skill_ids": [group.skill_id for group in record_groups],
                "supporting_references": auto_references,
                "selection": ReportAssetSelection(
                    auto_references=auto_references,
                ),
            }
        )
    return ReportScopeCandidateResponse(
        adapter_kind=adapter_kind,
        events=events,
        record_groups=record_groups,
        time_range_options=options,
        default_scope=draft,
    )
