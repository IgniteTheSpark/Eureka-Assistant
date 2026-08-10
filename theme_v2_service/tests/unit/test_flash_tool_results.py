import json

from app.domains.capture.dispatcher import FlashIntent
from app.domains.capture.tool_results import (
    resolve_agent_result,
    unwrap_mcp_response,
)


def _intent(
    intent_type="expense",
    source_text="午饭8元",
    operation="create",
):
    return FlashIntent(
        type=intent_type,
        operation=operation,
        source_text=source_text,
        domain="生活",
    )


def test_unwrap_mcp_response_prefers_structured_content_result():
    response = {
        "ok": False,
        "structuredContent": {
            "result": json.dumps(
                {"ok": True, "asset_id": "asset-1"}, ensure_ascii=False
            )
        },
        "content": [{"type": "text", "text": '{"ok":false}'}],
    }

    assert unwrap_mcp_response(response) == {
        "ok": True,
        "asset_id": "asset-1",
    }


def test_unwrap_mcp_response_accepts_content_text_and_normalized_dict():
    wrapped = {
        "content": [
            {
                "type": "text",
                "text": '{"ok":true,"contact_id":"contact-1"}',
            }
        ]
    }

    assert unwrap_mcp_response(wrapped)["contact_id"] == "contact-1"
    assert unwrap_mcp_response({"ok": True, "event_id": "event-1"}) == {
        "ok": True,
        "event_id": "event-1",
    }


def test_successful_tool_result_wins_over_malformed_final_text():
    resolved = resolve_agent_result(
        intent=_intent(),
        final_text="not json",
        tool_events=[
            {
                "name": "tool_create_asset",
                "args": {},
                "response": {
                    "ok": True,
                    "asset_id": "asset-1",
                    "user_skill_name": "expense",
                    "payload": {"amount": 8},
                },
            }
        ],
    )

    assert resolved.status == "success"
    assert resolved.result["asset_id"] == "asset-1"
    assert resolved.error_code is None


def test_model_cannot_claim_an_unobserved_mutation():
    resolved = resolve_agent_result(
        intent=_intent(),
        final_text='{"ok":true,"asset_id":"invented"}',
        tool_events=[],
    )

    assert resolved.status == "error"
    assert resolved.result == {}
    assert resolved.error_code == "intent_ungrounded_mutation"


def test_successful_query_does_not_claim_a_mutation_intent_was_completed():
    resolved = resolve_agent_result(
        intent=_intent(),
        final_text='{"ok":false,"error":"period rejected"}',
        tool_events=[
            {
                "name": "tool_query_asset",
                "args": {"user_skill_name": "expense"},
                "response": {
                    "ok": True,
                    "assets": [
                        {"asset_id": "expense-1", "payload": {"amount": 8}}
                    ],
                },
            },
            {
                "name": "tool_create_asset",
                "args": {"period": "早上"},
                "response": {"ok": False, "error": "period rejected"},
            },
        ],
    )

    assert resolved.status == "error"
    assert resolved.result == {}
    assert resolved.error_code == "intent_tool_rejected"


def test_query_requires_a_grounded_read_and_returns_a_reply():
    resolved = resolve_agent_result(
        intent=_intent(
            "expense",
            "帮我看看最近花了多少钱",
            operation="query",
        ),
        final_text='{"ok":true,"answer":"最近共消费 28 元。"}',
        tool_events=[
            {
                "name": "tool_query_asset",
                "args": {"user_skill_name": "expense"},
                "response": {
                    "ok": True,
                    "assets": [
                        {"asset_id": "expense-1", "payload": {"amount": 8}},
                        {"asset_id": "expense-2", "payload": {"amount": 20}},
                    ],
                },
            }
        ],
    )

    assert resolved.status == "reply"
    assert resolved.result["answer"] == "最近共消费 28 元。"
    assert len(resolved.result["sources"]["assets"]) == 2


def test_query_without_a_grounded_read_is_not_accepted():
    resolved = resolve_agent_result(
        intent=_intent("expense", "最近花了多少钱", operation="query"),
        final_text='{"ok":true,"answer":"最近共消费 28 元。"}',
        tool_events=[],
    )

    assert resolved.status == "error"
    assert resolved.error_code == "intent_query_ungrounded"


def test_update_requires_a_matching_update_effect():
    resolved = resolve_agent_result(
        intent=_intent("expense", "把刚刚账单改成8元", operation="update"),
        final_text='{"ok":true,"asset_id":"asset-2"}',
        tool_events=[
            {
                "name": "tool_create_asset",
                "args": {"user_skill_name": "expense"},
                "response": {"ok": True, "asset_id": "asset-2"},
            }
        ],
    )

    assert resolved.status == "error"
    assert resolved.error_code == "intent_effect_mismatch"


def test_delete_accepts_only_the_matching_delete_effect():
    resolved = resolve_agent_result(
        intent=_intent("todo", "删除刚刚那个代办", operation="delete"),
        final_text="not json",
        tool_events=[
            {
                "name": "tool_delete_asset",
                "args": {"asset_id": "todo-1"},
                "response": {"ok": True, "asset_id": "todo-1"},
            }
        ],
    )

    assert resolved.status == "success"
    assert resolved.result["asset_id"] == "todo-1"
    assert resolved.result["operation_tool"] == "tool_delete_asset"


def test_answer_cannot_be_satisfied_by_a_mutation():
    resolved = resolve_agent_result(
        intent=_intent("qa", "地球为什么是圆的", operation="answer"),
        final_text='{"ok":true,"answer":"因为引力。"}',
        tool_events=[
            {
                "name": "tool_create_asset",
                "args": {"user_skill_name": "notes"},
                "response": {"ok": True, "asset_id": "note-1"},
            }
        ],
    )

    assert resolved.status == "error"
    assert resolved.error_code == "intent_unexpected_mutation"


def test_qa_final_json_becomes_reply_without_a_write():
    resolved = resolve_agent_result(
        intent=_intent("qa", "拿铁和美式有什么区别", operation="answer"),
        final_text=(
            '{"ok":true,"answer":"拿铁加牛奶，美式加水。",'
            '"session_id":"ignored"}'
        ),
        tool_events=[],
    )

    assert resolved.status == "reply"
    assert resolved.result == {"answer": "拿铁加牛奶，美式加水。"}


def test_contact_candidates_become_pending_confirmation():
    resolved = resolve_agent_result(
        intent=_intent("contact", "更新Alex的职业"),
        final_text=(
            '{"ok":true,"status":"pending_confirmation",'
            '"candidates":[{"contact_id":"c1","name":"Alex"},'
            '{"contact_id":"c2","name":"Alex"}]}'
        ),
        tool_events=[
            {
                "name": "tool_query_contact",
                "args": {"name_query": "Alex"},
                "response": {
                    "ok": True,
                    "contacts": [
                        {"contact_id": "c1", "name": "Alex"},
                        {"contact_id": "c2", "name": "Alex"},
                    ],
                    "exact_contacts": [
                        {"contact_id": "c1", "name": "Alex"},
                        {"contact_id": "c2", "name": "Alex"},
                    ],
                },
            }
        ],
    )

    assert resolved.status == "pending_confirmation"
    assert [item["contact_id"] for item in resolved.result["candidates"]] == [
        "c1",
        "c2",
    ]


def test_rejected_tool_result_uses_generic_error_code():
    resolved = resolve_agent_result(
        intent=_intent(),
        final_text='{"ok":false,"error":"provider details"}',
        tool_events=[
            {
                "name": "tool_create_asset",
                "args": {},
                "response": {"ok": False, "error": "database internals"},
            }
        ],
    )

    assert resolved.status == "error"
    assert resolved.error_code == "intent_tool_rejected"
    assert "database" not in json.dumps(resolved.result)
