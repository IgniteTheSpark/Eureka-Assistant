from datetime import datetime, timedelta

from sqlalchemy import func, select

from app.db.models import Asset, UserSkill
from app.domains.assets.schemas import AssetCreate, UserSkillCreate
from app.domains.assets.service import create_asset, create_user_skill
from app.domains.notifications.models import Notification, OutboxEvent
from app.domains.triggers.models import (
    TriggerCountedAsset,
    TriggerExecution,
    TriggerTracker,
)
from app.domains.triggers.service import on_asset_created


START = datetime(2026, 7, 24, 10, 0, 0)
NOW = datetime(2026, 7, 31, 10, 0, 0)


async def _skill(session) -> UserSkill:
    return await create_user_skill(
        session,
        "user-1",
        UserSkillCreate(
            machine_name="notes",
            display_name="Notes",
            schema={
                "type": "object",
                "properties": {"content": {"type": "string"}},
                "required": ["content"],
                "additionalProperties": False,
            },
        ),
    )


async def _signal_asset(
    session,
    skill: UserSkill,
    *,
    now: datetime,
    marker: str,
) -> Asset:
    asset = Asset(
        user_id="user-1",
        user_skill_id=skill.id,
        payload_json={"private": marker},
        created_at=now,
        updated_at=now,
    )
    session.add(asset)
    await session.flush()
    await on_asset_created(
        session,
        asset=asset,
        now=now,
        timezone_name="Asia/Shanghai",
    )
    return asset


async def _reach_initial_threshold(session):
    skill = await _skill(session)
    assets = []
    for index in range(6):
        assets.append(
            await _signal_asset(
                session,
                skill,
                now=START + timedelta(minutes=index),
                marker=f"secret-{index}",
            )
        )
    assets.append(
        await _signal_asset(
            session,
            skill,
            now=NOW,
            marker="secret-6",
        )
    )
    return skill, assets


async def test_initial_threshold_creates_execution_and_notification(session):
    skill, assets = await _reach_initial_threshold(session)

    tracker = await session.scalar(select(TriggerTracker))
    execution = await session.scalar(select(TriggerExecution))
    notification = await session.scalar(select(Notification))

    assert tracker.scope_id == skill.id
    assert tracker.new_asset_count == 7
    assert tracker.active_execution_id == execution.id
    assert execution.revision == 1
    assert execution.last_notified_revision == 1
    assert execution.payload_json == {
        "primary_skill_id": skill.id,
        "asset_ids": [asset.id for asset in assets],
        "scope_started_at": "2026-07-24T10:00:00Z",
        "scope_ended_at": "2026-07-31T10:00:00Z",
        "asset_count": 7,
    }
    assert notification.type == "report_available"
    assert notification.link == f"report-start:{execution.id}:1"
    assert "secret" not in notification.title
    assert "secret" not in (notification.body or "")
    assert await session.scalar(
        select(func.count()).select_from(OutboxEvent)
    ) == 1


async def test_same_day_updates_revision_without_second_notification(session):
    skill, _ = await _reach_initial_threshold(session)

    eighth = await _signal_asset(
        session,
        skill,
        now=NOW + timedelta(hours=1),
        marker="secret-7",
    )
    execution = await session.scalar(select(TriggerExecution))

    assert execution.revision == 2
    assert execution.last_notified_revision == 1
    assert execution.payload_json["asset_ids"][-1] == eighth.id
    assert execution.payload_json["asset_count"] == 8
    assert await session.scalar(
        select(func.count()).select_from(Notification)
    ) == 1


async def test_next_local_day_updates_revision_and_notifies(session):
    skill, _ = await _reach_initial_threshold(session)
    await _signal_asset(
        session,
        skill,
        now=NOW + timedelta(hours=1),
        marker="secret-7",
    )

    await _signal_asset(
        session,
        skill,
        now=NOW + timedelta(days=1),
        marker="secret-8",
    )
    execution = await session.scalar(select(TriggerExecution))
    links = list(
        await session.scalars(select(Notification.link).order_by(Notification.created_at))
    )

    assert execution.revision == 3
    assert execution.last_notified_revision == 3
    assert links == [
        f"report-start:{execution.id}:1",
        f"report-start:{execution.id}:3",
    ]


async def test_duplicate_asset_signal_changes_nothing(session):
    skill, assets = await _reach_initial_threshold(session)
    execution = await session.scalar(select(TriggerExecution))

    await on_asset_created(
        session,
        asset=assets[-1],
        now=NOW + timedelta(days=1),
        timezone_name="Asia/Shanghai",
    )

    await session.refresh(execution)
    tracker = await session.scalar(select(TriggerTracker))
    assert tracker.new_asset_count == 7
    assert execution.revision == 1
    assert await session.scalar(
        select(func.count()).select_from(Notification)
    ) == 1


async def test_asset_trigger_state_rolls_back_with_outer_transaction(session):
    skill = await _skill(session)
    await _signal_asset(
        session,
        skill,
        now=START,
        marker="rollback",
    )

    await session.rollback()

    for model in (
        Asset,
        TriggerTracker,
        TriggerCountedAsset,
        TriggerExecution,
        Notification,
        OutboxEvent,
    ):
        assert await session.scalar(select(func.count()).select_from(model)) == 0


async def test_create_asset_calls_trigger_hook_inside_its_session(session):
    skill = await _skill(session)

    await create_asset(
        session,
        "user-1",
        AssetCreate(user_skill_id=skill.id, payload={"content": "one"}),
    )

    tracker = await session.scalar(select(TriggerTracker))
    assert tracker.scope_id == skill.id
    assert tracker.new_asset_count == 1
