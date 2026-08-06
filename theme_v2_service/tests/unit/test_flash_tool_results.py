import json

from app.domains.capture.dispatcher import FlashIntent
from app.domains.capture.tool_results import (
    resolve_agent_result,
    unwrap_mcp_response,
)


def _intent(intent_type="expense", source_text="午饭8元"):
    return FlashIntent(type=intent_type, source_text=source_text, domain="生活")


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


def test_successful_query_snapshot_is_ground_truth():
    resolved = resolve_agent_result(
        intent=_intent(),
        final_text='{"ok":true,"answer":"查到了"}',
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
            }
        ],
    )

    assert resolved.status == "success"
    assert resolved.result["assets"][0]["asset_id"] == "expense-1"


def test_qa_final_json_becomes_reply_without_a_write():
    resolved = resolve_agent_result(
        intent=_intent("qa", "拿铁和美式有什么区别"),
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
