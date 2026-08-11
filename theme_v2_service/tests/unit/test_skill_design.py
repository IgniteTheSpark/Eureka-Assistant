import json
from types import SimpleNamespace

import pytest

from app.domains.assets.skill_design import (
    InvalidSkillDraft,
    _normalize_design_step,
    _normalize_draft,
    design_skill_step,
)


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


def test_custom_skill_draft_normalizes_named_fire_icon_to_emoji():
    draft = _normalize_draft(
        {
            "name": "calorie_log",
            "display_name": "卡路里记录",
            "payload_schema": {
                "calories": {"type": "number", "label": "卡路里"},
                "food_name": {"type": "string", "label": "食物"},
            },
            "render_spec": {
                "icon": "fire",
                "primary_field": "food_name",
            },
        },
        "记录每天摄入的卡路里",
    )

    assert draft["render_spec"]["icon"] == "🔥"


def test_custom_skill_design_step_keeps_scope_and_recording_content_questions():
    result = _normalize_design_step(
        {
            "questions": [
                {
                    "key": "beverage_scope",
                    "prompt": "你希望记录哪些饮品？",
                    "type": "choice",
                    "options": [
                        "仅记录白水",
                        "记录所有无酒精饮品",
                        "仅记录白水",
                        "自定义范围",
                    ],
                },
                {
                    "key": "recording_content",
                    "prompt": "每次最想记录哪些内容？",
                    "type": "text",
                    "placeholder": "例如：舞种、时长、地点和感受",
                },
            ]
        },
        "喝水记录",
        answers=[],
    )

    assert result == {
        "questions": [
            {
                "key": "beverage_scope",
                "prompt": "你希望记录哪些饮品？",
                "type": "choice",
                "multiple": False,
                "options": [
                    "仅记录白水",
                    "记录所有无酒精饮品",
                    "自定义范围",
                ],
                "placeholder": "请选择记录范围",
            },
            {
                "key": "recording_content",
                "prompt": "每次最想记录哪些内容？",
                "type": "choice",
                "multiple": True,
                "options": ["类型", "时长", "地点", "感受"],
                "placeholder": "请输入其他想记录的内容",
            },
        ]
    }


def test_custom_skill_design_step_accepts_live_provider_question_alias():
    result = _normalize_design_step(
        {
            "questions": [
                {
                    "question": "您主要想记录哪些饮品？",
                    "options": ["仅白水", "所有无酒精饮品"],
                }
            ]
        },
        "喝水记录",
        answers=[],
    )

    assert result["questions"][0] == {
        "key": "recording_scope",
        "prompt": "您主要想记录哪些饮品？",
        "type": "choice",
        "multiple": False,
        "options": ["仅白水", "所有无酒精饮品"],
        "placeholder": "请选择记录范围",
    }
    assert result["questions"][1]["key"] == "recording_content"
    assert result["questions"][1]["type"] == "choice"
    assert result["questions"][1]["multiple"] is True


def test_custom_skill_design_step_adds_recording_content_when_provider_only_asks_scope():
    result = _normalize_design_step(
        {
            "questions": [
                {
                    "key": "recording_scope",
                    "prompt": "主要记录日常训练、课程还是比赛？",
                    "type": "choice",
                    "options": ["日常训练", "课程", "比赛"],
                }
            ]
        },
        "跳舞记录",
        answers=[],
    )

    assert [question["key"] for question in result["questions"]] == [
        "recording_scope",
        "recording_content",
    ]
    assert result["questions"][1] == {
        "key": "recording_content",
        "prompt": "每次记录时，你最想保留哪些内容？",
        "type": "choice",
        "multiple": True,
        "options": ["类型", "时长", "地点", "感受"],
        "placeholder": "请输入其他想记录的内容",
    }


def test_custom_skill_design_step_rejects_a_second_question_after_scope_answer():
    with pytest.raises(InvalidSkillDraft, match="question after scope confirmation"):
        _normalize_design_step(
            {
                "questions": [
                    {
                        "key": "another_scope",
                        "prompt": "还要记录什么？",
                        "type": "choice",
                        "options": ["选项一", "选项二"],
                    }
                ]
            },
            "喝水记录",
            answers=[{"key": "beverage_scope", "value": "仅记录白水"}],
        )


def test_custom_skill_draft_normalizes_hidden_semantic_routing_profile():
    result = _normalize_design_step(
        {
            "draft": {
                "name": "daily_water_intake",
                "display_name": "喝水记录",
                "description": "记录实际喝下的白水",
                "payload_schema": {
                    "amount_ml": {
                        "type": "number",
                        "label": "饮水量",
                        "description": "实际喝下的毫升数",
                    }
                },
                "render_spec": {
                    "icon": "💧",
                    "primary_field": "amount_ml",
                },
                "routing_profile": {
                    "intent": "记录用户实际喝下的白水",
                    "aliases": ["喝水", " 饮水 ", "喝水"],
                    "include": ["白水", "矿泉水", "纯净水"],
                    "exclude": ["咖啡", "茶", "购买水", "提醒喝水"],
                    "positive_examples": ["刚喝了500毫升水"],
                    "negative_examples": ["买矿泉水花了6块"],
                    "ignored_provider_key": "must not survive",
                },
            }
        },
        "喝水记录",
        answers=[{"key": "beverage_scope", "value": "仅记录白水"}],
    )

    draft = result["draft"]
    assert draft["description"] == "记录实际喝下的白水"
    assert draft["routing_profile"] == {
        "intent": "记录用户实际喝下的白水",
        "aliases": ["喝水", "饮水"],
        "include": ["白水", "矿泉水", "纯净水"],
        "exclude": ["咖啡", "茶", "购买水", "提醒喝水"],
        "positive_examples": ["刚喝了500毫升水"],
        "negative_examples": ["买矿泉水花了6块"],
    }


async def test_skill_designer_uses_deterministic_temperature(monkeypatch):
    captured = {}

    async def completion(**kwargs):
        captured.update(kwargs)
        return {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "draft": {
                                    "name": "running_log",
                                    "display_name": "跑步记录",
                                    "payload_schema": {
                                        "distance": {
                                            "type": "number",
                                            "label": "距离",
                                        }
                                    },
                                    "render_spec": {"primary_field": "distance"},
                                }
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }

    monkeypatch.setattr(
        "app.domains.assets.skill_design.get_settings",
        lambda: SimpleNamespace(
            capture_agent_enabled=True,
            capture_agent_model="deepseek/deepseek-chat",
            capture_agent_api_key="test-key",
            capture_agent_timeout_seconds=20,
        ),
    )
    monkeypatch.setattr(
        "app.domains.assets.skill_design.litellm.acompletion",
        completion,
    )

    await design_skill_step("记录已完成跑步", [])

    assert captured["temperature"] == 0
