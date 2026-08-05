from app.domains.assets.skill_design import _normalize_draft


def test_custom_skill_draft_forces_generated_fields_optional():
    draft = _normalize_draft(
        {
            "name": "running_log",
            "display_name": "跑步记录",
            "payload_schema": {
                "distance": {
                    "type": "number",
                    "label": "距离",
                    "required": True,
                },
                "duration": {
                    "type": "integer",
                    "label": "时长",
                    "required": True,
                },
            },
            "render_spec": {"primary_field": "distance"},
        },
        "记录跑步",
    )

    assert draft["payload_schema"]["distance"]["required"] is False
    assert draft["payload_schema"]["duration"]["required"] is False
    assert draft["render_spec"]["primary_field"] == "distance"
