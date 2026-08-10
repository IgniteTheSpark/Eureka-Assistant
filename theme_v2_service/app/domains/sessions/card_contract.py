from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any, Literal


logger = logging.getLogger(__name__)

SessionCardEntityKind = Literal["asset", "event", "contact"]
SessionCardSourceKind = Literal["capture", "chat", "report"]


class SessionCardInvalid(ValueError):
    pass


@dataclass(frozen=True)
class SessionCardSource:
    session_id: str
    input_turn_id: str
    kind: SessionCardSourceKind

    def __post_init__(self) -> None:
        if not self.session_id.strip():
            raise SessionCardInvalid("source session_id is required")
        if not self.input_turn_id.strip():
            raise SessionCardInvalid("source input_turn_id is required")
        if self.kind not in {"capture", "chat", "report"}:
            raise SessionCardInvalid(f"unsupported source kind: {self.kind}")

    def as_dict(self) -> dict[str, str]:
        return {
            "session_id": self.session_id,
            "input_turn_id": self.input_turn_id,
            "kind": self.kind,
        }


def build_entity_card(
    *,
    entity_kind: SessionCardEntityKind | str,
    entity_id: str,
    entity: dict[str, Any],
    source: SessionCardSource,
    skill_machine_name: str | None = None,
) -> dict[str, Any]:
    if entity_kind not in {"asset", "event", "contact"}:
        raise SessionCardInvalid(f"unsupported entity kind: {entity_kind}")
    normalized_id = str(entity_id or "").strip()
    if not normalized_id:
        raise SessionCardInvalid("entity_id is required")
    if not isinstance(entity, dict):
        raise SessionCardInvalid("entity must be an object")
    normalized_skill = str(skill_machine_name or "").strip()
    if entity_kind == "asset" and not normalized_skill:
        raise SessionCardInvalid("asset skill_machine_name is required")

    card: dict[str, Any] = {
        "entity_kind": entity_kind,
        "entity_id": normalized_id,
        "entity": dict(entity),
        "source": source.as_dict(),
    }
    if entity_kind == "asset":
        card["skill_machine_name"] = normalized_skill
    return card


def cards_from_tool_result(
    name: str,
    result: dict[str, Any],
    source: SessionCardSource,
) -> list[dict[str, Any]]:
    if not result.get("ok") or name.startswith("tool_delete_"):
        return []

    candidates: list[tuple[str, str, dict[str, Any], str | None]] = []
    if result.get("asset_id") and isinstance(result.get("payload"), dict):
        candidates.append(
            (
                "asset",
                str(result["asset_id"]),
                _raw_entity(result),
                str(result.get("user_skill_name") or ""),
            )
        )
    elif result.get("event_id"):
        candidates.append(
            ("event", str(result["event_id"]), _raw_entity(result), None)
        )
    elif result.get("contact_id") and result.get("name"):
        candidates.append(
            ("contact", str(result["contact_id"]), _raw_entity(result), None)
        )
    else:
        candidates.extend(_list_candidates(result, "assets", "asset", "asset_id"))
        candidates.extend(_list_candidates(result, "events", "event", "event_id"))
        candidates.extend(
            _list_candidates(result, "contacts", "contact", "contact_id")
        )

    cards: list[dict[str, Any]] = []
    for entity_kind, entity_id, entity, skill_name in candidates:
        try:
            cards.append(
                build_entity_card(
                    entity_kind=entity_kind,
                    entity_id=entity_id,
                    entity=entity,
                    source=source,
                    skill_machine_name=skill_name,
                )
            )
        except SessionCardInvalid:
            logger.warning(
                "session entity card was not persisted",
                exc_info=True,
                extra={
                    "tool_name": name,
                    "entity_kind": entity_kind,
                    "entity_id": entity_id,
                },
            )
    return cards


def _raw_entity(value: dict[str, Any]) -> dict[str, Any]:
    return {key: item for key, item in value.items() if key not in {"ok", "error"}}


def _list_candidates(
    result: dict[str, Any],
    list_key: str,
    entity_kind: SessionCardEntityKind,
    id_key: str,
) -> list[tuple[str, str, dict[str, Any], str | None]]:
    candidates: list[tuple[str, str, dict[str, Any], str | None]] = []
    for raw in result.get(list_key) or []:
        if not isinstance(raw, dict):
            continue
        entity_id = str(raw.get(id_key) or "").strip()
        skill_name = (
            str(raw.get("user_skill_name") or "").strip()
            if entity_kind == "asset"
            else None
        )
        candidates.append((entity_kind, entity_id, dict(raw), skill_name))
    return candidates
