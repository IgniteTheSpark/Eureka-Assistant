import asyncio
from datetime import datetime, timedelta

from app.domains.reka.maintenance import (
    expire_stale_nudges,
    run_reka_maintenance_cycle,
    run_reka_maintenance_scheduler,
)
from app.domains.reka.models import Nudge, RhythmProfile


NOW = datetime(2026, 8, 10, 10, 0)


async def test_expire_stale_nudges_only_closes_active_expired_rows(session):
    session.add_all(
        [
            Nudge(
                id="expired-active",
                user_id="user-1",
                natural_key="overdue:todo-1:old",
                kind="overdue",
                ref="todo-1",
                status="delivered",
                delivered_at=NOW - timedelta(days=4),
                expires_at=NOW,
            ),
            Nudge(
                id="future-active",
                user_id="user-1",
                natural_key="overdue:todo-2:future",
                kind="overdue",
                ref="todo-2",
                status="delivered",
                delivered_at=NOW,
                expires_at=NOW + timedelta(hours=1),
            ),
            Nudge(
                id="already-dismissed",
                user_id="user-1",
                natural_key="overdue:todo-3:old",
                kind="overdue",
                ref="todo-3",
                status="dismissed",
                delivered_at=NOW - timedelta(days=4),
                dismissed_at=NOW - timedelta(days=3),
                expires_at=NOW,
            ),
        ]
    )
    await session.flush()

    expired = await expire_stale_nudges(session, now=NOW)

    assert expired == 1
    assert (await session.get(Nudge, "expired-active")).status == "expired"
    assert (await session.get(Nudge, "future-active")).status == "delivered"
    assert (await session.get(Nudge, "already-dismissed")).status == "dismissed"


async def test_recompute_failure_keeps_profile_and_does_not_block_expiry(
    session,
    monkeypatch,
):
    profile = RhythmProfile(
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
        computed_at=NOW - timedelta(days=1),
    )
    nudge = Nudge(
        id="expired-active",
        user_id="user-1",
        natural_key="overdue:todo-1:old",
        kind="overdue",
        ref="todo-1",
        status="delivered",
        delivered_at=NOW - timedelta(days=4),
        expires_at=NOW,
    )
    session.add_all([profile, nudge])
    await session.commit()

    async def fail_recompute(*args, **kwargs):
        del args, kwargs
        raise RuntimeError("temporary failure")

    monkeypatch.setattr(
        "app.domains.reka.maintenance.recompute_rhythm_profiles",
        fail_recompute,
    )

    result = await run_reka_maintenance_cycle(
        now=NOW,
        timezone_name="Asia/Shanghai",
        recompute_profiles=True,
    )

    await session.refresh(profile)
    await session.refresh(nudge)
    assert result.recompute_failed is True
    assert result.expired == 1
    assert profile.patterns_json[0]["pattern_key"] == "daily:上午"
    assert nudge.status == "expired"


async def test_scheduler_survives_a_cycle_error_and_retries(monkeypatch):
    stop_event = asyncio.Event()
    calls = 0

    async def flaky_cycle(**kwargs):
        nonlocal calls
        del kwargs
        calls += 1
        if calls == 1:
            raise RuntimeError("temporary failure")
        stop_event.set()

    monkeypatch.setattr(
        "app.domains.reka.maintenance.run_reka_maintenance_cycle",
        flaky_cycle,
    )

    await run_reka_maintenance_scheduler(
        stop_event=stop_event,
        interval_seconds=0.01,
    )

    assert calls == 2
