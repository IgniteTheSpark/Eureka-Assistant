import pytest

from app.domains.assets.validation import AssetPayloadInvalid, validate_asset_payload
from app.domains.capture.agent import (
    CaptureAgentResult,
    CaptureRecordCommand,
    CaptureSkill,
    validate_capture_result,
)


RUNNING_SCHEMA = {
    "type": "object",
    "properties": {
        "distance": {"type": "number"},
        "duration": {"type": "integer"},
        "run_date": {"type": "string"},
    },
    "required": ["distance", "duration", "run_date"],
    "additionalProperties": False,
}


def test_custom_agent_output_accepts_partial_payload_and_source_fallback():
    skill = CaptureSkill(
        machine_name="running_training_log",
        display_name="跑步训练",
        description="跑步训练记录",
        schema_definition=RUNNING_SCHEMA,
        enabled=True,
    )
    result = CaptureAgentResult(
        summary="已记录跑步。",
        records=[
            CaptureRecordCommand(
                kind="asset",
                skill_machine_name="running_training_log",
                payload={"distance": 2, "location": "深圳湾人才公园"},
                source_text="刚刚我跑了两公里，在深圳湾人才公园，感觉很不错。",
            )
        ],
    )

    assert validate_capture_result(result, [skill]) is result
    assert result.records[0].payload == {
        "distance": 2,
        "location": "深圳湾人才公园",
    }


def test_manual_write_keeps_strict_custom_schema_validation():
    with pytest.raises(AssetPayloadInvalid, match="duration is required"):
        validate_asset_payload(
            {"distance": 2, "location": "深圳湾人才公园"},
            RUNNING_SCHEMA,
        )
