import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def _register(client: AsyncClient, email: str) -> str:
    response = await client.post(
        "/api/auth/register",
        json={"email": email, "password": "secret1"},
    )
    assert response.status_code == 200
    return response.json()["token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def test_user_skill_and_asset_crud_are_owner_scoped(client):
    owner = await _register(client, "owner@example.com")
    foreign = await _register(client, "foreign@example.com")

    skill_response = await client.post(
        "/api/user-skills",
        headers=_headers(owner),
        json={
            "machine_name": "notes",
            "display_name": "笔记",
            "description": "短笔记",
            "domain": "knowledge",
            "schema": {"content": {"type": "string"}},
        },
    )
    assert skill_response.status_code == 200
    skill = skill_response.json()
    assert skill["schema"] == {"content": {"type": "string"}}
    assert skill["created_at"].endswith("Z")

    listed_skills = await client.get(
        "/api/user-skills",
        headers=_headers(owner),
    )
    assert [item["id"] for item in listed_skills.json()] == [skill["id"]]

    asset_response = await client.post(
        "/api/assets",
        headers=_headers(owner),
        json={
            "user_skill_id": skill["id"],
            "payload": {"content": "first"},
            "effective_at": "2026-07-31T08:00:00Z",
        },
    )
    assert asset_response.status_code == 200
    asset = asset_response.json()
    assert asset["payload"] == {"content": "first"}
    assert asset["effective_at"] == "2026-07-31T08:00:00Z"

    foreign_get = await client.get(
        f"/api/assets/{asset['id']}",
        headers=_headers(foreign),
    )
    foreign_patch = await client.patch(
        f"/api/assets/{asset['id']}",
        headers=_headers(foreign),
        json={"payload": {"content": "stolen"}},
    )
    foreign_delete = await client.delete(
        f"/api/assets/{asset['id']}",
        headers=_headers(foreign),
    )
    assert foreign_get.status_code == 404
    assert foreign_patch.status_code == 404
    assert foreign_delete.status_code == 404

    updated = await client.patch(
        f"/api/assets/{asset['id']}",
        headers=_headers(owner),
        json={
            "payload": {"content": "updated"},
            "effective_at": "2026-08-01T09:30:00+08:00",
        },
    )
    assert updated.status_code == 200
    assert updated.json()["payload"] == {"content": "updated"}
    assert updated.json()["effective_at"] == "2026-08-01T01:30:00Z"

    listed_assets = await client.get(
        "/api/assets",
        headers=_headers(owner),
        params={"user_skill_id": skill["id"], "limit": 10},
    )
    assert [item["id"] for item in listed_assets.json()] == [asset["id"]]

    deleted = await client.delete(
        f"/api/assets/{asset['id']}",
        headers=_headers(owner),
    )
    missing = await client.get(
        f"/api/assets/{asset['id']}",
        headers=_headers(owner),
    )
    assert deleted.json() == {"ok": True}
    assert missing.status_code == 404


async def test_theme_v2_skill_builder_routes_draft_create_and_configure(client, monkeypatch):
    owner = await _register(client, "skill-builder@example.com")

    async def fake_draft(description, answers=None):
        assert description == "记录跑步"
        assert answers == []
        return {
            "name": "running_log",
            "display_name": "跑步记录",
            "payload_schema": {
                "distance": {
                    "type": "number",
                    "label": "距离",
                    "description": "本次跑步距离",
                    "required": True,
                    "long": False,
                }
            },
            "render_spec": {
                "icon": "🏃",
                "primary_field": "distance",
            },
            "sample_payload": {"distance": 5.2},
        }

    monkeypatch.setattr(
        "app.domains.assets.api.design_skill_draft",
        fake_draft,
        raising=False,
    )
    drafted = await client.post(
        "/api/user-skills/draft",
        headers=_headers(owner),
        json={"description": "记录跑步"},
    )
    assert drafted.status_code == 200
    assert drafted.json()["draft"]["name"] == "running_log"

    created = await client.post(
        "/api/user-skills",
        headers=_headers(owner),
        json={
            "machine_name": "running_log",
            "display_name": "跑步记录",
            "schema": {
                "type": "object",
                "properties": {
                    "distance": {"type": "number", "title": "距离"},
                },
                "required": ["distance"],
                "x-capture-enabled": True,
            },
            "render_spec": {
                "icon": "🏃",
                "primary_field": "distance",
            },
        },
    )
    assert created.status_code == 200
    skill = created.json()
    assert skill["render_spec"]["icon"] == "🏃"

    configured = await client.patch(
        f"/api/user-skills/{skill['id']}",
        headers=_headers(owner),
        json={
            "render_spec": {
                "icon": "⚡",
                "primary_field": "distance",
                "card_display": {
                    "primary_field_id": "distance",
                    "secondary_field_ids": [],
                },
            }
        },
    )
    assert configured.status_code == 200
    assert configured.json()["render_spec"]["icon"] == "⚡"


async def test_asset_list_validates_limit(client):
    token = await _register(client, "owner@example.com")

    too_small = await client.get(
        "/api/assets",
        headers=_headers(token),
        params={"limit": 0},
    )
    too_large = await client.get(
        "/api/assets",
        headers=_headers(token),
        params={"limit": 101},
    )

    assert too_small.status_code == 422
    assert too_large.status_code == 422


async def test_event_can_be_rescheduled_cancelled_and_physically_deleted(client):
    owner = await _register(client, "owner@example.com")
    foreign = await _register(client, "foreign@example.com")

    created = await client.post(
        "/api/events",
        headers=_headers(owner),
        json={
            "title": "Review",
            "description": "Theme V2 review",
            "location": "Room 1",
            "start_at": "2026-08-01T10:00:00+08:00",
            "end_at": "2026-08-01T11:00:00+08:00",
            "all_day": False,
            "status": "scheduled",
            "attendees": [{"name": "冯总"}],
        },
    )
    assert created.status_code == 200
    event = created.json()
    assert event["start_at"] == "2026-08-01T02:00:00Z"
    assert event["description"] == "Theme V2 review"
    assert event["attendees"] == [
        {
            "id": event["attendees"][0]["id"],
            "contact_id": None,
            "name_raw": "冯总",
            "display_name": "冯总",
            "is_resolved": False,
            "contact_summary": "",
            "role": "attendee",
        }
    ]

    foreign_get = await client.get(
        f"/api/events/{event['id']}",
        headers=_headers(foreign),
    )
    assert foreign_get.status_code == 404

    changed = await client.patch(
        f"/api/events/{event['id']}",
        headers=_headers(owner),
        json={
            "start_at": "2026-08-01T12:00:00+08:00",
            "end_at": "2026-08-01T13:00:00+08:00",
            "status": "cancelled",
            "attendees": [
                {"name": "冯总", "contact_id": None},
                {"name": "王总", "contact_id": "contact-asset-id"},
            ],
        },
    )
    assert changed.status_code == 200
    assert changed.json()["status"] == "cancelled"
    assert changed.json()["start_at"] == "2026-08-01T04:00:00Z"
    assert [item["display_name"] for item in changed.json()["attendees"]] == [
        "冯总",
        "王总",
    ]
    assert changed.json()["attendees"][1]["contact_id"] == "contact-asset-id"

    listed = await client.get(
        "/api/events",
        headers=_headers(owner),
        params={
            "start_from": "2026-08-01T00:00:00Z",
            "start_to": "2026-08-02T00:00:00Z",
            "limit": 10,
        },
    )
    assert [item["id"] for item in listed.json()] == [event["id"]]

    deleted = await client.delete(
        f"/api/events/{event['id']}",
        headers=_headers(owner),
    )
    missing = await client.get(
        f"/api/events/{event['id']}",
        headers=_headers(owner),
    )
    assert deleted.json() == {"ok": True}
    assert missing.status_code == 404


async def test_legacy_event_participant_phrase_is_presented_as_unresolved_attendee(client):
    owner = await _register(client, "legacy-attendee@example.com")
    created = await client.post(
        "/api/events",
        headers=_headers(owner),
        json={
            "title": "参加饭局",
            "description": "和冯总一起参加",
            "start_at": "2026-08-03T18:00:00+08:00",
            "end_at": "2026-08-03T19:00:00+08:00",
        },
    )

    assert created.status_code == 200
    event = created.json()
    assert event["description"] is None
    assert event["attendees"][0]["name_raw"] == "冯总"
    assert event["attendees"][0]["is_resolved"] is False

    loaded = await client.get(
        f"/api/events/{event['id']}",
        headers=_headers(owner),
    )
    assert loaded.json()["description"] is None
    assert loaded.json()["attendees"][0]["display_name"] == "冯总"
