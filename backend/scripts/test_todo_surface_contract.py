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


def test_todo_editor_uses_the_canonical_theme_v2_schema() -> None:
    page = _read(
        "mobile/lib/theme_v2/asset_detail/theme_v2_asset_edit_page.dart"
    )
    presentation = _read(
        "mobile/lib/theme_v2/library/asset/asset_detail_presentation.dart"
    )
    endpoint = _read("backend/api/asset_details.py")
    assert "renderSpecFromAssetDetailModel(model)" in page
    assert "AssetEditorRouter" in page
    assert (
        "schemaFields: [for (final field in model.fields) field.id]"
        in presentation
    )
    assert "fields = _field_rows(user_skill.payload_schema)" in endpoint
    assert "_assert_known_fields(body.values_patch, set(schema))" in endpoint
    assert not (
        ROOT / "mobile/lib/render/asset_detail_sheet.dart"
    ).exists()


def test_todo_payload_metadata_is_normalized_at_write_boundary() -> None:
    source = _read("backend/mcp_server/tools.py")
    assert "_normalize_todo_payload" in source
    assert "payload_dict.pop(\"period\"" in source
    assert "payload_dict.pop(\"occurred_at\"" in source


if __name__ == "__main__":
    test_timeline_exposes_user_scheduled_time()
    test_calendar_does_not_treat_capture_time_as_todo_schedule()
    test_todo_editor_uses_the_canonical_theme_v2_schema()
    test_todo_payload_metadata_is_normalized_at_write_boundary()
    print("ok - todo surface contract")
