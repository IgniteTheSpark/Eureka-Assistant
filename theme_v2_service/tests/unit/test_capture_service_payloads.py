from types import SimpleNamespace

from app.domains.capture.service import (
    _display_result_summary,
    flash_response_payload,
)


def test_migrated_misc_capture_is_presented_as_notes():
    recording = SimpleNamespace(
        result_summary="内容不明确，已记为其他类型。",
        result_records_json=[
            {
                "kind": "asset",
                "asset_id": "asset-1",
                "skill_machine_name": "notes",
            }
        ],
    )

    assert _display_result_summary(recording) == "内容不明确，已记为随记。"


def test_unrelated_capture_summary_is_not_rewritten():
    recording = SimpleNamespace(
        result_summary="其他参与人稍后确认。",
        result_records_json=[
            {
                "kind": "asset",
                "asset_id": "asset-1",
                "skill_machine_name": "notes",
            }
        ],
    )

    assert _display_result_summary(recording) == "其他参与人稍后确认。"


def test_completed_capture_with_confirmation_card_reports_pending():
    recording = SimpleNamespace(
        id="recording-1",
        session_id="session-1",
        input_turn_id="turn-1",
        process_status="done",
        result_summary="有 1 项需要确认。",
        result_records_json=[
            {
                "kind": "pending_contact",
                "card_type": "pending_contact",
                "pending_action_id": "pending-1",
                "title": "Alex",
                "candidates": [],
            }
        ],
        error_message=None,
    )

    payload = flash_response_payload(
        SimpleNamespace(recording=recording, turn=None),
        elapsed_ms=42,
    )

    assert payload["has_pending"] is True
    assert payload["cards"][0]["pending_action_id"] == "pending-1"
