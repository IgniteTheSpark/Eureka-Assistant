from __future__ import annotations

from datetime import date, datetime, time, timezone
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.db.models import Asset, Event, UserSkill
from app.domains.capture.models import CaptureRecording, CaptureTurn


_UTC = timezone.utc


def _utc_aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=_UTC)
    return value.astimezone(_UTC)


def _iso_z(value: datetime | None) -> str | None:
    if value is None:
        return None
    return _utc_aware(value).isoformat().replace("+00:00", "Z")


def _parse_semantic_time(value: Any, *, zone: ZoneInfo) -> datetime | None:
    if isinstance(value, datetime):
        return _utc_aware(value)
    if isinstance(value, date):
        return datetime.combine(value, time.min, tzinfo=zone).astimezone(_UTC)
    if not isinstance(value, str) or not value.strip():
        return None
    raw = value.strip()
    try:
        if len(raw) == 10 and raw[4] == "-" and raw[7] == "-":
            local_date = date.fromisoformat(raw)
            return datetime.combine(local_date, time.min, tzinfo=zone).astimezone(_UTC)
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=zone)
    return parsed.astimezone(_UTC)


def _schema_properties(schema: dict) -> dict:
    properties = schema.get("properties")
    if isinstance(properties, dict):
        return properties
    return {
        key: value
        for key, value in schema.items()
        if isinstance(value, dict) and not key.startswith("x-")
    }


def _schema_time_anchor(skill: UserSkill) -> str | None:
    render_spec = skill.render_spec_json or {}
    anchor = render_spec.get("timeline_anchor")
    if isinstance(anchor, str) and anchor.strip():
        return anchor.strip()
    properties = _schema_properties(skill.schema_json or {})
    for preferred in ("date", "due_date", "run_date", "played_at", "occurred_at"):
        definition = properties.get(preferred)
        if isinstance(definition, dict) and definition.get("type") == "string":
            return preferred
    for name, definition in properties.items():
        if isinstance(definition, dict) and definition.get("format") in {
            "date",
            "date-time",
        }:
            return name
    return None


def effective_at_for_asset(
    asset: Asset,
    skill: UserSkill,
    *,
    timezone_name: str,
) -> datetime:
    zone = ZoneInfo(timezone_name)
    payload = asset.payload_json or {}
    if asset.occurred_at is not None:
        return _utc_aware(asset.occurred_at)
    if asset.effective_at is not None:
        return _utc_aware(asset.effective_at)
    anchor = _schema_time_anchor(skill)
    if anchor:
        anchored = _parse_semantic_time(payload.get(anchor), zone=zone)
        if anchored is not None:
            return anchored
    if skill.machine_name == "todo":
        due = _parse_semantic_time(payload.get("due_date"), zone=zone)
        if due is not None:
            return due
    if skill.machine_name == "expense":
        for field in ("at", "date"):
            expense_time = _parse_semantic_time(payload.get(field), zone=zone)
            if expense_time is not None:
                return expense_time
    return _utc_aware(asset.created_at)


def _format_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "是" if value else "否"
    if isinstance(value, (dict, list)):
        return ""
    return str(value).strip()


def _asset_title(asset: Asset, skill: UserSkill) -> str:
    payload = asset.payload_json or {}
    for field in ("title", "content", "name"):
        value = _format_value(payload.get(field))
        if value:
            return value[:120]

    render_spec = skill.render_spec_json or {}
    primary = render_spec.get("primary_field")
    primary_value = _format_value(payload.get(primary)) if isinstance(primary, str) else ""
    if not primary_value and payload.get("amount") not in (None, ""):
        primary_value = _format_value(payload.get("amount"))
    if primary_value:
        unit = _format_value(render_spec.get("primary_unit"))
        value = " ".join(part for part in (primary_value, unit) if part)
        if skill.machine_name in {"todo", "notes", "contact"}:
            return value[:120]
        return f"{skill.display_name} · {value}"[:120]
    return skill.display_name[:120]


def _asset_subtitle(asset: Asset, skill: UserSkill) -> str:
    payload = asset.payload_json or {}
    render_spec = skill.render_spec_json or {}
    secondary = render_spec.get("secondary_field")
    candidates = [payload.get(secondary)] if isinstance(secondary, str) else []
    candidates.extend((payload.get("description"), payload.get("note"), payload.get("merchant")))
    for value in candidates:
        formatted = _format_value(value)
        if formatted:
            return formatted[:120]
    return ""


def _todo_due_has_clock(payload: dict) -> bool:
    due = payload.get("due_date")
    return isinstance(due, str) and "T" in due


def _local_date(value: datetime, *, zone: ZoneInfo) -> str:
    return _utc_aware(value).astimezone(zone).date().isoformat()


async def assemble_timeline(
    session: AsyncSession,
    user_id: str,
    *,
    timezone_name: str,
    limit: int = 500,
) -> list[dict]:
    zone = ZoneInfo(timezone_name)
    items: list[dict] = []
    asset_rows = (
        await session.execute(
            select(Asset, UserSkill)
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .where(Asset.user_id == user_id)
        )
    ).all()
    events = list(
        await session.scalars(
            select(Event)
            .options(selectinload(Event.attendees))
            .where(Event.user_id == user_id, Event.status != "cancelled")
        )
    )
    capture_rows = (
        await session.execute(
            select(CaptureRecording, CaptureTurn)
            .outerjoin(CaptureTurn, CaptureTurn.recording_id == CaptureRecording.id)
            .where(
                CaptureRecording.user_id == user_id,
                CaptureRecording.source != "typed",
            )
        )
    ).all()

    asset_sources: dict[str, tuple[CaptureRecording, CaptureTurn | None]] = {}
    event_sources: dict[str, tuple[CaptureRecording, CaptureTurn | None]] = {}
    for recording, turn in capture_rows:
        for reference in recording.result_records_json or []:
            if not isinstance(reference, dict):
                continue
            if reference.get("kind") == "asset" and reference.get("asset_id"):
                asset_sources[str(reference["asset_id"])] = (recording, turn)
            elif reference.get("kind") == "event" and reference.get("event_id"):
                event_sources[str(reference["event_id"])] = (recording, turn)

    for asset, skill in asset_rows:
        effective = effective_at_for_asset(
            asset,
            skill,
            timezone_name=timezone_name,
        )
        source = asset_sources.get(asset.id)
        source_recording, source_turn = source if source else (None, None)
        payload = asset.payload_json or {}
        has_clock = asset.occurred_at is not None or (
            asset.effective_at is not None
            and isinstance(payload.get(_schema_time_anchor(skill) or ""), str)
            and "T" in str(payload.get(_schema_time_anchor(skill) or ""))
        )
        items.append(
            {
                "kind": "asset",
                "id": asset.id,
                "effective_at": _iso_z(effective),
                "created_at": _iso_z(asset.created_at),
                "title": _asset_title(asset, skill),
                "subtitle": _asset_subtitle(asset, skill),
                "skill_name": skill.machine_name,
                "user_skill_id": skill.id,
                "period": asset.period or "",
                "has_clock_time": has_clock,
                "has_scheduled_time": asset.occurred_at is not None
                or (skill.machine_name == "todo" and _todo_due_has_clock(payload)),
                "domain": skill.domain or "",
                "payload": payload,
                "session_id": _local_date(
                    source_recording.capture_started_at or source_recording.created_at,
                    zone=zone,
                )
                if source_recording
                else None,
                "source_recording_id": source_recording.id if source_recording else None,
                "source_input_turn_id": source_turn.id if source_turn else None,
            }
        )

    for event in events:
        source = event_sources.get(event.id)
        source_recording, source_turn = source if source else (None, None)
        attendees = [
            {
                "id": attendee.id,
                "contact_id": attendee.contact_id,
                "name_raw": attendee.name_raw,
                "display_name": attendee.name_raw,
                "is_resolved": attendee.contact_id is not None,
                "contact_summary": "",
                "role": attendee.role,
            }
            for attendee in event.attendees
        ]
        payload = {
            "event_id": event.id,
            "title": event.title,
            "description": event.description,
            "location": event.location,
            "start_at": _iso_z(event.start_at),
            "end_at": _iso_z(event.end_at),
            "all_day": event.all_day,
            "attendees": attendees,
        }
        items.append(
            {
                "kind": "event",
                "id": event.id,
                "event_id": event.id,
                "effective_at": _iso_z(event.start_at),
                "created_at": _iso_z(event.created_at),
                "end_at": _iso_z(event.end_at),
                "title": event.title,
                "subtitle": event.location or "",
                "location": event.location,
                "all_day": event.all_day,
                "attendees": attendees,
                "payload": payload,
                "session_id": _local_date(
                    source_recording.capture_started_at or source_recording.created_at,
                    zone=zone,
                )
                if source_recording
                else None,
                "source_recording_id": source_recording.id if source_recording else None,
                "source_input_turn_id": source_turn.id if source_turn else None,
            }
        )

    for recording, turn in capture_rows:
        captured_at = recording.capture_started_at or recording.created_at
        transcript = (turn.transcript if turn else recording.asr_text or "").strip()
        items.append(
            {
                "kind": "input_turn",
                "id": turn.id if turn else recording.id,
                "effective_at": _iso_z(captured_at),
                "created_at": _iso_z(recording.created_at),
                "title": (transcript[:80] or "闪念"),
                "subtitle": "",
                "source": recording.source,
                "session_id": _local_date(captured_at, zone=zone),
                "source_recording_id": recording.id,
                "file_id": recording.file_id,
                "derived": {},
                "derived_total": len(recording.result_records_json or []),
                "payload": {
                    "process_status": recording.process_status,
                    "session_date": _local_date(captured_at, zone=zone),
                },
            }
        )

    items.sort(
        key=lambda item: (
            item.get("effective_at") or "",
            item.get("created_at") or "",
            item["id"],
        )
    )
    return items[-limit:]
