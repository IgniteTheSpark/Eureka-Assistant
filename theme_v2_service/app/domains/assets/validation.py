from __future__ import annotations

from enum import StrEnum
from typing import Any


class AssetPayloadInvalid(ValueError):
    pass


class AssetWriteProfile(StrEnum):
    manual = "manual"
    agent = "agent"


def normalize_payload_schema(schema_json: dict | None) -> dict:
    schema = schema_json if isinstance(schema_json, dict) else {}
    properties = schema.get("properties")
    if isinstance(properties, dict):
        return {
            **schema,
            "type": schema.get("type", "object"),
            "properties": properties,
            "additionalProperties": schema.get("additionalProperties", True),
        }

    shorthand_properties = {
        name: definition
        for name, definition in schema.items()
        if isinstance(definition, dict) and not name.startswith("x-")
    }
    required = [
        name
        for name, definition in shorthand_properties.items()
        if definition.get("required") is True
    ]
    return {
        "type": "object",
        "properties": shorthand_properties,
        "required": required,
        "additionalProperties": False,
        **{key: value for key, value in schema.items() if key.startswith("x-")},
    }


def _matches_type(value: Any, expected: str) -> bool:
    if expected == "null":
        return value is None
    if expected == "string":
        return isinstance(value, str)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    return True


def _validate_value(value: Any, schema: dict, path: str) -> None:
    expected = schema.get("type")
    expected_types = expected if isinstance(expected, list) else [expected]
    concrete_types = [item for item in expected_types if isinstance(item, str)]
    if concrete_types and not any(_matches_type(value, item) for item in concrete_types):
        raise AssetPayloadInvalid(f"{path} has invalid type")
    if isinstance(schema.get("enum"), list) and value not in schema["enum"]:
        raise AssetPayloadInvalid(f"{path} is not an allowed value")
    if isinstance(value, list) and isinstance(schema.get("items"), dict):
        for index, item in enumerate(value):
            _validate_value(item, schema["items"], f"{path}[{index}]")
    if isinstance(value, dict) and isinstance(schema.get("properties"), dict):
        _validate_object(value, schema, path)


def _validate_object(payload: dict, schema: dict, path: str) -> None:
    properties = schema.get("properties") or {}
    required = schema.get("required") or []
    if not isinstance(required, list):
        raise AssetPayloadInvalid("skill schema required must be a list")
    for name in required:
        if name not in payload:
            raise AssetPayloadInvalid(f"{path}.{name} is required")
    if schema.get("additionalProperties") is False:
        unknown = next((name for name in payload if name not in properties), None)
        if unknown is not None:
            raise AssetPayloadInvalid(f"{path}.{unknown} is not defined by the skill")
    for name, value in payload.items():
        definition = properties.get(name)
        if isinstance(definition, dict):
            _validate_value(value, definition, f"{path}.{name}")


def validate_asset_payload(
    payload: dict,
    schema_json: dict | None,
    *,
    profile: AssetWriteProfile = AssetWriteProfile.manual,
) -> None:
    if not isinstance(payload, dict):
        raise AssetPayloadInvalid("payload must be an object")
    schema = normalize_payload_schema(schema_json)
    if schema.get("type") != "object":
        raise AssetPayloadInvalid("skill schema root must be an object")
    if profile == AssetWriteProfile.agent:
        # Agent extraction is intentionally best-effort for custom skills.
        # Missing fields and additional source-grounded keys must not discard a
        # physical capture. Known fields still receive type/enum validation so
        # we never silently coerce or invent values.
        properties = schema.get("properties") or {}
        for name, value in payload.items():
            definition = properties.get(name)
            if isinstance(definition, dict):
                _validate_value(value, definition, f"payload.{name}")
        return
    _validate_object(payload, schema, "payload")
