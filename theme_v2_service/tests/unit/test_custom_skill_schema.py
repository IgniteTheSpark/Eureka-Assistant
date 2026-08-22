from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from app.domains.assets.schemas import UserSkillUpdate
from app.domains.assets.skill_schema import (
    SkillUpdateConflict,
    normalized_custom_skill_schema,
    validate_custom_skill_create_schema,
    validate_custom_skill_update,
)


def _skill(*, global_skill_id=None, machine_name="tennis", schema=None, updated_at=None):
    return SimpleNamespace(
        global_skill_id=global_skill_id,
        machine_name=machine_name,
        schema_json=schema
        or {
            "type": "object",
            "properties": {
                "duration": {"type": "number", "title": "时长"},
            },
            "required": [],
        },
        updated_at=updated_at or datetime(2026, 8, 18, 8, 0, 0),
    )


def test_custom_skill_schema_allows_relabel_hide_reorder_and_new_optional_field():
    skill = _skill(
        schema={
            "type": "object",
            "properties": {
                "duration": {"type": "number", "title": "时长"},
                "notes": {"type": "string", "title": "备注"},
            },
            "required": [],
        }
    )
    command = UserSkillUpdate(
        schema={
            "type": "object",
            "properties": {
                "notes": {"type": "string", "title": "训练感受", "x-hidden": True},
                "duration": {"type": "number", "title": "训练时长"},
                "location": {"type": "string", "title": "地点"},
            },
            "required": [],
        }
    )

    validate_custom_skill_update(skill, command)
    normalized = normalized_custom_skill_schema(command.schema_definition)

    assert list(normalized["properties"]) == ["notes", "duration", "location"]
    assert normalized["properties"]["notes"]["x-hidden"] is True
    assert normalized["required"] == []


def test_custom_skill_schema_allows_deleting_fields_including_the_last_field():
    skill = _skill(
        schema={
            "type": "object",
            "properties": {
                "duration": {"type": "number", "title": "时长"},
                "location": {"type": "string", "title": "地点"},
            },
            "required": [],
        }
    )

    validate_custom_skill_update(
        skill,
        UserSkillUpdate(
            schema={
                "type": "object",
                "properties": {
                    "location": {"type": "string", "title": "地点"},
                },
                "required": [],
            }
        ),
    )
    validate_custom_skill_update(
        _skill(),
        UserSkillUpdate(
            schema={"type": "object", "properties": {}, "required": []}
        ),
    )


@pytest.mark.parametrize(
    ("schema", "code"),
    [
        (
            {
                "type": "object",
                "properties": {"duration": {"type": "string", "title": "时长"}},
            },
            "field_type_changed",
        ),
        (
            {
                "type": "object",
                "properties": {
                    "duration": {
                        "type": "number",
                        "format": "duration",
                        "title": "时长",
                    }
                },
            },
            "field_format_changed",
        ),
    ],
)
def test_custom_skill_schema_rejects_incompatible_changes(schema, code):
    with pytest.raises(SkillUpdateConflict) as error:
        validate_custom_skill_update(_skill(), UserSkillUpdate(schema=schema))

    assert error.value.code == code


def test_system_skill_only_allows_card_render_configuration():
    validate_custom_skill_update(
        _skill(global_skill_id=42),
        UserSkillUpdate(render_spec={"card": {"title_field": "title"}}),
    )

    with pytest.raises(SkillUpdateConflict) as error:
        validate_custom_skill_update(
            _skill(global_skill_id=42),
            UserSkillUpdate(display_name="新的名字"),
        )

    assert error.value.code == "system_skill_protected"


def test_protected_machine_name_is_system_even_without_catalog_fk():
    with pytest.raises(SkillUpdateConflict) as error:
        validate_custom_skill_update(
            _skill(machine_name="expense"),
            UserSkillUpdate(display_name="伪装成自定义消费"),
        )

    assert error.value.code == "system_skill_protected"


@pytest.mark.parametrize(
    "schema",
    [
        {"type": "array", "properties": {}},
        {"type": "object", "properties": []},
        {
            "type": "object",
            "properties": {"Bad-Key": {"type": "string"}},
        },
        {
            "type": "object",
            "properties": {"value": {"type": "binary"}},
        },
        {
            "type": "object",
            "properties": {"value": {"type": "number", "format": "date"}},
        },
        {
            "type": "object",
            "properties": {"tags": {"type": "array", "items": "string"}},
        },
    ],
)
def test_custom_skill_update_rejects_malformed_complete_schema(schema):
    with pytest.raises(SkillUpdateConflict) as error:
        validate_custom_skill_update(_skill(), UserSkillUpdate(schema=schema))

    assert error.value.code == "invalid_skill_schema"


def test_custom_skill_update_rejects_new_required_fields():
    schema = {
        "type": "object",
        "properties": {
            "duration": {"type": "number"},
            "location": {"type": "string"},
        },
        "required": ["location"],
    }

    with pytest.raises(SkillUpdateConflict) as error:
        validate_custom_skill_update(_skill(), UserSkillUpdate(schema=schema))

    assert error.value.code == "new_field_required"


def test_legacy_shorthand_keeps_json_schema_keyword_field_names_compatible():
    validate_custom_skill_create_schema(
        {
            "type": {"type": "string"},
            "properties": {"type": "boolean"},
            "required": {"type": "boolean"},
        }
    )


def test_skill_update_rejects_stale_revision_with_timezone_normalization():
    with pytest.raises(SkillUpdateConflict) as error:
        validate_custom_skill_update(
            _skill(updated_at=datetime(2026, 8, 18, 8, 0, 0)),
            UserSkillUpdate(
                display_name="网球记录",
                expected_updated_at=datetime(2026, 8, 18, 8, 0, 1, tzinfo=timezone.utc),
            ),
        )

    assert error.value.code == "stale_skill_revision"
