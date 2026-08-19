import pytest
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


def _binding_payload(card_sn: str = "SN-001") -> dict[str, str]:
    return {
        "card_sn": card_sn,
        "card_device_uuid": "device-uuid",
        "card_app_uuid": "app-uuid",
        "card_mac": "AA:BB",
        "card_mac_from": "android",
        "card_name": "W2",
        "card_nick": "UReka 录音卡",
    }


async def _bind(
    client: AsyncClient,
    token: str,
    card_sn: str = "SN-001",
) -> dict:
    response = await client.post(
        "/api/cards/bindings",
        headers=_headers(token),
        json=_binding_payload(card_sn),
    )
    assert response.status_code == 200
    return response.json()["binding"]


async def test_card_can_bind_list_and_unbind(client):
    token = await _register(client, "card-owner@example.com")
    headers = _headers(token)

    info = await client.post(
        "/api/cards/binding-info",
        headers=headers,
        json={"card_sn": "SN-001"},
    )
    assert info.status_code == 200
    assert info.json() == {
        "ok": True,
        "card_sn": "SN-001",
        "bindable": True,
        "state": "never_bound_by_me",
        "current_binding": None,
        "latest_user_binding": None,
        "connect_hint": None,
    }

    bound = await client.post(
        "/api/cards/bindings",
        headers=headers,
        json=_binding_payload(),
    )
    assert bound.status_code == 200
    assert bound.json()["action"] == "created"
    binding = bound.json()["binding"]
    assert binding["card_sn"] == "SN-001"
    assert binding["card_device_uuid"] == "device-uuid"
    assert binding["card_app_uuid"] == "app-uuid"
    assert binding["bind_status"] == "bound"
    assert binding["unbind_time"] is None

    listed = await client.get("/api/cards/bindings", headers=headers)
    assert listed.status_code == 200
    assert listed.json() == {"ok": True, "bindings": [binding]}

    active_info = await client.post(
        "/api/cards/binding-info",
        headers=headers,
        json={"card_sn": "SN-001"},
    )
    assert active_info.json()["state"] == "bound_by_me"
    assert active_info.json()["current_binding"] == binding
    assert active_info.json()["connect_hint"] == {
        "card_app_uuid": "app-uuid",
        "card_device_uuid": "device-uuid",
        "card_name": "W2",
        "card_mac": "AA:BB",
    }

    removed = await client.post(
        f"/api/cards/{binding['binding_id']}/unbind",
        headers=headers,
        json={"delete_data": False},
    )
    assert removed.status_code == 200
    assert removed.json()["delete_data"] is False
    assert removed.json()["binding"]["bind_status"] == "unbound"
    assert removed.json()["binding"]["unbind_time"] is not None

    replayed = await client.post(
        f"/api/cards/{binding['binding_id']}/unbind",
        headers=headers,
        json={"delete_data": False},
    )
    assert replayed.status_code == 200
    assert replayed.json()["binding"]["bind_status"] == "unbound"
    assert replayed.json()["binding"]["unbind_time"] == removed.json()["binding"][
        "unbind_time"
    ]
    assert replayed.json()["binding"]["updated_at"] == removed.json()["binding"][
        "updated_at"
    ]

    assert (await client.get("/api/cards/bindings", headers=headers)).json() == {
        "ok": True,
        "bindings": [],
    }
    previous_info = await client.post(
        "/api/cards/binding-info",
        headers=headers,
        json={"card_sn": "SN-001"},
    )
    assert previous_info.json()["state"] == "previously_bound_by_me"
    assert previous_info.json()["current_binding"] is None
    assert previous_info.json()["latest_user_binding"]["binding_id"] == binding[
        "binding_id"
    ]


async def test_foreign_active_binding_is_not_bindable(client):
    owner = await _register(client, "card-owner@example.com")
    foreign = await _register(client, "card-foreign@example.com")
    await _bind(client, owner)

    info = await client.post(
        "/api/cards/binding-info",
        headers=_headers(foreign),
        json={"card_sn": "SN-001"},
    )
    assert info.status_code == 200
    assert info.json()["state"] == "bound_by_other"
    assert info.json()["bindable"] is False
    assert info.json()["current_binding"] is None
    assert info.json()["connect_hint"] is None

    conflict = await client.post(
        "/api/cards/bindings",
        headers=_headers(foreign),
        json=_binding_payload(),
    )
    assert conflict.status_code == 409
    assert conflict.json()["detail"] == "card already bound by another user"


async def test_same_user_rebind_updates_the_active_binding(client):
    token = await _register(client, "card-owner@example.com")
    original = await _bind(client, token)
    changed = _binding_payload()
    changed.update(
        {
            "card_device_uuid": "new-device-uuid",
            "card_app_uuid": "new-app-uuid",
            "card_mac": "CC:DD",
            "card_nick": "会议卡",
        }
    )

    response = await client.post(
        "/api/cards/bindings",
        headers=_headers(token),
        json=changed,
    )
    assert response.status_code == 200
    assert response.json()["action"] == "updated"
    updated = response.json()["binding"]
    assert updated["binding_id"] == original["binding_id"]
    assert updated["card_device_uuid"] == "new-device-uuid"
    assert updated["card_app_uuid"] == "new-app-uuid"
    assert updated["card_mac"] == "CC:DD"
    assert updated["card_nick"] == "会议卡"

    listed = await client.get("/api/cards/bindings", headers=_headers(token))
    assert listed.json()["bindings"] == [updated]


async def test_foreign_user_cannot_unbind(client):
    owner = await _register(client, "card-owner@example.com")
    foreign = await _register(client, "card-foreign@example.com")
    binding = await _bind(client, owner)

    response = await client.post(
        f"/api/cards/{binding['binding_id']}/unbind",
        headers=_headers(foreign),
        json={"delete_data": True},
    )
    assert response.status_code == 404

    missing = await client.post(
        "/api/cards/00000000-0000-0000-0000-000000000001/unbind",
        headers=_headers(foreign),
        json={"delete_data": False},
    )
    assert missing.status_code == 404


@pytest.mark.parametrize(
    ("path", "payload"),
    [
        ("/api/cards/binding-info", {"card_sn": "  "}),
        ("/api/cards/bindings", {**_binding_payload(), "card_sn": ""}),
        (
            "/api/cards/bindings",
            {**_binding_payload(), "card_device_uuid": "  "},
        ),
        ("/api/cards/bindings", {**_binding_payload(), "card_app_uuid": ""}),
    ],
)
async def test_blank_required_fields_return_400(client, path, payload):
    token = await _register(client, "card-owner@example.com")
    response = await client.post(path, headers=_headers(token), json=payload)
    assert response.status_code == 400


@pytest.mark.parametrize(
    ("method", "path", "payload"),
    [
        ("POST", "/api/cards/binding-info", {"card_sn": "SN-001"}),
        ("POST", "/api/cards/bindings", _binding_payload()),
        ("GET", "/api/cards/bindings", None),
        (
            "POST",
            "/api/cards/00000000-0000-0000-0000-000000000001/unbind",
            {"delete_data": False},
        ),
    ],
)
async def test_card_routes_require_authentication(client, method, path, payload):
    response = await client.request(method, path, json=payload)
    assert response.status_code == 401
