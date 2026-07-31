from datetime import datetime

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import DBAPIError, IntegrityError

from app.domains.reports.models import File, Report, ReportGenerationRun


NOW = datetime(2026, 7, 31, 10, 0, 0)


def _run(*, trigger_execution_id: str | None = None, state: str = "planning"):
    return ReportGenerationRun(
        user_id="user-1",
        origin="trigger" if trigger_execution_id else "user_initiated",
        trigger_execution_id=trigger_execution_id,
        state=state,
        launch_context={},
        answers={},
        evidence_scope={},
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )


def _report(run_id: str, *, title: str = "Report") -> Report:
    return Report(
        user_id="user-1",
        generation_run_id=run_id,
        title=title,
        template_id="general-period-review",
        template_version="1.0.0",
        base_family="theme_synthesis",
        content_md="# Report",
        spec_json={},
        share_card_spec={},
        tokens_used=0,
        gen_ms=0,
    )


async def test_nullable_trigger_unique_allows_manual_runs(session):
    first = _run()
    second = _run()
    session.add_all([first, second])

    await session.commit()

    assert first.id != second.id
    assert await session.scalar(
        select(func.count()).select_from(ReportGenerationRun)
    ) == 2


async def test_trigger_execution_can_back_only_one_run(session):
    session.add_all(
        [
            _run(trigger_execution_id="execution-1"),
            _run(trigger_execution_id="execution-1"),
        ]
    )

    with pytest.raises(IntegrityError):
        await session.commit()
    await session.rollback()


async def test_generation_run_can_produce_only_one_report(session):
    run = _run()
    session.add(run)
    await session.flush()
    session.add_all([_report(run.id, title="First"), _report(run.id, title="Second")])

    with pytest.raises(IntegrityError):
        await session.commit()
    await session.rollback()


async def test_file_metadata_round_trips_without_inline_content(session):
    file = File(
        user_id="user-1",
        purpose="report_illustration",
        mime_type="image/png",
        size_bytes=4,
        sha256="a" * 64,
        storage_key="reports/user-1/image.png",
    )
    session.add(file)
    await session.commit()

    loaded = await session.get(File, file.id)
    assert loaded.storage_key == "reports/user-1/image.png"
    assert loaded.size_bytes == 4
    assert not hasattr(loaded, "content")


async def test_database_rejects_unknown_run_state(session):
    session.add(_run(state="invented"))

    with pytest.raises(DBAPIError):
        await session.commit()
    await session.rollback()
