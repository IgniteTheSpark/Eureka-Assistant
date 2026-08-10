from datetime import datetime, timedelta, timezone

from app.domains.reka.overdue import overdue_candidate, parse_todo_due


UTC = timezone.utc
NOW = datetime(2026, 8, 10, 10, 0, tzinfo=UTC)


def test_parse_todo_due_requires_an_explicit_clock_time():
    assert parse_todo_due("2026-08-10", "Asia/Shanghai") is None
    assert parse_todo_due("", "Asia/Shanghai") is None
    assert parse_todo_due(None, "Asia/Shanghai") is None
    assert parse_todo_due("not-a-date", "Asia/Shanghai") is None


def test_naive_todo_due_uses_the_requested_local_timezone():
    assert parse_todo_due(
        "2026-08-10T18:00:00",
        "Asia/Shanghai",
    ) == datetime(2026, 8, 10, 10, 0, tzinfo=UTC)


def test_overdue_occurrence_starts_after_due_and_expires_at_72_hours():
    payload = {
        "title": "提交方案",
        "due_date": "2026-08-10T09:59:59Z",
        "status": "pending",
    }

    candidate = overdue_candidate(
        todo_id="todo-1",
        payload=payload,
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert candidate is not None
    assert candidate.natural_key == "overdue:todo-1:2026-08-10T09:59:59Z"
    assert candidate.expires_at == datetime(2026, 8, 13, 9, 59, 59, tzinfo=UTC)
    assert overdue_candidate(
        todo_id="todo-1",
        payload={**payload, "due_date": "2026-08-10T10:00:00Z"},
        now=NOW,
        timezone_name="Asia/Shanghai",
    ) is None
    assert overdue_candidate(
        todo_id="todo-1",
        payload=payload,
        now=datetime(2026, 8, 13, 9, 59, 59, tzinfo=UTC),
        timezone_name="Asia/Shanghai",
    ) is None


def test_completed_todos_never_become_overdue():
    base = {"title": "提交方案", "due_date": "2026-08-09T10:00:00Z"}

    for completed in (
        {"status": "done"},
        {"status": "completed"},
        {"done": True},
    ):
        assert overdue_candidate(
            todo_id="todo-1",
            payload={**base, **completed},
            now=NOW,
            timezone_name="Asia/Shanghai",
        ) is None


def test_rescheduled_due_time_changes_occurrence_identity():
    first = overdue_candidate(
        todo_id="todo-1",
        payload={
            "title": "提交方案",
            "due_date": "2026-08-10T09:00:00Z",
            "status": "pending",
        },
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    second = overdue_candidate(
        todo_id="todo-1",
        payload={
            "title": "提交方案",
            "due_date": "2026-08-10T09:30:00Z",
            "status": "pending",
        },
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert first is not None and second is not None
    assert first.natural_key != second.natural_key
    assert second.due_at - first.due_at == timedelta(minutes=30)
