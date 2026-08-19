import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from tests.fakes.auth_helpers import register_user
from app.main import app


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def _register(client: AsyncClient, email: str) -> str:
    body = await register_user(client, email, password="secret123")
    return body["token"]

def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def test_first_class_contact_crud_is_owner_scoped(client):
    owner = await _register(client, "contact-owner@example.com")
    foreign = await _register(client, "contact-foreign@example.com")

    created = await client.post(
        "/api/contacts",
        headers=_headers(owner),
        json={
            "name": "冯总",
            "company": "远山科技",
            "notes": ["行业会上认识", "行业会上认识"],
            "socials": {"wechat": "feng_88", "unknown": "drop-me"},
        },
    )
    assert created.status_code == 200
    contact = created.json()
    assert contact["notes"] == ["行业会上认识"]
    assert contact["socials"] == {"wechat": "feng_88"}
    assert contact["created_at"].endswith("Z")

    listed = await client.get(
        "/api/contacts",
        headers=_headers(owner),
        params={"name_query": "冯"},
    )
    assert [item["id"] for item in listed.json()["contacts"]] == [contact["id"]]
    assert (
        await client.get(
            f"/api/contacts/{contact['id']}", headers=_headers(foreign)
        )
    ).status_code == 404

    updated = await client.patch(
        f"/api/contacts/{contact['id']}",
        headers=_headers(owner),
        json={"title": "CEO", "notes": ["喜欢越野跑"]},
    )
    assert updated.status_code == 200
    assert updated.json()["title"] == "CEO"
    assert updated.json()["notes"] == ["喜欢越野跑"]

    invalid_name = await client.patch(
        f"/api/contacts/{contact['id']}",
        headers=_headers(owner),
        json={"name": "   "},
    )
    assert invalid_name.status_code == 422

    assert (
        await client.delete(
            f"/api/contacts/{contact['id']}", headers=_headers(foreign)
        )
    ).status_code == 404
    deleted = await client.delete(
        f"/api/contacts/{contact['id']}", headers=_headers(owner)
    )
    assert deleted.json() == {"ok": True}
    assert (
        await client.get(
            f"/api/contacts/{contact['id']}", headers=_headers(owner)
        )
    ).status_code == 404


async def test_contact_routes_require_authentication(client):
    assert (await client.get("/api/contacts")).status_code == 401
    assert (
        await client.post("/api/contacts", json={"name": "冯总"})
    ).status_code == 401
