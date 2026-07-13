"""Regression checks for Event cards persisted in Flash sessions."""

from __future__ import annotations

import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _load_event_card_helpers() -> dict:
    source = (ROOT / "agents/flash_pipeline.py").read_text()
    module = ast.parse(source)
    body = [
        node
        for node in module.body
        if isinstance(node, ast.FunctionDef)
        and node.name in {"_fmt_dt", "_event_card"}
    ]
    namespace: dict = {}
    exec(
        compile(ast.Module(body=body, type_ignores=[]), "event_card_subset", "exec"),
        namespace,
    )
    return namespace


def test_event_card_preserves_summary_fields() -> None:
    event_card = _load_event_card_helpers()["_event_card"]

    card = event_card({
        "event_id": "event-1",
        "title": "产品评审",
        "start_at": "2026-07-13T14:00:00+08:00",
        "end_at": "2026-07-13T15:00:00+08:00",
        "all_day": False,
        "location": "会议室",
        "attendees": [{"name": "Alex"}, {"name": "Bob"}],
    })

    assert card["start_at"] == "2026-07-13T14:00:00+08:00"
    assert card["end_at"] == "2026-07-13T15:00:00+08:00"
    assert card["all_day"] is False
    assert card["location"] == "会议室"
    assert card["attendees"] == [{"name": "Alex"}, {"name": "Bob"}]


if __name__ == "__main__":
    test_event_card_preserves_summary_fields()
    print("ok - event card summary contract")
