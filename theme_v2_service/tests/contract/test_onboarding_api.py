"""Onboarding backend contract tests (§6)."""
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.auth.email_sender import get_verification_sender
from app.auth.models import ONBOARDING_COMPLETED, ONBOARDING_SKIPPED, UserAccount
from app.db.models import Asset, UserSkill
from app.db.session import AsyncSessionFactory
from app.main import app
from tests.fakes.auth_helpers import register_user


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _authed_user(client, email: str = "onb@example.com") -> tuple[str, str]:
    registered = await register_user(client, email)
    return registered["token"], registered["user"]["id"]


async def _create_running_skill(client, token: str) -> str:
    response = await client.post(
        "/api/onboarding/skills",
        headers=_headers(token),
        json={
            "category": "running",
            "fields": [
                {"key": "distance_km", "label": "距离(公里)", "type": "number"},
                {"key": "duration_min", "label": "时长(分钟)", "type": "duration"},
            ],
        },
    )
    assert response.status_code == 200, response.text
    return response.json()["skill"]["id"]


async def test_catalog_contains_required_categories(client):
    response = await client.get("/api/onboarding/catalog")

    assert response.status_code == 200
    body = response.json()
    categories = {item["id"] for item in body["categories"]}
    assert {"running", "drinking_water", "baby_feeding", "dancing"} <= categories
    running = next(item for item in body["categories"] if item["id"] == "running")
    assert len(running["fields"]) == 3
    assert running["hint"]


async def test_catalog_does_not_require_auth(client):
    response = await client.get("/api/onboarding/catalog")
    assert response.status_code == 200


async def test_suggest_fields_returns_curated_fields(client):
    response = await client.post(
        "/api/onboarding/suggest-fields", json={"category": "running"}
    )
    assert response.status_code == 200
    assert len(response.json()["fields"]) == 3


async def test_suggest_fields_unknown_category_returns_empty(client):
    response = await client.post(
        "/api/onboarding/suggest-fields", json={"category": "totally-unknown"}
    )
    assert response.status_code == 200
    assert response.json()["fields"] == []


async def test_skill_creation_is_idempotent(client):
    token, _ = await _authed_user(client, "idem@example.com")
    skill_id = await _create_running_skill(client, token)

    response = await client.post(
        "/api/onboarding/skills",
        headers=_headers(token),
        json={
            "category": "running",
            "fields": [
                {"key": "distance_km", "label": "距离(公里)", "type": "number"},
                {"key": "duration_min", "label": "时长(分钟)", "type": "duration"},
            ],
        },
    )
    assert response.status_code == 200
    assert response.json()["skill"]["id"] == skill_id
    assert response.json()["created"] is False


async def test_skill_creation_requires_auth(client):
    response = await client.post(
        "/api/onboarding/skills",
        json={"category": "running", "fields": []},
    )
    assert response.status_code == 401


async def test_preview_extracts_and_never_creates_asset(client):
    token, _ = await _authed_user(client, "prev@example.com")
    skill_id = await _create_running_skill(client, token)

    response = await client.post(
        "/api/onboarding/preview",
        headers=_headers(token),
        json={
            "user_skill_id": skill_id,
            "source_text": "我今天沿着河边跑了5公里,用了32分钟。",
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["payload"]["distance_km"] == "5"
    assert body["payload"]["duration_min"] == "32"

    async with AsyncSessionFactory() as database:
        from sqlalchemy import text
        rows = (await database.execute(text(
            "SELECT COUNT(*) FROM assets WHERE user_id = "
            "(SELECT id FROM user_accounts WHERE email='prev@example.com')"
        ))).scalar_one()
    assert rows == 0


async def test_preview_fallback_to_manual_fields(client):
    token, _ = await _authed_user(client, "manual@example.com")
    skill_id = await _create_running_skill(client, token)

    response = await client.post(
        "/api/onboarding/preview",
        headers=_headers(token),
        json={"user_skill_id": skill_id, "source_text": "今天天气不错。"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["payload"] is None
    assert len(body["manual_fields"]) >= 2
    assert body["field_warnings"]


async def test_preview_unknown_skill_returns_404(client):
    token, _ = await _authed_user(client, "miss@example.com")

    response = await client.post(
        "/api/onboarding/preview",
        headers=_headers(token),
        json={"user_skill_id": "missing-skill", "source_text": "hello"},
    )
    assert response.status_code == 404


async def test_confirm_creates_one_asset_and_is_idempotent(client):
    token, user_id = await _authed_user(client, "conf@example.com")
    skill_id = await _create_running_skill(client, token)

    payload = {"distance_km": 5, "duration_min": 32}
    response = await client.post(
        "/api/onboarding/confirm",
        headers=_headers(token),
        json={
            "skill_id": skill_id,
            "payload": payload,
            "idempotency_key": "conf-key-1",
        },
    )
    assert response.status_code == 200, response.text
    first_asset_id = response.json()["asset_id"]
    assert response.json()["created"] is True

    duplicate = await client.post(
        "/api/onboarding/confirm",
        headers=_headers(token),
        json={
            "skill_id": skill_id,
            "payload": payload,
            "idempotency_key": "conf-key-1",
        },
    )
    assert duplicate.status_code == 200
    assert duplicate.json()["asset_id"] == first_asset_id
    assert duplicate.json()["created"] is False

    async with AsyncSessionFactory() as database:
        count = (
            await database.execute(
                Asset.__table__.select().where(Asset.user_id == user_id)
            )
        ).scalars().all()
    assert len(list(count)) == 1


async def test_skip_marks_onboarding_skipped(client):
    token, _ = await _authed_user(client, "skip@example.com")

    response = await client.post(
        "/api/onboarding/skip",
        headers=_headers(token),
        json={"idempotency_key": "skip-key-1"},
    )
    assert response.status_code == 200
    assert response.json()["onboarding_status"] == ONBOARDING_SKIPPED

    from sqlalchemy import select
    async with AsyncSessionFactory() as database:
        user = await database.scalar(
            select(UserAccount).where(UserAccount.email == "skip@example.com")
        )
    assert user.onboarding_status == ONBOARDING_SKIPPED


async def test_confirm_does_not_mark_onboarding_completed(client):
    # §6.9: confirm creates the Asset; the durable onboarding->completed
    # transition is driven by the front-end flow (E3). Confirm must not
    # prematurely flip pending->completed by itself.
    token, _ = await _authed_user(client, "keep@example.com")
    skill_id = await _create_running_skill(client, token)

    await client.post(
        "/api/onboarding/confirm",
        headers=_headers(token),
        json={
            "skill_id": skill_id,
            "payload": {"distance_km": 5, "duration_min": 32},
            "idempotency_key": "keep-key-1",
        },
    )

    from sqlalchemy import select
    async with AsyncSessionFactory() as database:
        user = await database.scalar(
            select(UserAccount).where(UserAccount.email == "keep@example.com")
        )
    assert user.onboarding_status != ONBOARDING_COMPLETED
