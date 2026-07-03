from __future__ import annotations

from api.sessions import _hydrate_task_card


def main() -> None:
    card = {
        "card_type": "task",
        "task_id": "task-1",
        "asset_id": "asset-1",
        "status": "pending",
        "payload": {
            "task_id": "task-1",
            "status": "pending",
            "external_system": "pending",
            "title": "同步到钉钉",
        },
    }
    task = {
        "status": "done",
        "mcp_target": "dingtalk_notes",
    }
    asset_payload = {
        "task_id": "task-1",
        "status": "done",
        "external_system": "dingtalk_notes",
        "external_id": "doc-1",
        "external_url": "https://example.test/doc-1",
        "external_type": "document",
        "title": "世界杯",
    }

    hydrated = _hydrate_task_card(card, task, asset_payload)
    assert hydrated["status"] == "done"
    assert hydrated["payload"]["status"] == "done"
    assert hydrated["payload"]["external_system"] == "dingtalk_notes"
    assert hydrated["payload"]["external_id"] == "doc-1"
    assert hydrated["payload"]["title"] == "世界杯"
    print("ok - task card hydrated from latest task/external_ref state")


if __name__ == "__main__":
    main()
