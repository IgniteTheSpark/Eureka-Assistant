"""Regression checks for todo scheduling and editor field boundaries.

These checks intentionally inspect the small cross-layer contract: the backend
must expose whether a todo has a user-supplied schedule, and the Flutter editor
must use the canonical todo field list instead of arbitrary payload leftovers.
"""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_timeline_exposes_user_scheduled_time() -> None:
    source = _read("backend/core/timeline.py")
    assert '"has_scheduled_time"' in source
    assert "_todo_due_has_clock" in source


def test_calendar_does_not_treat_capture_time_as_todo_schedule() -> None:
    source = _read("mobile/lib/pages/calendar_page.dart")
    start = source.index("static bool _todoTimed")
    body = source[start : source.index(";", start) + 1]
    assert "hasScheduledTime" in body
    assert "effectiveAt.hour" not in body


def test_todo_editor_has_a_strict_business_field_allowlist() -> None:
    source = _read("mobile/lib/render/asset_detail_sheet.dart")
    assert "_todoEditableFields" in source
    assert "{'title', 'due_date', 'content'}" in source
    assert "widget.cardType == 'todo'" in source


def test_todo_payload_metadata_is_normalized_at_write_boundary() -> None:
    source = _read("backend/mcp_server/tools.py")
    assert "_normalize_todo_payload" in source
    assert "payload_dict.pop(\"period\"" in source
    assert "payload_dict.pop(\"occurred_at\"" in source


if __name__ == "__main__":
    test_timeline_exposes_user_scheduled_time()
    test_calendar_does_not_treat_capture_time_as_todo_schedule()
    test_todo_editor_has_a_strict_business_field_allowlist()
    test_todo_payload_metadata_is_normalized_at_write_boundary()
    print("ok - todo surface contract")
