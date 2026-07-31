from datetime import datetime, timedelta

from sqlalchemy import select

from app.domains.reports.models import File, Report, ReportGenerationRun, ReportShare
from app.domains.reports.shares import (
    create_report_share,
    get_active_share,
    hash_share_token,
    revoke_report_share,
)


NOW = datetime(2026, 7, 31, 10, 0, 0)


async def _report(session, *, user_id="user-1") -> Report:
    run = ReportGenerationRun(
        user_id=user_id,
        origin="user_initiated",
        state="completed",
        active_stage=None,
        launch_context={},
        intent="Summary",
        answers={},
        evidence_scope={},
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
        report_id="pending",
        completed_at=NOW,
    )
    session.add(run)
    await session.flush()
    report = Report(
        user_id=user_id,
        generation_run_id=run.id,
        title="Original title",
        template_id="general_period_review",
        template_version="1.0.0",
        base_family="theme_synthesis",
        content_md="# Original\n\n[evidence:asset-private]",
        html='<html><img src="/api/files/file-private">asset-private</html>',
        spec_json={
            "template_id": "general_period_review",
            "template_version": "1.0.0",
            "base_family": "theme_synthesis",
            "source_asset_ids": ["asset-private"],
            "unavailable_asset_ids": [],
            "field_bindings": {"private": "payload.secret"},
            "time_range": None,
            "external_sources": [],
            "web_policy": "none",
            "generated_file_ids": ["file-private"],
            "surface": "report",
            "palette": "calm",
            "seed": 1,
        },
        share_card_spec={
            "headline": "Original title",
            "summary": "Original summary",
            "highlights": [],
            "time_range": "2026-07",
            "illustration_file_id": "file-private",
        },
        tokens_used=0,
        gen_ms=0,
        created_at=NOW,
    )
    session.add(report)
    await session.flush()
    run.report_id = report.id
    session.add(
        File(
            id="file-private",
            user_id=user_id,
            purpose="report_illustration",
            mime_type="image/png",
            size_bytes=3,
            sha256="a" * 64,
            storage_key="reports/private.png",
        )
    )
    await session.commit()
    return report


async def test_share_persists_hash_snapshot_and_thirty_day_expiry(session):
    report = await _report(session)

    created = await create_report_share(
        session,
        user_id="user-1",
        report_id=report.id,
        now=NOW,
    )
    await session.commit()
    share = created.share

    assert share.token_hash == hash_share_token(created.token)
    assert created.token != share.token_hash
    assert created.token not in str(share.snapshot_html)
    assert share.expires_at == NOW + timedelta(days=30)
    assert list(share.media_map_json.values()) == ["file-private"]
    assert "file-private" not in share.snapshot_html
    assert "asset-private" not in share.snapshot_content_md

    report.title = "Changed title"
    report.content_md = "Changed content"
    await session.commit()
    active = await get_active_share(session, token=created.token, now=NOW)
    assert active.snapshot_content_md.startswith("# Original")


async def test_revoked_and_expired_shares_are_unavailable(session):
    report = await _report(session)
    created = await create_report_share(
        session,
        user_id="user-1",
        report_id=report.id,
        now=NOW,
    )
    await session.commit()

    assert await get_active_share(session, token=created.token, now=NOW)
    assert await revoke_report_share(
        session,
        user_id="user-1",
        share_id=created.share.id,
        now=NOW,
    )
    await session.commit()
    assert await get_active_share(session, token=created.token, now=NOW) is None

    expired = await create_report_share(
        session,
        user_id="user-1",
        report_id=report.id,
        now=NOW - timedelta(days=31),
    )
    await session.commit()
    assert await get_active_share(session, token=expired.token, now=NOW) is None


async def test_cross_user_report_and_file_never_enter_share_snapshot(session):
    report = await _report(session)
    session.add(
        File(
            id="file-other",
            user_id="user-2",
            purpose="report_illustration",
            mime_type="image/png",
            size_bytes=3,
            sha256="b" * 64,
            storage_key="reports/other.png",
        )
    )
    await session.commit()
    report.spec_json = {**report.spec_json, "generated_file_ids": ["file-other"]}
    await session.commit()

    created = await create_report_share(
        session,
        user_id="user-1",
        report_id=report.id,
        now=NOW,
    )

    assert list(created.share.media_map_json.values()) == ["file-private"]
    assert "file-other" not in created.share.media_map_json.values()
    assert await create_report_share(
        session,
        user_id="user-2",
        report_id=report.id,
        now=NOW,
    ) is None
