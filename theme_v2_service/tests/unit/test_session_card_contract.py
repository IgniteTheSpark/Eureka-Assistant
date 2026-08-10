import pytest

from app.domains.sessions.card_contract import (
    SessionCardInvalid,
    SessionCardSource,
    build_entity_card,
    cards_from_tool_result,
)


SOURCE = SessionCardSource(
    session_id="session-1",
    input_turn_id="turn-1",
    kind="chat",
)


def test_asset_card_contains_only_canonical_identity_entity_and_source():
    card = build_entity_card(
        entity_kind="asset",
        entity_id="asset-1",
        skill_machine_name="todo",
        entity={
            "asset_id": "asset-1",
            "user_skill_name": "todo",
            "payload": {"title": "交方案"},
            "created_at": "2026-08-08T10:00:00Z",
        },
        source=SOURCE,
    )

    assert card == {
        "entity_kind": "asset",
        "entity_id": "asset-1",
        "skill_machine_name": "todo",
        "entity": {
            "asset_id": "asset-1",
            "user_skill_name": "todo",
            "payload": {"title": "交方案"},
            "created_at": "2026-08-08T10:00:00Z",
        },
        "source": {
            "session_id": "session-1",
            "input_turn_id": "turn-1",
            "kind": "chat",
        },
    }
    assert not {
        "title",
        "subtitle",
        "icon",
        "accent_color",
        "meta_fields",
        "card_type",
        "asset_id",
    }.intersection(card)


@pytest.mark.parametrize(
    ("kwargs", "message"),
    [
        (
            {
                "entity_kind": "task",
                "entity_id": "task-1",
                "entity": {},
                "source": SOURCE,
            },
            "unsupported entity kind",
        ),
        (
            {
                "entity_kind": "event",
                "entity_id": "",
                "entity": {},
                "source": SOURCE,
            },
            "entity_id is required",
        ),
        (
            {
                "entity_kind": "asset",
                "entity_id": "asset-1",
                "entity": {},
                "source": SOURCE,
            },
            "asset skill_machine_name is required",
        ),
    ],
)
def test_invalid_or_incomplete_entity_identity_is_rejected(kwargs, message):
    with pytest.raises(SessionCardInvalid, match=message):
        build_entity_card(**kwargs)


def test_tool_results_map_assets_events_and_contacts_to_one_protocol():
    asset_cards = cards_from_tool_result(
        "tool_create_todo",
        {
            "ok": True,
            "asset_id": "todo-1",
            "user_skill_name": "todo",
            "payload": {"title": "交方案"},
        },
        SOURCE,
    )
    event_cards = cards_from_tool_result(
        "tool_query_event",
        {
            "ok": True,
            "events": [
                {
                    "event_id": "event-1",
                    "title": "设计评审",
                    "start_at": "2026-08-09T15:00:00+08:00",
                    "end_at": "2026-08-09T16:00:00+08:00",
                }
            ],
        },
        SOURCE,
    )
    contact_cards = cards_from_tool_result(
        "tool_query_contact",
        {
            "ok": True,
            "contacts": [{"contact_id": "contact-1", "name": "冯总"}],
        },
        SOURCE,
    )

    assert asset_cards[0]["entity_kind"] == "asset"
    assert asset_cards[0]["skill_machine_name"] == "todo"
    assert event_cards[0]["entity_kind"] == "event"
    assert event_cards[0]["entity_id"] == "event-1"
    assert contact_cards[0]["entity_kind"] == "contact"
    assert contact_cards[0]["entity_id"] == "contact-1"
    assert all(card["source"] == SOURCE.as_dict() for card in [
        *asset_cards,
        *event_cards,
        *contact_cards,
    ])


def test_failed_and_unidentified_tool_results_do_not_create_cards():
    assert cards_from_tool_result(
        "tool_create_todo",
        {"ok": False, "error": "failed"},
        SOURCE,
    ) == []
    assert cards_from_tool_result(
        "tool_delete_asset",
        {"ok": True, "asset_id": "asset-1", "status": "deleted"},
        SOURCE,
    ) == []
