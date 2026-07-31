from datetime import datetime, timedelta
from io import BytesIO

from PIL import Image

from app.domains.reports.models import Report, ReportGenerationRun, ReportShare
from app.domains.reports.share_cards import render_share_card
from app.domains.reports.shares import generate_share_card_for_share
from app.domains.reports.storage import LocalStorage


NOW = datetime(2026, 7, 31, 10, 0, 0)


async def _share(session):
    run = ReportGenerationRun(
        user_id="user-1",
        origin="user_initiated",
        state="completed",
        launch_context={},
        intent="Summary",
        answers={},
        evidence_scope={},
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
        completed_at=NOW,
    )
    session.add(run)
    await session.flush()
    report = Report(
        user_id="user-1",
        generation_run_id=run.id,
        title="Complete",
        template_id="general_period_review",
        template_version="1.0.0",
        base_family="theme_synthesis",
        content_md="# Complete",
        html="<html>Complete</html>",
        spec_json={},
        share_card_spec={
            "headline": "七月复盘",
            "summary": "本月变化清晰。",
            "highlights": ["稳定推进"],
            "time_range": "2026 年 7 月",
            "illustration_file_id": None,
        },
        tokens_used=0,
        gen_ms=0,
        created_at=NOW,
    )
    session.add(report)
    await session.flush()
    run.report_id = report.id
    share = ReportShare(
        report_id=report.id,
        user_id="user-1",
        token_hash="a" * 64,
        status="active",
        expires_at=NOW + timedelta(days=30),
        snapshot_content_md=report.content_md,
        snapshot_spec_json={"share_card": report.share_card_spec},
        snapshot_html=report.html,
        media_map_json={},
        created_at=NOW,
    )
    session.add(share)
    await session.commit()
    return run, report, share


async def test_share_card_is_stored_and_authorized_by_share_media_map(session, tmp_path):
    _, _, share = await _share(session)
    storage = LocalStorage(tmp_path / "media")

    file = await generate_share_card_for_share(
        session,
        share=share,
        token="raw-token",
        public_base_url="https://reports.example",
        storage=storage,
    )
    await session.commit()

    assert file.purpose == "report_share_card"
    assert share.share_card_file_id == file.id
    assert file.id in share.media_map_json.values()
    image = Image.open(BytesIO(await storage.get(file.storage_key)))
    assert image.size == (1080, 1440)


async def test_card_failure_preserves_completed_report_and_retry_succeeds(
    session,
    tmp_path,
):
    run, report, share = await _share(session)
    storage = LocalStorage(tmp_path / "media")

    def fail(*args, **kwargs):
        raise RuntimeError("font unavailable")

    failed = await generate_share_card_for_share(
        session,
        share=share,
        token="raw-token",
        public_base_url="https://reports.example",
        storage=storage,
        renderer=fail,
    )
    await session.commit()
    assert failed is None
    assert run.state == "completed"
    assert report.id == run.report_id
    assert share.share_card_file_id is None
    assert "share card generation failed" in share.snapshot_spec_json["warnings"]

    retried = await generate_share_card_for_share(
        session,
        share=share,
        token="raw-token",
        public_base_url="https://reports.example",
        storage=storage,
        renderer=render_share_card,
    )
    await session.commit()
    assert retried is not None
    assert share.share_card_file_id == retried.id
