"""Regression contract for authoritative asset effective time responses.

This repository intentionally keeps backend contract checks dependency-free, so
the script inspects the API source instead of importing FastAPI/SQLAlchemy.
"""

import ast
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from core.asset_time import effective_at_for_asset


SOURCE = (ROOT / "api/assets.py").read_text(encoding="utf-8")
TREE = ast.parse(SOURCE)
TZ = timezone(timedelta(hours=8))


def _function(name: str):
    return next(
        node
        for node in TREE.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == name
    )


def test_serializer_uses_timeline_rule_and_keeps_audit_time() -> None:
    serializer = _function("_serialize_asset")
    args = [argument.arg for argument in serializer.args.args]
    body = ast.get_source_segment(SOURCE, serializer) or ""

    assert "render_spec" in args
    assert "effective_at_for_asset" in body
    assert '"effective_at"' in body
    assert '"created_at"' in body
    assert '"user_skill_id"' in body


def test_every_read_path_selects_and_passes_render_spec() -> None:
    for name in ("list_assets", "get_asset", "update_asset"):
        body = ast.get_source_segment(SOURCE, _function(name)) or ""
        assert "render_spec" in body, f"{name} must select/pass render_spec"

    structured = (ROOT / "db/queries.py").read_text(encoding="utf-8")
    assert "effective_at_for_asset" in structured
    assert '"effective_at"' in structured
    assert '"skill_name":' in structured, "keep the legacy structured-query key"


def test_authoritative_rule_prefers_occurred_then_schema_anchor() -> None:
    created = datetime(2026, 7, 28, 9, tzinfo=TZ)
    anchored = SimpleNamespace(
        payload={"played_on": "2026-07-02"},
        occurred_at=None,
        created_at=created,
    )
    occurred = datetime(2026, 7, 3, 15, 20, tzinfo=TZ)
    precise = SimpleNamespace(
        payload=anchored.payload,
        occurred_at=occurred,
        created_at=created,
    )

    assert effective_at_for_asset(
        anchored,
        "tennis_match",
        {"timeline_anchor": "played_on"},
    ) == datetime(2026, 7, 2, tzinfo=TZ)
    assert effective_at_for_asset(
        precise,
        "tennis_match",
        {"timeline_anchor": "played_on"},
    ) == occurred


if __name__ == "__main__":
    test_serializer_uses_timeline_rule_and_keeps_audit_time()
    test_every_read_path_selects_and_passes_render_spec()
    test_authoritative_rule_prefers_occurred_then_schema_anchor()
    print("asset effective-at contract: OK")
