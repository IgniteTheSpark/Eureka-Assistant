from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select
from sqlalchemy.dialects.mysql import insert as mysql_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import new_uuid
from app.db.models import Asset
from app.domains.triggers.models import (
    TriggerCountedAsset,
    TriggerExecution,
    TriggerTracker,
)
from app.domains.triggers.notifications import ensure_report_available_notification
from app.domains.triggers.proactive_summary import (
    ActiveExecutionSnapshot,
    ProactiveSnapshot,
    decide_proactive_summary,
)


class ExecutionNotFound(Exception):
    pass


class ExecutionExpired(Exception):
    pass


def _utc_z(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _tracker_query(asset: Asset):
    return select(TriggerTracker).where(
        TriggerTracker.user_id == asset.user_id,
        TriggerTracker.trigger_type == "proactive_summary",
        TriggerTracker.scope_type == "user_skill",
        TriggerTracker.scope_id == asset.user_skill_id,
    )


async def get_or_create_tracker_for_update(
    session: AsyncSession,
    *,
    asset: Asset,
    now: datetime,
) -> TriggerTracker:
    query = _tracker_query(asset).with_for_update()
    await session.execute(
        mysql_insert(TriggerTracker)
        .values(
            id=new_uuid(),
            user_id=asset.user_id,
            trigger_type="proactive_summary",
            scope_type="user_skill",
            scope_id=asset.user_skill_id,
            cycle_started_at=asset.created_at or now,
            new_asset_count=0,
            metadata_json={},
            created_at=now,
            updated_at=now,
        )
        .on_duplicate_key_update(id=TriggerTracker.id)
    )
    tracker = await session.scalar(query)
    if tracker is None:
        raise RuntimeError("trigger tracker upsert did not return a row")
    return tracker


async def _count_asset_once(
    session: AsyncSession,
    *,
    tracker: TriggerTracker,
    asset: Asset,
    now: datetime,
) -> bool:
    counted = TriggerCountedAsset(
        tracker_id=tracker.id,
        asset_id=asset.id,
        counted_at=now,
    )
    try:
        async with session.begin_nested():
            session.add(counted)
            await session.flush()
    except IntegrityError:
        return False
    return True


async def _locked_cycle_asset_ids(
    session: AsyncSession,
    tracker_id: str,
) -> list[str]:
    result = await session.scalars(
        select(TriggerCountedAsset.asset_id)
        .where(TriggerCountedAsset.tracker_id == tracker_id)
        .order_by(
            TriggerCountedAsset.counted_at,
            TriggerCountedAsset.id,
        )
        .with_for_update()
    )
    return list(result)


def _payload(
    *,
    tracker: TriggerTracker,
    asset_ids: list[str],
    now: datetime,
) -> dict:
    return {
        "primary_skill_id": tracker.scope_id,
        "asset_ids": asset_ids,
        "scope_started_at": _utc_z(tracker.cycle_started_at),
        "scope_ended_at": _utc_z(now),
        "asset_count": len(asset_ids),
    }


async def on_asset_created(
    session: AsyncSession,
    *,
    asset: Asset,
    now: datetime,
    timezone_name: str,
) -> None:
    tracker = await get_or_create_tracker_for_update(
        session,
        asset=asset,
        now=now,
    )
    if not await _count_asset_once(
        session,
        tracker=tracker,
        asset=asset,
        now=now,
    ):
        return

    asset_ids = await _locked_cycle_asset_ids(session, tracker.id)
    tracker.new_asset_count = len(asset_ids)
    execution = None
    if tracker.active_execution_id is not None:
        execution = await session.scalar(
            select(TriggerExecution)
            .where(
                TriggerExecution.id == tracker.active_execution_id,
                TriggerExecution.status == "available",
            )
            .with_for_update()
        )

    decision = decide_proactive_summary(
        ProactiveSnapshot(
            cycle_started_at=tracker.cycle_started_at,
            new_asset_count=tracker.new_asset_count,
            active_execution=(
                ActiveExecutionSnapshot(revision=execution.revision)
                if execution is not None
                else None
            ),
            last_notified_local_date=tracker.last_notified_local_date,
            dismissed_until=tracker.dismissed_until,
            proactive_suppressed_until=tracker.proactive_suppressed_until,
            new_asset_arrived=True,
        ),
        now=now,
        timezone_name=timezone_name,
    )
    payload = _payload(tracker=tracker, asset_ids=asset_ids, now=now)

    if decision.create_execution:
        execution = TriggerExecution(
            user_id=asset.user_id,
            trigger_type="proactive_summary",
            workflow_type="report_generation",
            tracker_id=tracker.id,
            scope_type="user_skill",
            scope_id=asset.user_skill_id,
            status="available",
            dedupe_key=(
                f"proactive_summary:{tracker.id}:"
                f"{tracker.cycle_started_at.isoformat()}"
            ),
            revision=1,
            payload_json=payload,
            first_fired_at=now,
            last_fired_at=now,
        )
        session.add(execution)
        await session.flush()
        tracker.active_execution_id = execution.id
    elif execution is not None and decision.next_revision is not None:
        execution.revision = decision.next_revision
        execution.payload_json = payload
        execution.last_fired_at = now

    if execution is not None and decision.should_notify:
        await ensure_report_available_notification(
            session,
            execution=execution,
            tracker=tracker,
            title=(
                f"已经积累了 {tracker.new_asset_count} 条记录，可以生成报告了"
            ),
            body=(
                f"{tracker.cycle_started_at.date().isoformat()}"
                f"—{now.date().isoformat()}"
            ),
            now=now,
            local_date=decision.notification_local_date,
        )
    await session.flush()


async def owned_execution_for_update(
    session: AsyncSession,
    *,
    user_id: str,
    execution_id: str,
) -> TriggerExecution:
    execution = await session.scalar(
        select(TriggerExecution)
        .where(
            TriggerExecution.id == execution_id,
            TriggerExecution.user_id == user_id,
        )
        .with_for_update()
    )
    if execution is None or execution.workflow_type != "report_generation":
        raise ExecutionNotFound()
    return execution


def _raise_if_expired(execution: TriggerExecution, now: datetime) -> None:
    if execution.status == "expired" or (
        execution.expires_at is not None and execution.expires_at <= now
    ):
        raise ExecutionExpired()


async def dismiss_execution(
    session: AsyncSession,
    *,
    user_id: str,
    execution_id: str,
    now: datetime,
) -> TriggerExecution:
    execution = await owned_execution_for_update(
        session,
        user_id=user_id,
        execution_id=execution_id,
    )
    _raise_if_expired(execution, now)
    if execution.status == "consumed" or execution.trigger_type != "proactive_summary":
        return execution

    if execution.tracker_id is not None:
        tracker = await session.get(
            TriggerTracker,
            execution.tracker_id,
            with_for_update=True,
        )
        if tracker is not None:
            tracker.dismissed_until = now + timedelta(days=7)
    await session.flush()
    return execution


async def consume_execution(
    session: AsyncSession,
    *,
    user_id: str,
    execution_id: str,
    workflow_run_id: str,
    now: datetime,
) -> TriggerExecution:
    execution = await owned_execution_for_update(
        session,
        user_id=user_id,
        execution_id=execution_id,
    )
    _raise_if_expired(execution, now)
    if execution.status == "consumed":
        return execution

    execution.status = "consumed"
    execution.consumed_at = now
    execution.workflow_run_id = workflow_run_id
    if execution.tracker_id is not None:
        tracker = await session.get(
            TriggerTracker,
            execution.tracker_id,
            with_for_update=True,
        )
        if tracker is not None:
            if tracker.active_execution_id == execution.id:
                tracker.active_execution_id = None
            tracker.last_consumed_at = now
            tracker.proactive_suppressed_until = now + timedelta(days=7)
            tracker.cycle_started_at = now
            tracker.new_asset_count = 0
            await session.execute(
                delete(TriggerCountedAsset).where(
                    TriggerCountedAsset.tracker_id == tracker.id
                )
            )
    await session.flush()
    return execution
