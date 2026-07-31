from datetime import datetime, timedelta

from sqlalchemy import select

from app.db.base import utc_now
from app.db.models import Asset, UserSkill
from app.db.session import AsyncSessionFactory
from app.domains.notifications.outbox import dispatch_one
from app.domains.triggers.models import TriggerExecution
from app.domains.triggers.service import on_asset_created
from app.domains.notifications.subscribers import SubscriberRegistry


START = datetime(2026, 7, 24, 10, 0, 0)
NOW = datetime(2026, 7, 31, 10, 0, 0)


async def test_worker_trigger_reaches_sse_without_creating_report_run(session):
    registry = SubscriberRegistry()
    queue = registry.subscribe("user-1")
    async with AsyncSessionFactory() as worker_session:
        skill = UserSkill(
            user_id="user-1",
            machine_name="notes",
            display_name="Notes",
            schema_json={},
        )
        worker_session.add(skill)
        await worker_session.flush()
        for index in range(7):
            signal_time = START + timedelta(minutes=index)
            if index == 6:
                signal_time = NOW
            asset = Asset(
                user_id="user-1",
                user_skill_id=skill.id,
                payload_json={"private": f"secret-{index}"},
                created_at=signal_time,
                updated_at=signal_time,
            )
            worker_session.add(asset)
            await worker_session.flush()
            await on_asset_created(
                worker_session,
                asset=asset,
                now=signal_time,
                timezone_name="Asia/Shanghai",
            )
        await worker_session.commit()

    assert await dispatch_one(AsyncSessionFactory, registry, now=utc_now())
    frame = await queue.get()

    async with AsyncSessionFactory() as check:
        execution = await check.scalar(select(TriggerExecution))
        assert frame["id"]
        assert frame["link"] == f"report-start:{execution.id}:1"
        assert "secret" not in frame["title"]
        assert "secret" not in frame["body"]
        assert execution.status == "available"
        assert execution.workflow_run_id is None
