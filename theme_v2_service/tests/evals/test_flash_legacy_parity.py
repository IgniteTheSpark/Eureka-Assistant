import pytest

from app.domains.capture.dispatcher import FlashIntent
from app.domains.capture.intent_normalizer import normalize_intents


LEGACY_FLASH_CASES = [
    {
        "id": "multi_expense_hydration",
        "intents": [
            FlashIntent(type="expense", source_text="昨天早上吃饭8元"),
            FlashIntent(type="hydration", source_text="昨晚喝水200毫升"),
        ],
        "custom": {"hydration"},
        "types": ["expense", "hydration"],
    },
    {
        "id": "contact_create",
        "intents": [FlashIntent(type="contact", source_text="保存Alex，他在Acme做产品")],
        "custom": set(),
        "types": ["contact"],
    },
    {
        "id": "contact_update",
        "intents": [FlashIntent(type="contact", source_text="Alex的职业改成设计师")],
        "custom": set(),
        "types": ["contact"],
    },
    {
        "id": "event_attendee",
        "intents": [FlashIntent(type="event", source_text="明天下午三点到四点和冯总开会")],
        "custom": set(),
        "types": ["event"],
    },
    {
        "id": "single_point_todo",
        "intents": [FlashIntent(type="todo", source_text="明天下午三点和冯总开会")],
        "custom": set(),
        "types": ["todo"],
    },
    {
        "id": "notes_default",
        "intents": [FlashIntent(type="idea", source_text="产品应该更安静一点")],
        "custom": set(),
        "types": ["notes"],
    },
    {
        "id": "qa_no_write",
        "intents": [FlashIntent(type="qa", source_text="拿铁和美式有什么区别")],
        "custom": set(),
        "types": ["qa"],
    },
]


@pytest.mark.parametrize("case", LEGACY_FLASH_CASES, ids=lambda case: case["id"])
def test_legacy_intent_normalization_contract(case):
    normalized = normalize_intents(
        case["intents"],
        custom_skill_names=case["custom"],
    )

    assert [intent.type for intent in normalized] == case["types"]
    assert all(intent.source_text.strip() for intent in normalized)


@pytest.mark.parametrize("alias", ["idea", "misc", "other", "note"])
def test_free_text_aliases_converge_on_notes(alias: str):
    normalized = normalize_intents(
        [FlashIntent(type=alias, source_text="自由文本")],
        custom_skill_names=set(),
    )

    assert [intent.type for intent in normalized] == ["notes"]
