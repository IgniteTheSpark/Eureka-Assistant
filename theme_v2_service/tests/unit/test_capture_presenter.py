from types import SimpleNamespace

from app.domains.capture.presenter import present_capture_references


def _skill(
    machine_name: str,
    display_name: str,
    *,
    icon: str = "•",
    primary_field: str | None = None,
):
    return SimpleNamespace(
        machine_name=machine_name,
        display_name=display_name,
        render_spec_json={
            "icon": icon,
            "accent_color": "gray",
            "card_layout": "horizontal",
            "primary_field": primary_field,
        },
    )


def test_presenter_pins_builtin_expense_icon_and_keeps_snapshot_payload():
    cards = present_capture_references(
        [
            {
                "kind": "asset",
                "asset_id": "expense-1",
                "skill_machine_name": "expense",
                "payload": {
                    "amount": 38,
                    "currency": "CNY",
                    "category": "餐饮",
                },
                "source_text": "咖啡三十八元",
            }
        ],
        skills=[_skill("expense", "消费", icon="🍔", primary_field="amount")],
    )

    assert cards[0]["card_type"] == "expense"
    assert cards[0]["icon"] == "💳"
    assert cards[0]["title"] == "38 CNY"
    assert cards[0]["subtitle"] == "餐饮"
    assert cards[0]["payload"]["amount"] == 38
    assert cards[0]["asset_id"] == "expense-1"


def test_presenter_pins_contact_icon_and_preserves_deleted_entity_snapshot():
    cards = present_capture_references(
        [
            {
                "kind": "contact",
                "contact_id": "alex-1",
                "name": "Alex",
                "company": "Acme",
                "title": "设计师",
                "icon": "🪪",
                "source_text": "Alex 的职业改成设计师",
            }
        ],
        skills=[],
    )

    assert cards[0]["card_type"] == "contact"
    assert cards[0]["icon"] == "👤"
    assert cards[0]["title"] == "Alex"
    assert cards[0]["subtitle"] == "Acme · 设计师"
    assert cards[0]["contact_id"] == "alex-1"


def test_presenter_preserves_custom_skill_icon_and_primary_field():
    cards = present_capture_references(
        [
            {
                "kind": "asset",
                "asset_id": "run-1",
                "skill_machine_name": "running_training_log",
                "payload": {"distance": 2, "location": "深圳湾"},
                "source_text": "跑了两公里",
            }
        ],
        skills=[
            _skill(
                "running_training_log",
                "跑步训练",
                icon="🏃",
                primary_field="distance",
            )
        ],
    )

    assert cards[0]["card_type"] == "running_training_log"
    assert cards[0]["icon"] == "🏃"
    assert cards[0]["title"] == "2"
    assert cards[0]["subtitle"] == "深圳湾"


def test_presenter_keeps_turn_local_error_and_pending_cards_intact():
    cards = present_capture_references(
        [
            {
                "kind": "error",
                "card_type": "error",
                "title": "消费",
                "subtitle": "未找到唯一记录",
            },
            {
                "kind": "pending_contact",
                "card_type": "pending_contact",
                "pending_action_id": "pending-1",
                "title": "Alex",
                "candidates": [],
            },
        ],
        skills=[],
    )

    assert cards[0]["card_type"] == "error"
    assert cards[0]["subtitle"] == "未找到唯一记录"
    assert cards[1]["card_type"] == "pending_contact"
    assert cards[1]["icon"] == "👤"
