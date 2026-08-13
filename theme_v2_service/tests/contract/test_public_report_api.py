from io import BytesIO
from pathlib import Path

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from PIL import Image

from app.config import get_settings
from app.domains.reports.models import File, Report, ReportGenerationRun
from app.domains.reports.storage import LocalStorage, persist_owned_file
from app.main import app

from tests.fakes.auth_helpers import register_user


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def _register(client, email):
    body = await register_user(client, email, password="secret123")
    return body["token"], body["user"]["id"]


def _headers(token):
    return {"Authorization": f"Bearer {token}"}


async def _seed_report(session, *, user_id):
    file = await persist_owned_file(
        session,
        storage=LocalStorage(Path(get_settings().media_root)),
        user_id=user_id,
        purpose="report_illustration",
        key=f"public-tests/{user_id}/image.png",
        content=b"public-image",
        mime_type="image/png",
    )
    run = ReportGenerationRun(
        user_id=user_id,
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
        completed_at=None,
    )
    session.add(run)
    await session.flush()
    report = Report(
        user_id=user_id,
        generation_run_id=run.id,
        title="Shareable",
        template_id="general_period_review",
        template_version="1.0.0",
        base_family="theme_synthesis",
        content_md="# Shareable\n\n[evidence:asset-secret]",
        html=f'<html><body>Shareable<img src="/api/files/{file.id}"></body></html>',
        spec_json={
            "template_id": "general_period_review",
            "template_version": "1.0.0",
            "base_family": "theme_synthesis",
            "source_asset_ids": ["asset-secret"],
            "unavailable_asset_ids": [],
            "field_bindings": {},
            "time_range": None,
            "external_sources": [],
            "web_policy": "none",
            "generated_file_ids": [file.id],
            "surface": "report",
            "palette": "calm",
            "seed": 1,
        },
        share_card_spec={
            "headline": "Shareable",
            "summary": "Public summary",
            "highlights": [],
            "time_range": "2026-07",
            "illustration_file_id": file.id,
        },
        tokens_used=0,
        gen_ms=0,
    )
    session.add(report)
    await session.flush()
    run.report_id = report.id
    await session.commit()
    return report, file


async def test_public_snapshot_media_isolation_and_immediate_revocation(client, session):
    owner_token, owner_id = await _register(client, "owner@example.com")
    other_token, _ = await _register(client, "other@example.com")
    report, file = await _seed_report(session, user_id=owner_id)

    cross_create = await client.post(
        f"/api/reports/{report.id}/shares",
        headers=_headers(other_token),
    )
    created = await client.post(
        f"/api/reports/{report.id}/shares",
        headers=_headers(owner_token),
    )
    assert cross_create.status_code == 404
    assert created.status_code == 200
    token = created.json()["url"].rsplit("/", 1)[-1]
    share_id = created.json()["share_id"]

    public_json = await client.get(f"/api/public/report-shares/{token}")
    public_html = await client.get(f"/r/{token}")
    serialized = str(public_json.json())
    assert public_json.status_code == 200
    assert public_html.status_code == 200
    assert public_html.headers["x-robots-tag"] == "noindex"
    share_card_url = public_json.json()["share_card_url"]
    assert share_card_url
    assert f'property="og:image" content="{share_card_url}"' in public_html.text
    share_card = await client.get(share_card_url)
    assert share_card.status_code == 200
    assert share_card.headers["content-type"] == "image/png"
    assert Image.open(BytesIO(share_card.content)).size == (1080, 1440)
    for internal in (report.id, report.generation_run_id, file.id, "asset-secret"):
        assert internal not in serialized
        assert internal not in public_html.text

    illustration = next(
        item
        for item in public_json.json()["media"]
        if item["url"] != share_card_url
    )
    media_key = illustration["key"]
    media = await client.get(illustration["url"])
    tampered = await client.get(f"/r/{token}/media/not-the-key")
    assert media.content == b"public-image"
    assert tampered.status_code == 404

    revoked = await client.delete(
        f"/api/report-shares/{share_id}",
        headers=_headers(owner_token),
    )
    assert revoked.status_code == 200
    assert (await client.get(f"/r/{token}")).status_code == 404
    assert (await client.get(f"/r/{token}/media/{media_key}")).status_code == 404
