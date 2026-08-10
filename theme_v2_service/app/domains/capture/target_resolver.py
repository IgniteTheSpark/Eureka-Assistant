from __future__ import annotations

from dataclasses import dataclass
from dataclasses import replace
import re
from typing import Any, Literal, Sequence

from sqlalchemy import exists, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset, Contact, Event, UserSkill
from app.domains.sessions.models import InputTurn, SessionMessage


TargetResolutionStatus = Literal["resolved", "ambiguous", "not_found"]
_RECENT_REFERENCE_RE = re.compile(
    r"(刚刚|刚才|方才|那个|那条|那笔|上一(?:个|条|笔)|前一(?:个|条|笔))"
)


@dataclass(frozen=True)
class TargetCandidate:
    entity_id: str
    entity_type: str
    source: str
    snapshot: dict[str, Any]


@dataclass(frozen=True)
class TargetResolution:
    status: TargetResolutionStatus
    entity_id: str | None = None
    entity_type: str | None = None
    source: str | None = None
    candidates: tuple[TargetCandidate, ...] = ()


def resolve_target_candidates(
    *,
    explicit: Sequence[TargetCandidate],
    prior_turn: Sequence[TargetCandidate],
    result_card: Sequence[TargetCandidate],
    exact: Sequence[TargetCandidate],
    safe: Sequence[TargetCandidate],
) -> TargetResolution:
    for candidates in (explicit, prior_turn, result_card, exact, safe):
        stable = tuple(candidates)
        if len(stable) == 1:
            candidate = stable[0]
            return TargetResolution(
                status="resolved",
                entity_id=candidate.entity_id,
                entity_type=candidate.entity_type,
                source=candidate.source,
                candidates=stable,
            )
        if len(stable) > 1:
            return TargetResolution(
                status="ambiguous",
                source=stable[0].source,
                candidates=stable,
            )
    return TargetResolution(status="not_found")


def _asset_candidate(asset: Asset, skill: UserSkill, source: str) -> TargetCandidate:
    return TargetCandidate(
        entity_id=asset.id,
        entity_type=skill.machine_name,
        source=source,
        snapshot={
            "asset_id": asset.id,
            "user_skill_name": skill.machine_name,
            "payload": dict(asset.payload_json or {}),
        },
    )


def _contact_candidate(contact: Contact, source: str) -> TargetCandidate:
    return TargetCandidate(
        entity_id=contact.id,
        entity_type="contact",
        source=source,
        snapshot={
            "contact_id": contact.id,
            "name": contact.name,
            "company": contact.company,
            "title": contact.title,
        },
    )


def _event_candidate(event: Event, source: str) -> TargetCandidate:
    return TargetCandidate(
        entity_id=event.id,
        entity_type="event",
        source=source,
        snapshot={
            "event_id": event.id,
            "title": event.title,
            "start_at": event.start_at.isoformat(),
            "end_at": event.end_at.isoformat(),
        },
    )


async def _owned_candidate(
    database: AsyncSession,
    *,
    user_id: str,
    entity_type: str,
    entity_id: str,
    source: str,
) -> TargetCandidate | None:
    if entity_type == "contact":
        contact = await database.scalar(
            select(Contact).where(
                Contact.id == entity_id,
                Contact.user_id == user_id,
            )
        )
        return _contact_candidate(contact, source) if contact is not None else None
    if entity_type == "event":
        event = await database.scalar(
            select(Event).where(
                Event.id == entity_id,
                Event.user_id == user_id,
            )
        )
        return _event_candidate(event, source) if event is not None else None
    row = (
        await database.execute(
            select(Asset, UserSkill)
            .join(UserSkill, UserSkill.id == Asset.user_skill_id)
            .where(
                Asset.id == entity_id,
                Asset.user_id == user_id,
                Asset.migrated_contact_id.is_(None),
                UserSkill.user_id == user_id,
                UserSkill.machine_name == entity_type,
            )
        )
    ).first()
    return _asset_candidate(*row, source) if row is not None else None


async def _candidates_for_type(
    database: AsyncSession,
    *,
    user_id: str,
    entity_type: str,
    source: str,
    source_input_turn_id: str | None = None,
    limit: int = 100,
) -> list[TargetCandidate]:
    if entity_type == "contact":
        query = select(Contact).where(Contact.user_id == user_id)
        if source_input_turn_id is not None:
            query = query.where(Contact.source_input_turn_id == source_input_turn_id)
        contacts = list(
            await database.scalars(
                query.order_by(Contact.created_at.desc(), Contact.id.desc()).limit(limit)
            )
        )
        return [_contact_candidate(item, source) for item in contacts]
    if entity_type == "event":
        query = select(Event).where(Event.user_id == user_id)
        if source_input_turn_id is not None:
            query = query.where(Event.source_input_turn_id == source_input_turn_id)
        events = list(
            await database.scalars(
                query.order_by(Event.created_at.desc(), Event.id.desc()).limit(limit)
            )
        )
        return [_event_candidate(item, source) for item in events]

    query = (
        select(Asset, UserSkill)
        .join(UserSkill, UserSkill.id == Asset.user_skill_id)
        .where(
            Asset.user_id == user_id,
            Asset.migrated_contact_id.is_(None),
            UserSkill.user_id == user_id,
            UserSkill.machine_name == entity_type,
        )
    )
    if source_input_turn_id is not None:
        query = query.where(Asset.source_input_turn_id == source_input_turn_id)
    rows = (
        await database.execute(
            query.order_by(Asset.created_at.desc(), Asset.id.desc()).limit(limit)
        )
    ).all()
    return [_asset_candidate(asset, skill, source) for asset, skill in rows]


async def _prior_turn_candidates(
    database: AsyncSession,
    *,
    user_id: str,
    session_id: str,
    input_turn_id: str,
    entity_type: str,
) -> list[TargetCandidate]:
    current = await database.scalar(
        select(InputTurn).where(
            InputTurn.id == input_turn_id,
            InputTurn.user_id == user_id,
            InputTurn.session_id == session_id,
        )
    )
    if current is None:
        return []
    completed = exists(
        select(SessionMessage.id).where(
            SessionMessage.input_turn_id == InputTurn.id,
            SessionMessage.user_id == user_id,
            SessionMessage.session_id == session_id,
            SessionMessage.role == "agent",
            SessionMessage.status == "done",
        )
    )
    turns = list(
        await database.scalars(
            select(InputTurn)
            .where(
                InputTurn.user_id == user_id,
                InputTurn.session_id == session_id,
                InputTurn.turn_index < current.turn_index,
                completed,
            )
            .order_by(InputTurn.turn_index.desc())
        )
    )
    for turn in turns:
        candidates = await _candidates_for_type(
            database,
            user_id=user_id,
            entity_type=entity_type,
            source="prior_input_turn",
            source_input_turn_id=turn.id,
        )
        if candidates:
            return candidates
    return []


async def _result_card_candidates(
    database: AsyncSession,
    *,
    user_id: str,
    session_id: str,
    input_turn_id: str,
    entity_type: str,
) -> list[TargetCandidate]:
    current = await database.scalar(
        select(InputTurn).where(
            InputTurn.id == input_turn_id,
            InputTurn.user_id == user_id,
            InputTurn.session_id == session_id,
        )
    )
    if current is None:
        return []
    messages = list(
        await database.scalars(
            select(SessionMessage)
            .join(InputTurn, SessionMessage.input_turn_id == InputTurn.id)
            .where(
                SessionMessage.user_id == user_id,
                SessionMessage.session_id == session_id,
                SessionMessage.role == "agent",
                SessionMessage.status == "done",
                InputTurn.turn_index < current.turn_index,
            )
            .order_by(InputTurn.turn_index.desc(), SessionMessage.created_at.desc())
        )
    )
    for message in messages:
        candidates: list[TargetCandidate] = []
        for card in message.cards_json or []:
            if not isinstance(card, dict):
                continue
            card_kind = str(card.get("entity_kind") or "")
            skill_name = str(card.get("skill_machine_name") or "")
            if entity_type == "event" and card_kind != "event":
                continue
            if entity_type == "contact" and card_kind != "contact":
                continue
            if entity_type not in {"event", "contact"} and (
                card_kind != "asset" or skill_name != entity_type
            ):
                continue
            candidate = await _owned_candidate(
                database,
                user_id=user_id,
                entity_type=entity_type,
                entity_id=str(card.get("entity_id") or ""),
                source="result_card",
            )
            if candidate is not None:
                candidates.append(candidate)
        if candidates:
            return candidates
    return []


def _normalized_text(value: Any) -> str:
    return re.sub(r"\s+", "", str(value or "")).casefold()


def _exact_match(candidate: TargetCandidate, query: str) -> bool:
    target = _normalized_text(query)
    if not target:
        return False
    snapshot = candidate.snapshot
    values: list[Any]
    if candidate.entity_type == "contact":
        values = [snapshot.get("name"), snapshot.get("company"), snapshot.get("title")]
    elif candidate.entity_type == "event":
        values = [snapshot.get("title")]
    else:
        payload = snapshot.get("payload")
        values = list(payload.values()) if isinstance(payload, dict) else []
    return any(_normalized_text(value) == target for value in values)


def _source_identifier_match(
    candidate: TargetCandidate,
    source_text: str,
) -> bool:
    """Match only stable human-facing identifiers explicitly present in input."""
    source = _normalized_text(source_text)
    if not source:
        return False
    snapshot = candidate.snapshot
    if candidate.entity_type == "contact":
        identifiers = [snapshot.get("name")]
    elif candidate.entity_type == "event":
        identifiers = [snapshot.get("title")]
    else:
        payload = snapshot.get("payload")
        identifiers = (
            [payload.get(key) for key in ("title", "name", "content")]
            if isinstance(payload, dict)
            else []
        )
    normalized = [
        _normalized_text(value)
        for value in identifiers
        if len(_normalized_text(value)) >= 2
    ]
    return any(identifier in source for identifier in normalized)


async def resolve_capture_target(
    database: AsyncSession,
    *,
    user_id: str,
    session_id: str | None,
    input_turn_id: str | None,
    entity_type: str,
    source_text: str,
    explicit_id: str | None = None,
    target_query: str | None = None,
) -> TargetResolution:
    if not entity_type.strip():
        return TargetResolution(status="not_found")

    if explicit_id:
        candidate = await _owned_candidate(
            database,
            user_id=user_id,
            entity_type=entity_type,
            entity_id=explicit_id,
            source="explicit_id",
        )
        if candidate is None:
            return TargetResolution(status="not_found", source="explicit_id")
        return resolve_target_candidates(
            explicit=[candidate],
            prior_turn=[],
            result_card=[],
            exact=[],
            safe=[],
        )

    recent_reference = bool(_RECENT_REFERENCE_RE.search(source_text))
    prior: list[TargetCandidate] = []
    cards: list[TargetCandidate] = []
    if recent_reference and session_id and input_turn_id:
        prior = await _prior_turn_candidates(
            database,
            user_id=user_id,
            session_id=session_id,
            input_turn_id=input_turn_id,
            entity_type=entity_type,
        )
        if not prior:
            cards = await _result_card_candidates(
                database,
                user_id=user_id,
                session_id=session_id,
                input_turn_id=input_turn_id,
                entity_type=entity_type,
            )

    all_candidates = await _candidates_for_type(
        database,
        user_id=user_id,
        entity_type=entity_type,
        source="safe_candidate",
        limit=100,
    )
    exact = [
        replace(candidate, source="exact_match")
        for candidate in all_candidates
        if (
            (bool(target_query) and _exact_match(candidate, target_query))
            or _source_identifier_match(candidate, source_text)
        )
    ]
    # An explicit semantic target that matched nothing must remain not-found.
    # Falling back to arbitrary recent entities here can turn a precise delete
    # request into a confirmation for unrelated assets (or a wrong mutation
    # when only one entity of that type exists).
    safe = [] if (target_query or "").strip() else all_candidates[:2]
    return resolve_target_candidates(
        explicit=[],
        prior_turn=prior,
        result_card=cards,
        exact=exact,
        safe=safe,
    )
