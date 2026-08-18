"""Unit contract for durable chat mutation receipts.

Run:
    cd backend && python -m scripts.test_chat_mutation_receipt_contract
"""

from api.chat import build_durable_tool_result


def test_successful_delete_receipt_needs_no_card() -> None:
    receipt = build_durable_tool_result([
        {
            "name": "tool_delete_asset",
            "response": {
                "structuredContent": {
                    "result": '{"ok":true,"asset_id":"deleted-asset"}',
                },
            },
        },
    ])

    assert receipt["confirmed_mutation"] is True
    assert receipt["results"][0]["name"] == "tool_delete_asset"


def test_query_and_failed_write_have_no_mutation_receipt() -> None:
    query = build_durable_tool_result([
        {"name": "tool_query_asset", "response": {"ok": True, "assets": []}},
    ])
    failed_write = build_durable_tool_result([
        {"name": "tool_update_asset", "response": {"ok": False, "error": "gone"}},
    ])

    assert query["confirmed_mutation"] is False
    assert failed_write["confirmed_mutation"] is False


if __name__ == "__main__":
    test_successful_delete_receipt_needs_no_card()
    test_query_and_failed_write_have_no_mutation_receipt()
    print("PASS - durable chat mutation receipt contract")
