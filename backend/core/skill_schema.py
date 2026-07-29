"""Strict schema contract shared by Skill authoring and runtime consumers."""

from __future__ import annotations

from typing import Any


def validate_payload_schema(schema: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if not isinstance(schema, dict) or not schema:
        raise ValueError("payload_schema must be a non-empty object")

    validated: dict[str, dict[str, Any]] = {}
    for order, (field_id, raw) in enumerate(schema.items()):
        if not isinstance(field_id, str) or not field_id.strip():
            raise ValueError("payload_schema field id is required")
        if not isinstance(raw, dict):
            raise ValueError(f"{field_id} must be an object")

        field = dict(raw)
        field_type = field.get("type")
        if not isinstance(field_type, str) or not field_type.strip():
            raise ValueError(f"{field_id}.type is required")
        label = field.get("label")
        if not isinstance(label, str) or not label.strip():
            raise ValueError(f"{field_id}.label is required")
        if not isinstance(field.get("required"), bool):
            raise ValueError(f"{field_id}.required must be boolean")
        if not isinstance(field.get("long"), bool):
            raise ValueError(f"{field_id}.long must be boolean")
        if field["long"] and field_type != "string":
            raise ValueError(f"{field_id}.long requires type=string")

        field["label"] = label.strip()
        field["order"] = order
        validated[field_id] = field

    return validated
