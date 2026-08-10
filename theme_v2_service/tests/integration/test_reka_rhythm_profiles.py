from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from app.db.models import Asset, UserSkill
from app.domains.reka.models import Nudge, RhythmProfile
from app.domains.reka.rhythm import (
    collect_rhythm_candidates,
    recompute_rhythm_profiles,
)


UTC = timezone.utc
SHANGHAI = ZoneInfo("Asia/Shanghai")


def _db(local_day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(
        2026,
        8,
        local_day,
        hour,
        minute,
        tzinfo=SHANGHAI,
    ).astimezone(UTC).replace(tzinfo=None)


def _now(local_day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(
        2026,
        8,
        local_day,
        hour,
        minute,
        tzinfo=SHANGHAI,
    ).astimezone(UTC)


async def _skill(session, machine_name: str, display_name: str) -> UserSkill:
    skill = UserSkill(
        id=f"skill-{machine_name}",
        user_id="user-1",
        machine_name=machine_name,
        display_name=display_name,
        schema_json={},
        render_spec_json={},
    )
    session.add(skill)
    await session.flush()
    return skill


async def _asset(
    session,
    skill: UserSkill,
    *,
    asset_id: str,
    created_at: datetime,
    occurred_at: datetime | None = None,
) -> Asset:
    asset = Asset(
        id=asset_id,
        user_id=skill.user_id,
        user_skill_id=skill.id,
        payload_json={"value": asset_id},
        occurred_at=occurred_at,
        created_at=created_at,
        updated_at=created_at,
    )
    session.add(asset)
    return asset


async def test_recompute_uses_created_at_and_persists_multiple_periods(session):
    medication = await _skill(session, "medication", "用药记录")
    todo = await _skill(session, "todo", "待办")
    for day in range(1, 6):
        await _asset(
            session,
            medication,
            asset_id=f"medication-morning-{day}",
            created_at=_db(day, 8, 13),
            occurred_at=_db(day, 22, 0),
        )
        await _asset(
            session,
            medication,
            asset_id=f"medication-afternoon-{day}",
            created_at=_db(day, 16, 40),
            occurred_at=_db(day, 1, 0),
        )
        await _asset(
            session,
            todo,
            asset_id=f"todo-{day}",
            created_at=_db(day, 8, 0),
        )
    session.add(
        RhythmProfile(
            user_id="user-1",
            skill="stale-skill",
            timezone_name="Asia/Shanghai",
            patterns_json=[{"pattern_key": "daily:上午"}],
            computed_at=_db(1, 0),
        )
    )
    await session.flush()

    written = await recompute_rhythm_profiles(
        session,
        now=_now(10, 10),
        timezone_name="Asia/Shanghai",
    )

    profile = await session.get(
        RhythmProfile,
        {"user_id": "user-1", "skill": "medication"},
    )
    assert written == 1
    assert profile is not None
    assert [row["period"] for row in profile.patterns_json] == ["上午", "下午"]
    assert await session.get(
        RhythmProfile,
        {"user_id": "user-1", "skill": "todo"},
    ) is None
    assert await session.get(
        RhythmProfile,
        {"user_id": "user-1", "skill": "stale-skill"},
    ) is None


async def _profile_and_history(
    session,
    *,
    completed_days: tuple[int, ...],
    dismissed_day: int | None = None,
) -> None:
    breakfast = await _skill(session, "breakfast", "早餐记录")
    for day in completed_days:
        await _asset(
            session,
            breakfast,
            asset_id=f"breakfast-{day}",
            created_at=_db(day, 8, 0),
        )
    session.add(
        RhythmProfile(
            user_id="user-1",
            skill="breakfast",
            timezone_name="Asia/Shanghai",
            patterns_json=[
                {
                    "pattern_key": "daily:上午",
                    "cadence": "daily",
                    "period": "上午",
                    "weekdays": [],
                    "confidence": 0.8,
                    "sample_n": 8,
                }
            ],
            computed_at=_db(9, 0),
        )
    )
    if dismissed_day is not None:
        session.add(
            Nudge(
                user_id="user-1",
                natural_key=(
                    f"rhythm:breakfast:daily:上午:2026-08-{dismissed_day:02d}"
                ),
                kind="rhythm_gap",
                ref="breakfast:daily:上午",
                status="dismissed",
                delivered_at=_db(dismissed_day, 9),
                dismissed_at=_db(dismissed_day, 9, 5),
            )
        )
    await session.flush()


async def test_collect_returns_current_pattern_gap(session):
    await _profile_and_history(session, completed_days=tuple(range(1, 10)))

    candidates = await collect_rhythm_candidates(
        session,
        user_id="user-1",
        now=_now(10, 10),
        timezone_name="Asia/Shanghai",
    )

    assert len(candidates) == 1
    assert candidates[0].natural_key == (
        "rhythm:breakfast:daily:上午:2026-08-10"
    )
    assert candidates[0].ref == "breakfast:daily:上午"
    assert candidates[0].display_name == "早餐记录"


async def test_dismissed_pattern_stays_suppressed_when_cycle_streak_breaks(session):
    await _profile_and_history(
        session,
        completed_days=(1, 2, 3, 4, 5, 7, 9),
        dismissed_day=6,
    )

    assert await collect_rhythm_candidates(
        session,
        user_id="user-1",
        now=_now(10, 10),
        timezone_name="Asia/Shanghai",
    ) == []


async def test_three_completed_cycles_restore_dismissed_pattern(session):
    await _profile_and_history(
        session,
        completed_days=(1, 2, 3, 4, 5, 7, 8, 9),
        dismissed_day=6,
    )

    candidates = await collect_rhythm_candidates(
        session,
        user_id="user-1",
        now=_now(10, 10),
        timezone_name="Asia/Shanghai",
    )

    assert [candidate.skill for candidate in candidates] == ["breakfast"]
