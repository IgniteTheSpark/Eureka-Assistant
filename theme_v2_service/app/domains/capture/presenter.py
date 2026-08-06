from __future__ import annotations

from collections.abc import Iterable
from typing import Any


_BUILTIN_ICONS = {
    "todo": "📋",
    "event": "📅",
    "contact": "👤",
    "notes": "✍️",
    "expense": "💳",
}


def present_capture_references(
    references: list[dict[str, Any]],
    *,
    skills: Iterable[Any],
) -> list[dict[str, Any]]:
    """Add durable Theme V2 display snapshots without removing live references."""
    skill_by_name = {
        str(skill.machine_name): skill
        for skill in skills
        if getattr(skill, "machine_name", None)
    }
    cards: list[dict[str, Any]] = []
    for raw in references:
        reference = dict(raw)
        kind = str(reference.get("kind") or "")
        if kind == "asset":
            cards.append(_present_asset(reference, skill_by_name))
        elif kind == "event":
            cards.append(_present_event(reference))
        elif kind == "contact":
            cards.append(_present_contact(reference))
        elif kind == "pending_contact":
            cards.append(
                {
                    **reference,
                    "card_type": "pending_contact",
                    "icon": _BUILTIN_ICONS["contact"],
                    "accent_color": reference.get("accent_color") or "neutral",
                    "card_layout": reference.get("card_layout") or "horizontal",
                }
            )
        else:
            cards.append(reference)
    return cards


def _present_asset(reference: dict[str, Any], skills: dict[str, Any]) -> dict:
    machine_name = str(reference.get("skill_machine_name") or "asset")
    skill = skills.get(machine_name)
    render = dict(getattr(skill, "render_spec_json", None) or {})
    payload = dict(reference.get("payload") or {})
    display_name = str(getattr(skill, "display_name", None) or machine_name)
    primary_field = str(
        render.get("primary_field")
        or _default_primary_field(machine_name, payload)
        or ""
    )
    title = _asset_title(machine_name, payload, primary_field, display_name)
    subtitle = _asset_subtitle(machine_name, payload, primary_field)
    icon = _BUILTIN_ICONS.get(machine_name) or str(render.get("icon") or "•")
    return {
        **reference,
        "card_type": machine_name,
        "user_skill_name": machine_name,
        "payload": payload,
        "title": title,
        "subtitle": subtitle,
        "icon": icon,
        "accent_color": str(render.get("accent_color") or "gray"),
        "card_layout": str(render.get("card_layout") or "horizontal"),
        "domain": reference.get("domain") or getattr(skill, "domain", None),
        "meta_fields": _meta_fields(payload, render),
        "actions": list(render.get("actions") or []),
    }


def _present_event(reference: dict[str, Any]) -> dict[str, Any]:
    subtitle = str(reference.get("subtitle") or "")
    if not subtitle:
        start = str(reference.get("start_at") or "")
        end = str(reference.get("end_at") or "")
        location = str(reference.get("location") or "")
        subtitle = " · ".join(value for value in (start, end, location) if value)
    return {
        **reference,
        "card_type": "event",
        "title": str(reference.get("title") or "日程"),
        "subtitle": subtitle,
        "icon": _BUILTIN_ICONS["event"],
        "accent_color": reference.get("accent_color") or "blue",
        "card_layout": reference.get("card_layout") or "horizontal",
    }


def _present_contact(reference: dict[str, Any]) -> dict[str, Any]:
    summary = " · ".join(
        str(value)
        for value in (reference.get("company"), reference.get("title"))
        if value
    )
    return {
        **reference,
        "card_type": "contact",
        "title": str(reference.get("name") or reference.get("title") or "联系人"),
        "subtitle": summary or str(reference.get("subtitle") or ""),
        "icon": _BUILTIN_ICONS["contact"],
        "accent_color": reference.get("accent_color") or "neutral",
        "card_layout": reference.get("card_layout") or "horizontal",
    }


def _default_primary_field(machine_name: str, payload: dict[str, Any]) -> str | None:
    preferred = {
        "todo": ("title", "content"),
        "expense": ("amount", "description", "category"),
        "notes": ("title", "content"),
    }.get(machine_name, ())
    for field in (*preferred, *payload.keys()):
        if _displayable(payload.get(field)):
            return field
    return None


def _asset_title(
    machine_name: str,
    payload: dict[str, Any],
    primary_field: str,
    display_name: str,
) -> str:
    value = payload.get(primary_field)
    if machine_name == "expense" and primary_field == "amount" and value is not None:
        currency = str(payload.get("currency") or "CNY")
        return f"{_scalar(value)} {currency}".strip()
    if _displayable(value):
        return _scalar(value)
    return display_name


def _asset_subtitle(
    machine_name: str,
    payload: dict[str, Any],
    primary_field: str,
) -> str:
    priorities = {
        "expense": ("category", "merchant", "description"),
        "todo": ("due_date", "content"),
        "notes": ("content",),
    }.get(machine_name, ())
    for field in (*priorities, *payload.keys()):
        if field == primary_field:
            continue
        value = payload.get(field)
        if _displayable(value) and field not in {
            "currency",
            "status",
            "domain",
            "period",
            "occurred_at",
        }:
            return _scalar(value)
    return ""


def _meta_fields(payload: dict[str, Any], render: dict[str, Any]) -> list[dict]:
    values: list[dict] = []
    for item in render.get("meta_fields") or []:
        if not isinstance(item, dict):
            continue
        field = str(item.get("field") or "")
        value = payload.get(field)
        if not _displayable(value):
            continue
        values.append(
            {
                "value": _scalar(value),
                "format": item.get("format"),
            }
        )
    return values


def _displayable(value: Any) -> bool:
    return value is not None and value != "" and value != [] and value != {}


def _scalar(value: Any) -> str:
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    if isinstance(value, list):
        return "、".join(str(item) for item in value)
    return str(value)
