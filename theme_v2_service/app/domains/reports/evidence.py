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
    unavailable_asset_ids: list[str]
    unavailable_references: list[dict[str, str]] = Field(default_factory=list)
    field_bindings: dict[str, str]
    time_range: TimeRange | None
    report_goal: str
    template: dict[str, str]
    launch_context: dict = Field(default_factory=dict)


def _resolve_path(asset: Asset, path: str) -> Any:
    if path == "effective_at":
        return asset.effective_at or asset.created_at
    if not path.startswith("payload."):
        return None
    value: Any = asset.payload_json
    for part in path.removeprefix("payload.").split("."):
        if not isinstance(value, dict) or part not in value:
            return None
        value = value[part]
    return value


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
