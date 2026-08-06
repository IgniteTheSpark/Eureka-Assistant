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
