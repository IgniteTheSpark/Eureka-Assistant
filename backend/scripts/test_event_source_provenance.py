"""Regression checks for Event source-session provenance across API surfaces."""

from __future__ import annotations

import inspect
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from core import timeline
from mcp_server import tools


def _event():
    return SimpleNamespace(
        id=uuid.uuid4(),
        title="产品评审",
        start_at=datetime(2026, 7, 14, 14, 0, tzinfo=timezone.utc),
        end_at=datetime(2026, 7, 14, 15, 0, tzinfo=timezone.utc),
        all_day=False,
        location="会议室",
        description=None,
        recurrence_rule=None,
        status="scheduled",
        sync_source="manual",
        source_input_turn_id=uuid.uuid4(),
        created_at=datetime(2026, 7, 14, 8, 0, tzinfo=timezone.utc),
    )


def test_event_serializers_include_source_session() -> None:
    event = _event()
    session_id = uuid.uuid4()

    api_event = tools._event_to_dict(event, session_id=session_id)
    timeline_event = timeline._event_item(event, session_id=session_id)

    assert api_event["session_id"] == str(session_id)
    assert timeline_event["session_id"] == str(session_id)


def test_event_queries_resolve_source_turn_to_session() -> None:
    query_source = inspect.getsource(tools.query_event)
    detail_source = inspect.getsource(tools.get_event)
    timeline_source = inspect.getsource(timeline.assemble_timeline)

    assert "_event_source_sessions" in query_source
    assert "_event_source_sessions" in detail_source
    assert "_event_source_sessions" in timeline_source


if __name__ == "__main__":
    test_event_serializers_include_source_session()
    test_event_queries_resolve_source_turn_to_session()
    print("ok - event source provenance contract")
