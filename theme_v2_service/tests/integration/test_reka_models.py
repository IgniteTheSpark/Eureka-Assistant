from datetime import datetime, timedelta

import pytest
from sqlalchemy.exc import IntegrityError

from app.domains.reka.models import Nudge, RhythmProfile


NOW = datetime(2026, 8, 10, 10, 0)


async def test_nudge_natural_identity_is_unique_per_user(session):
    session.add(
        Nudge(
            user_id="user-1",
            natural_key="overdue:todo-1:2026-08-10T01:00:00Z",
            kind="overdue",
            ref="todo-1",
            status="delivered",
            delivered_at=NOW,
            expires_at=NOW + timedelta(hours=72),
        )
    )
    await session.flush()
    session.add(
        Nudge(
            user_id="user-1",
            natural_key="overdue:todo-1:2026-08-10T01:00:00Z",
            kind="overdue",
            ref="todo-1",
            status="delivered",
            delivered_at=NOW,
            expires_at=NOW + timedelta(hours=72),
        )
    )

    with pytest.raises(IntegrityError):
        await session.flush()


async def test_same_natural_identity_is_independent_between_users(session):
    natural_key = "rhythm:breakfast:daily:上午:2026-08-10"
    session.add_all(
        [
            Nudge(
                user_id=user_id,
                natural_key=natural_key,
                kind="rhythm_gap",
                ref="breakfast:daily:上午",
                status="delivered",
                delivered_at=NOW,
            )
            for user_id in ("user-1", "user-2")
        ]
    )

    await session.flush()


async def test_rhythm_profile_persists_multiple_period_patterns(session):
    profile = RhythmProfile(
        user_id="user-1",
        skill="medication",
        timezone_name="Asia/Shanghai",
        patterns_json=[
            {
                "pattern_key": "daily:上午",
                "cadence": "daily",
                "period": "上午",
                "weekdays": [],
                "confidence": 0.8,
                "sample_n": 8,
            },
            {
                "pattern_key": "daily:晚上",
                "cadence": "daily",
                "period": "晚上",
                "weekdays": [],
                "confidence": 0.7,
                "sample_n": 7,
            },
        ],
        computed_at=NOW,
    )
    session.add(profile)
    await session.flush()
    session.expunge(profile)

    restored = await session.get(
        RhythmProfile,
        {"user_id": "user-1", "skill": "medication"},
    )

    assert restored is not None
    assert [row["period"] for row in restored.patterns_json] == ["上午", "晚上"]
