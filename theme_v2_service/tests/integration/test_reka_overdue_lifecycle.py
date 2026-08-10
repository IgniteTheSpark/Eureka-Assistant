from datetime import datetime, timezone

from app.db.models import Asset, UserSkill
from app.domains.reka.overdue import collect_overdue_candidates


UTC = timezone.utc
NOW = datetime(2026, 8, 10, 10, 0, tzinfo=UTC)


async def _todo(session, *, payload: dict) -> Asset:
    skill = UserSkill(
        id="skill-todo",
        user_id="user-1",
        machine_name="todo",
        display_name="待办",
        schema_json={},
        render_spec_json={},
    )
    session.add(skill)
    await session.flush()
    asset = Asset(
        id="todo-1",
        user_id="user-1",
        user_skill_id=skill.id,
        payload_json=payload,
        created_at=datetime(2026, 8, 9, 1, 0),
        updated_at=datetime(2026, 8, 9, 1, 0),
    )
    session.add(asset)
    await session.flush()
    return asset


async def test_completion_removes_overdue_candidate_live(session):
    asset = await _todo(
        session,
        payload={
            "title": "提交方案",
            "due_date": "2026-08-10T09:00:00Z",
            "status": "pending",
        },
    )

    before = await collect_overdue_candidates(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    asset.payload_json = {**asset.payload_json, "status": "done"}
    await session.flush()
    after = await collect_overdue_candidates(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [candidate.todo_id for candidate in before] == ["todo-1"]
    assert after == []


async def test_reschedule_replaces_overdue_occurrence_identity(session):
    asset = await _todo(
        session,
        payload={
            "title": "提交方案",
            "due_date": "2026-08-10T09:00:00Z",
            "status": "pending",
        },
    )
    before = await collect_overdue_candidates(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    asset.payload_json = {
        **asset.payload_json,
        "due_date": "2026-08-10T09:30:00Z",
    }
    await session.flush()
    after = await collect_overdue_candidates(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert before[0].natural_key == "overdue:todo-1:2026-08-10T09:00:00Z"
    assert after[0].natural_key == "overdue:todo-1:2026-08-10T09:30:00Z"


async def test_date_only_and_non_todo_assets_are_excluded(session):
    await _todo(
        session,
        payload={
            "title": "提交方案",
            "due_date": "2026-08-09",
            "status": "pending",
        },
    )
    notes = UserSkill(
        id="skill-notes",
        user_id="user-1",
        machine_name="notes",
        display_name="随记",
        schema_json={},
        render_spec_json={},
    )
    session.add(notes)
    await session.flush()
    session.add(
        Asset(
            id="notes-1",
            user_id="user-1",
            user_skill_id=notes.id,
            payload_json={
                "title": "不是待办",
                "due_date": "2026-08-09T09:00:00Z",
            },
        )
    )
    await session.flush()

    assert await collect_overdue_candidates(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    ) == []
