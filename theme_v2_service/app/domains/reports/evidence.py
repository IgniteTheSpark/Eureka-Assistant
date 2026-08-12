from datetime import datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset, Contact, Event, EventAttendee
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.schemas import (
    EvidenceReference,
    ReportExecutionPlan,
    TimeRange,
)
from app.domains.reports.templates import TemplateRegistry


class InsufficientEvidence(ValueError):
    pass


class EvidenceModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class EvidenceItem(EvidenceModel):
    kind: str = "asset"
    reference_id: str
    asset_id: str | None = None
    skill_id: str | None = None
    effective_at: datetime
    payload: dict
    bound_fields: dict[str, Any] = Field(default_factory=dict)
    temporal_facts: "EvidenceTemporalFacts | None" = None


class EvidenceTemporalFacts(EvidenceModel):
    timezone: str
    local_date: str
    local_start_time: str
    local_end_time: str
    local_interval_text: str
    duration_minutes: int = Field(ge=0)


class EvidenceBundle(EvidenceModel):
    user_evidence: list[EvidenceItem]
    derived_metrics: dict[str, Any] = Field(default_factory=dict)
    unavailable_asset_ids: list[str]
    unavailable_references: list[dict[str, str]] = Field(default_factory=list)
    field_bindings: dict[str, str]
    time_range: TimeRange | None
    report_goal: str
    template: dict[str, str]
    launch_context: dict = Field(default_factory=dict)


MAX_GROUPED_DIMENSIONS = 8
MAX_GROUP_VALUES = 50
MAX_GROUPED_NUMERIC_FIELDS = 8
MAX_METRIC_LABEL_CHARS = 120


def _resolve_path(asset: Asset, path: str) -> Any:
    if path == "effective_at":
        return asset.effective_at or asset.created_at
    if path.startswith("fields."):
        path = f"payload.{path.removeprefix('fields.')}"
    elif "." not in path:
        path = f"payload.{path}"
    if not path.startswith("payload."):
        return None
    value: Any = asset.payload_json
    for part in path.removeprefix("payload.").split("."):
        if not isinstance(value, dict) or part not in value:
            return None
        value = value[part]
    return value


def _metric_values(
    item: EvidenceItem,
    *,
    zone: ZoneInfo,
) -> dict[str, Any]:
    values = dict(item.bound_fields)
    bound_suffixes = {
        name.rsplit(".", 1)[-1]
        for name, value in item.bound_fields.items()
        if value is not None
    }
    for name, value in sorted(item.payload.items()):
        if (
            not isinstance(name, str)
            or (name in values and values[name] is not None)
            or name in bound_suffixes
            or not isinstance(value, (str, int, float, bool))
            or (
                isinstance(value, str)
                and (not value.strip() or len(value) > MAX_METRIC_LABEL_CHARS)
            )
        ):
            continue
        values[name] = value
    effective_at = item.effective_at
    if effective_at.tzinfo is None:
        effective_at = effective_at.replace(tzinfo=timezone.utc)
    values["effective_date"] = effective_at.astimezone(zone).date().isoformat()
    return values


def _rounded_values(value: float) -> dict[str, int | float]:
    return {
        "rounded_0": round(value),
        "rounded_1": round(value, 1),
        "rounded_2": round(value, 2),
    }


def _derived_metrics(
    evidence: list[EvidenceItem],
    *,
    timezone_name: str = "Asia/Shanghai",
) -> dict[str, Any]:
    zone = ZoneInfo(timezone_name)
    item_values = [(item, _metric_values(item, zone=zone)) for item in evidence]
    fields: dict[str, dict[str, Any]] = {}
    bound_names = sorted(
        {
            name
            for item in evidence
            for name, value in item.bound_fields.items()
            if value is not None
        }
    )
    discovered_names = sorted(
        {
            name
            for _item, values in item_values
            for name, value in values.items()
            if value is not None
        }.difference(bound_names)
    )
    metric_names = [*bound_names, *discovered_names]
    for name in metric_names:
        values = [
            item_value[name]
            for _item, item_value in item_values
            if item_value.get(name) is not None
        ]
        scalar_values = [
            value
            for value in values
            if isinstance(value, (str, int, float, bool))
        ]
        stats: dict[str, Any] = {"value_count": len(values)}
        if scalar_values:
            counts: dict[str, int] = {}
            for value in scalar_values:
                label = str(value)
                counts[label] = counts.get(label, 0) + 1
            stats["distinct_count"] = len(counts)
            stats["counts_by_value"] = counts
        numeric_values = [
            value
            for value in values
            if isinstance(value, (int, float)) and not isinstance(value, bool)
        ]
        if numeric_values:
            total = sum(numeric_values)
            stats.update(
                {
                    "sum": total,
                    "average": total / len(numeric_values),
                    "average_rounded": _rounded_values(
                        total / len(numeric_values)
                    ),
                    "minimum": min(numeric_values),
                    "maximum": max(numeric_values),
                }
            )
        fields[name] = stats

    numeric_field_names = [
        name
        for name in metric_names
        if any(
            isinstance(values.get(name), (int, float))
            and not isinstance(values.get(name), bool)
            for _item, values in item_values
        )
    ][:MAX_GROUPED_NUMERIC_FIELDS]
    available_dimensions = {
        name
        for name in metric_names
        if any(
            isinstance(values.get(name), (str, bool))
            for _item, values in item_values
        )
    }
    dimension_names = [
        name
        for name in [
            "effective_date",
            *bound_names,
            *discovered_names,
        ]
        if name in available_dimensions
    ][:MAX_GROUPED_DIMENSIONS]
    grouped_fields: dict[str, dict[str, Any]] = {}
    for dimension_name in dimension_names:
        groups: dict[str, list[EvidenceItem]] = {}
        for item, values in item_values:
            dimension_value = values.get(dimension_name)
            if not isinstance(dimension_value, (str, bool)):
                continue
            groups.setdefault(str(dimension_value), []).append(item)
        if not groups or len(groups) > MAX_GROUP_VALUES:
            continue
        grouped_fields[dimension_name] = {}
        for label in sorted(groups):
            group_items = groups[label]
            numeric_fields: dict[str, dict[str, Any]] = {}
            for numeric_name in numeric_field_names:
                values = [
                    value
                    for item, item_value in item_values
                    if item in group_items
                    if isinstance(
                        (value := item_value.get(numeric_name)),
                        (int, float),
                    )
                    and not isinstance(value, bool)
                ]
                if not values:
                    continue
                total_values = [
                    value
                    for _item, item_value in item_values
                    if isinstance(
                        (value := item_value.get(numeric_name)),
                        (int, float),
                    )
                    and not isinstance(value, bool)
                ]
                group_total = sum(values)
                total = sum(total_values)
                stats = {
                    "value_count": len(values),
                    "sum": group_total,
                    "average": group_total / len(values),
                    "average_rounded": _rounded_values(
                        group_total / len(values)
                    ),
                    "minimum": min(values),
                    "maximum": max(values),
                }
                if total:
                    percentage = group_total / total * 100
                    stats["share_of_total_percent"] = _rounded_values(percentage)
                numeric_fields[numeric_name] = stats
            grouped_fields[dimension_name][label] = {
                "record_count": len(group_items),
                "numeric_fields": numeric_fields,
            }

    grouped_field_summaries: dict[str, dict[str, Any]] = {}
    for dimension_name, groups in grouped_fields.items():
        numeric_summaries: dict[str, Any] = {}
        for numeric_name in numeric_field_names:
            group_sums = [
                numeric_fields[numeric_name]["sum"]
                for group in groups.values()
                if isinstance((numeric_fields := group["numeric_fields"]), dict)
                and numeric_name in numeric_fields
            ]
            if not group_sums:
                continue
            numeric_summaries[numeric_name] = {
                "group_count": len(group_sums),
                "average_group_sum": sum(group_sums) / len(group_sums),
                "average_group_sum_rounded": _rounded_values(
                    sum(group_sums) / len(group_sums)
                ),
                "minimum_group_sum": min(group_sums),
                "maximum_group_sum": max(group_sums),
            }
            try:
                ordered_group_sums = [
                    (
                        datetime.fromisoformat(label).date(),
                        label,
                        group["numeric_fields"][numeric_name]["sum"],
                    )
                    for label, group in groups.items()
                    if numeric_name in group["numeric_fields"]
                ]
            except ValueError:
                ordered_group_sums = []
            if len(ordered_group_sums) >= 2:
                ordered_group_sums.sort(key=lambda value: value[0])
                changes = []
                for previous, current in zip(
                    ordered_group_sums,
                    ordered_group_sums[1:],
                ):
                    delta = current[2] - previous[2]
                    change = {
                        "from": previous[1],
                        "to": current[1],
                        "delta": delta,
                        "absolute_delta": abs(delta),
                    }
                    if previous[2]:
                        percentage = delta / previous[2] * 100
                        change.update(
                            {
                                "percentage_change": percentage,
                                "percentage_change_rounded": _rounded_values(
                                    percentage
                                ),
                                "absolute_percentage_change": abs(percentage),
                                "absolute_percentage_change_rounded": (
                                    _rounded_values(abs(percentage))
                                ),
                            }
                        )
                    changes.append(change)
                numeric_summaries[numeric_name]["ordered_changes"] = changes
        grouped_field_summaries[dimension_name] = numeric_summaries

    return {
        "record_count": len(evidence),
        "counts_by_kind": {
            kind: sum(1 for item in evidence if item.kind == kind)
            for kind in sorted({item.kind for item in evidence})
        },
        "fields": fields,
        "grouped_fields": grouped_fields,
        "grouped_field_summaries": grouped_field_summaries,
    }


def _minimum_data_satisfied(
    *,
    run: ReportGenerationRun,
    available_count: int,
) -> bool:
    if available_count > 0:
        return True
    return bool(run.launch_context.get("event_id"))


async def load_latest_evidence(
    session: AsyncSession,
    *,
    run: ReportGenerationRun,
    execution_plan: ReportExecutionPlan,
    registry: TemplateRegistry,
    timezone_name: str = "Asia/Shanghai",
) -> EvidenceBundle:
    package = registry.get(
        execution_plan.template_id,
        execution_plan.template_version,
    )
    if package.manifest.base_family != execution_plan.base_family:
        raise InsufficientEvidence("execution plan does not match template")

    references: list[EvidenceReference] = []
    seen_references: set[tuple[str, str]] = set()
    for reference in [
        *execution_plan.resolved_references,
        *(
            EvidenceReference(kind="asset", id=asset_id)
            for asset_id in execution_plan.resolved_asset_ids
        ),
    ]:
        key = (reference.kind, reference.id)
        if key in seen_references:
            continue
        seen_references.add(key)
        references.append(reference)

    requested_ids = [ref.id for ref in references if ref.kind == "asset"]
    rows = []
    if requested_ids:
        rows = list(
            await session.scalars(
                select(Asset).where(
                    Asset.id.in_(requested_ids),
                    Asset.user_id == run.user_id,
                )
            )
        )
    by_id = {asset.id: asset for asset in rows}
    event_ids = [ref.id for ref in references if ref.kind == "event"]
    events = list(
        await session.scalars(
            select(Event).where(
                Event.id.in_(event_ids),
                Event.user_id == run.user_id,
            )
        )
    ) if event_ids else []
    events_by_id = {event.id: event for event in events}
    event_attendees: dict[str, list[dict[str, Any]]] = {
        event_id: [] for event_id in event_ids
    }
    if event_ids:
        attendee_rows = (
            await session.execute(
                select(EventAttendee, Contact)
                .outerjoin(
                    Contact,
                    (Contact.id == EventAttendee.contact_id)
                    & (Contact.user_id == run.user_id),
                )
                .where(EventAttendee.event_id.in_(event_ids))
                .order_by(EventAttendee.created_at, EventAttendee.id)
            )
        ).all()
        for attendee, contact in attendee_rows:
            event_attendees.setdefault(attendee.event_id, []).append(
                {
                    "contact_id": contact.id if contact is not None else None,
                    "name": contact.name if contact is not None else attendee.name_raw,
                    "role": attendee.role,
                    "company": contact.company if contact is not None else None,
                    "title": contact.title if contact is not None else None,
                }
            )

    contact_ids = [ref.id for ref in references if ref.kind == "contact"]
    contacts = list(
        await session.scalars(
            select(Contact).where(
                Contact.id.in_(contact_ids),
                Contact.user_id == run.user_id,
            )
        )
    ) if contact_ids else []
    contacts_by_id = {contact.id: contact for contact in contacts}
    evidence: list[EvidenceItem] = []
    unavailable: list[str] = []
    unavailable_references: list[dict[str, str]] = []
    zone = ZoneInfo(timezone_name)
    for reference in references:
        if reference.kind == "asset":
            asset = by_id.get(reference.id)
            if asset is None:
                unavailable.append(reference.id)
                unavailable_references.append(reference.model_dump())
                continue
            evidence.append(
                EvidenceItem(
                    kind="asset",
                    reference_id=asset.id,
                    asset_id=asset.id,
                    skill_id=asset.user_skill_id,
                    effective_at=asset.effective_at or asset.created_at,
                    payload=asset.payload_json,
                    bound_fields={
                        binding: _resolve_path(asset, source)
                        for binding, source in execution_plan.field_bindings.items()
                    },
                )
            )
            continue
        if reference.kind == "event":
            event = events_by_id.get(reference.id)
            if event is None:
                unavailable_references.append(reference.model_dump())
                continue
            utc_start = (
                event.start_at
                if event.start_at.tzinfo is not None
                else event.start_at.replace(tzinfo=timezone.utc)
            ).astimezone(timezone.utc)
            utc_end = (
                event.end_at
                if event.end_at.tzinfo is not None
                else event.end_at.replace(tzinfo=timezone.utc)
            ).astimezone(timezone.utc)
            local_start = utc_start.astimezone(zone)
            local_end = utc_end.astimezone(zone)
            local_start_text = local_start.strftime("%H:%M")
            local_end_text = local_end.strftime("%H:%M")
            evidence.append(
                EvidenceItem(
                    kind="event",
                    reference_id=event.id,
                    effective_at=local_start,
                    payload={
                        "title": event.title,
                        "description": event.description,
                        "location": event.location,
                        "start_at": local_start,
                        "end_at": local_end,
                        "all_day": event.all_day,
                        "status": event.status,
                        "attendees": event_attendees.get(event.id, []),
                    },
                    temporal_facts=EvidenceTemporalFacts(
                        timezone=timezone_name,
                        local_date=local_start.date().isoformat(),
                        local_start_time=local_start_text,
                        local_end_time=local_end_text,
                        local_interval_text=(
                            f"{local_start_text}–{local_end_text}"
                        ),
                        duration_minutes=max(
                            0,
                            int((utc_end - utc_start).total_seconds() // 60),
                        ),
                    ),
                )
            )
            continue
        contact = contacts_by_id.get(reference.id)
        if contact is None:
            unavailable_references.append(reference.model_dump())
            continue
        evidence.append(
            EvidenceItem(
                kind="contact",
                reference_id=contact.id,
                effective_at=contact.created_at,
                payload={
                    "name": contact.name,
                    "phone": contact.phone,
                    "company": contact.company,
                    "title": contact.title,
                    "email": contact.email,
                    "notes": contact.notes_json,
                    "socials": contact.socials_json,
                },
            )
        )

    if not _minimum_data_satisfied(run=run, available_count=len(evidence)):
        raise InsufficientEvidence(
            f"template {package.manifest.id} minimum data is not satisfied"
        )
    return EvidenceBundle(
        user_evidence=evidence,
        derived_metrics=_derived_metrics(evidence, timezone_name=timezone_name),
        unavailable_asset_ids=unavailable,
        unavailable_references=unavailable_references,
        field_bindings=execution_plan.field_bindings,
        time_range=execution_plan.time_range,
        report_goal=execution_plan.report_goal,
        template={
            "id": package.manifest.id,
            "version": package.manifest.version,
        },
        launch_context=dict(run.launch_context),
    )
