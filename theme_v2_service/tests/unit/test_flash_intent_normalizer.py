import pytest

from app.domains.capture.agent import CaptureSkill
from app.domains.capture.dispatcher import FlashIntent
from app.domains.capture.intent_normalizer import normalize_intents


def test_splits_multiple_expenses_into_atomic_intents():
    normalized = normalize_intents(
        [
            FlashIntent(
                type="expense",
                domain="生活",
                source_text="午饭 38 元，咖啡 25 元",
            )
        ],
        custom_skill_names=set(),
    )

    assert [intent.source_text for intent in normalized] == [
        "午饭 38 元",
        "咖啡 25 元",
    ]
    assert [intent.operation for intent in normalized] == ["create", "create"]
    assert [intent.ordinal for intent in normalized] == [0, 1]
    assert [intent.intent_id for intent in normalized] == ["intent-0", "intent-1"]


def test_infers_operation_when_dispatcher_omits_or_mislabels_it():
    normalized = normalize_intents(
        [
            FlashIntent(
                type="expense",
                operation="create",
                source_text="帮我看看最近花了多少钱",
            ),
            FlashIntent(
                type="expense",
                operation="create",
                source_text="把刚刚账单从 10 块改成 8 块",
            ),
            FlashIntent(
                type="todo",
                operation="create",
                source_text="删除刚刚那个代办",
            ),
            FlashIntent(
                type="qa",
                operation="create",
                source_text="地球为什么是圆的",
            ),
        ],
        custom_skill_names=set(),
    )

    assert [intent.operation for intent in normalized] == [
        "query",
        "update",
        "delete",
        "answer",
    ]
    assert [intent.ordinal for intent in normalized] == [0, 1, 2, 3]
    assert [intent.intent_id for intent in normalized] == [
        "intent-0",
        "intent-1",
        "intent-2",
        "intent-3",
    ]


def test_scheduled_future_activity_cannot_be_stolen_by_custom_record_skill():
    normalized = normalize_intents(
        [
            FlashIntent(
                type="running_training",
                domain="运动",
                source_text="明天下午 3 点跑步训练",
            )
        ],
        custom_skill_names={"running_training"},
    )

    assert normalized[0].type == "todo"


@pytest.mark.parametrize(
    "source_text",
    ["今天中午12点和张总吃饭", "明天和张总吃饭", "和张总吃饭"],
)
def test_single_point_date_or_undated_builtin_event_becomes_todo(source_text):
    normalized = normalize_intents(
        [FlashIntent(type="event", source_text=source_text)],
        custom_skill_names=set(),
    )

    assert normalized[0].type == "todo"


@pytest.mark.parametrize(
    "source_text",
    ["两点到两点半见投资人", "下午四点开始开两个小时周会", "明天全天团建"],
)
def test_range_duration_or_all_day_builtin_todo_becomes_event(source_text):
    normalized = normalize_intents(
        [FlashIntent(type="todo", source_text=source_text)],
        custom_skill_names=set(),
    )

    assert normalized[0].type == "event"


def test_legacy_free_form_aliases_collapse_to_notes():
    normalized = normalize_intents(
        [
            FlashIntent(type="idea", domain="灵感", source_text="做客户标签"),
            FlashIntent(type="misc", domain="生活", source_text="天气很好"),
            FlashIntent(type="other", domain="生活", source_text="随手记"),
        ],
        custom_skill_names=set(),
    )

    assert [intent.type for intent in normalized] == ["notes", "notes", "notes"]


def _custom(
    user_skill_id: str,
    machine_name: str,
    display_name: str,
) -> CaptureSkill:
    return CaptureSkill(
        user_skill_id=user_skill_id,
        machine_name=machine_name,
        display_name=display_name,
        description=f"记录{display_name}",
        schema_definition={"summary": {"type": "string"}},
    )


def test_routes_custom_skill_by_stable_id_display_name_and_unique_prefix():
    skills = (
        _custom("skill-running", "running_training", "跑步训练"),
        _custom("skill-water", "water_intake", "喝水记录"),
    )
    normalized = normalize_intents(
        [
            FlashIntent(
                type="notes",
                custom_skill_id="skill-running",
                source_text="今天跑了五公里",
            ),
            FlashIntent(type="跑步训练", source_text="今天跑了六公里"),
            FlashIntent(type="water", source_text="刚刚喝了 300 毫升水"),
        ],
        custom_skill_names=set(),
        custom_skills=skills,
    )

    assert [intent.type for intent in normalized] == [
        "running_training",
        "running_training",
        "water_intake",
    ]
    assert [intent.custom_skill_id for intent in normalized] == [
        "skill-running",
        "skill-running",
        "skill-water",
    ]


def test_confident_custom_skill_match_wins_over_notes_fallback():
    normalized = normalize_intents(
        [FlashIntent(type="notes", source_text="记录一次跑步训练，完成 5 公里")],
        custom_skill_names=set(),
        custom_skills=(
            _custom("skill-running", "running_training", "跑步训练"),
        ),
    )

    assert normalized[0].type == "running_training"
    assert normalized[0].custom_skill_id == "skill-running"


def test_completed_custom_activity_recovers_from_todo_misclassification():
    normalized = normalize_intents(
        [
            FlashIntent(
                type="todo",
                domain="运动",
                source_text="昨天晚上去ABC舞社跳了一个舞，跳的是hiphop",
            )
        ],
        custom_skill_names=set(),
        custom_skills=(
            _custom("skill-dance", "dance_log", "跳舞记录"),
        ),
    )

    assert normalized[0].type == "dance_log"
    assert normalized[0].custom_skill_id == "skill-dance"


def test_explicit_future_custom_activity_remains_a_todo():
    normalized = normalize_intents(
        [
            FlashIntent(
                type="todo",
                domain="运动",
                source_text="提醒我明天下午去ABC舞社跳舞",
            )
        ],
        custom_skill_names=set(),
        custom_skills=(
            _custom("skill-dance", "dance_log", "跳舞记录"),
        ),
    )

    assert normalized[0].type == "todo"
    assert normalized[0].custom_skill_id is None


def test_ungrounded_expense_is_demoted_to_notes_without_custom_skill():
    normalized = normalize_intents(
        [
            FlashIntent(
                type="expense",
                domain="健康",
                source_text="昨天晚上喝水了160ml",
            )
        ],
        custom_skill_names=set(),
    )

    assert normalized[0].type == "notes"
    assert normalized[0].source_text == "昨天晚上喝水了160ml"


def test_ungrounded_expense_can_recover_to_unique_custom_record_skill():
    normalized = normalize_intents(
        [
            FlashIntent(
                type="expense",
                domain="健康",
                source_text="昨天晚上喝水了160ml",
            )
        ],
        custom_skill_names=set(),
        custom_skills=(
            _custom("skill-water", "water_intake", "喝水记录"),
        ),
    )

    assert normalized[0].type == "water_intake"
    assert normalized[0].custom_skill_id == "skill-water"


def test_natural_quantity_phrasing_routes_each_note_to_custom_skill():
    normalized = normalize_intents(
        [
            FlashIntent(
                type="notes",
                domain="健康",
                source_text="刚刚还喝了123ml的水",
            ),
            FlashIntent(
                type="notes",
                domain="健康",
                source_text="昨天晚上11点多，也喝了80ml的水",
            ),
        ],
        custom_skill_names=set(),
        custom_skills=(
            _custom("skill-water", "daily_water_intake", "喝水记录"),
            _custom("skill-milk", "milk_intake", "喝奶记录"),
        ),
    )

    assert [intent.type for intent in normalized] == [
        "daily_water_intake",
        "daily_water_intake",
    ]
    assert [intent.custom_skill_id for intent in normalized] == [
        "skill-water",
        "skill-water",
    ]


def test_semantically_duplicate_custom_displays_remain_ambiguous():
    normalized = normalize_intents(
        [FlashIntent(type="notes", source_text="刚刚喝了123ml的水")],
        custom_skill_names=set(),
        custom_skills=(
            _custom("skill-water-record", "water_record", "喝水记录"),
            _custom("skill-water-log", "water_log", "喝水日志"),
        ),
    )

    assert normalized[0].type == "notes"
    assert normalized[0].custom_skill_id is None
    assert normalized[0].routing_error == "custom_skill_ambiguous"


def test_expense_with_source_evidence_is_not_demoted():
    normalized = normalize_intents(
        [
            FlashIntent(type="expense", source_text="今天早餐花了25块钱"),
            FlashIntent(type="expense", source_text="把刚刚账单改成8块"),
            FlashIntent(type="expense", source_text="帮我看看最近花了多少钱"),
        ],
        custom_skill_names=set(),
    )

    assert [intent.type for intent in normalized] == [
        "expense",
        "expense",
        "expense",
    ]


def test_ambiguous_custom_prefix_is_not_silently_saved_as_notes():
    normalized = normalize_intents(
        [FlashIntent(type="跑步", source_text="记录跑步")],
        custom_skill_names=set(),
        custom_skills=(
            _custom("skill-road", "road_running", "公路跑步"),
            _custom("skill-trail", "trail_running", "越野跑步"),
        ),
    )

    assert normalized[0].routing_error == "custom_skill_ambiguous"
    assert normalized[0].custom_skill_id is None
