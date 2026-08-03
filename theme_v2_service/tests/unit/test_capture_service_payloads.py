from types import SimpleNamespace

from app.domains.capture.service import _display_result_summary


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
