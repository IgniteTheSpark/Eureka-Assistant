import pytest

from app.domains.assets.validation import (
    AssetPayloadInvalid,
    normalize_payload_schema,
    validate_asset_payload,
)


def test_normalizes_legacy_shorthand_as_a_closed_object_schema():
    normalized = normalize_payload_schema(
        {
            "distance": {"type": "number"},
            "duration": {"type": "integer"},
            "x-capture-enabled": True,
        }
    )

    assert normalized["type"] == "object"
    assert set(normalized["properties"]) == {"distance", "duration"}
    assert normalized["additionalProperties"] is False


def test_closed_schema_rejects_unknown_payload_field():
    schema = {
        "type": "object",
        "properties": {"distance": {"type": "number"}},
        "required": ["distance"],
        "additionalProperties": False,
    }

    with pytest.raises(AssetPayloadInvalid, match="acceptance_marker"):
        validate_asset_payload(
            {"distance": 5, "acceptance_marker": "forbidden"},
            schema,
        )


def test_closed_schema_rejects_missing_and_wrong_typed_fields():
    schema = {
        "type": "object",
        "properties": {
            "distance": {"type": "number"},
            "duration": {"type": "integer"},
        },
        "required": ["distance"],
        "additionalProperties": False,
    }

    with pytest.raises(AssetPayloadInvalid, match="distance"):
        validate_asset_payload({}, schema)
    with pytest.raises(AssetPayloadInvalid, match="duration"):
        validate_asset_payload({"distance": 5, "duration": "30"}, schema)


def test_open_schema_preserves_forward_compatible_payload_fields():
    validate_asset_payload(
        {"content": "正文", "future_field": "保留"},
        {
            "type": "object",
            "properties": {"content": {"type": "string"}},
        },
    )
