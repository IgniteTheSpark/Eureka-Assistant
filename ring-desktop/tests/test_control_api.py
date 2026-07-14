import json
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import pytest

from ring_desktop.control_api import VibrationControlServer
from ring_desktop.vibration import VibrationType


def post(server, payload, path="/vibrate"):
    request = Request(
        f"http://127.0.0.1:{server.port}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=2) as response:
        return response.status, json.loads(response.read())


def get(server, path):
    with urlopen(f"http://127.0.0.1:{server.port}{path}", timeout=2) as response:
        return response.status, json.loads(response.read())


def test_vibration_request_calls_callback():
    received = []
    server = VibrationControlServer(lambda kind: received.append(kind) or True, port=0)
    server.start()
    try:
        status, body = post(server, {"type": "gradient"})
    finally:
        server.stop()

    assert status == 200
    assert body == {"ok": True, "type": "gradient"}
    assert received == [VibrationType.GRADIENT]


def test_vibration_request_rejects_unknown_type():
    server = VibrationControlServer(lambda _kind: True, port=0)
    server.start()
    try:
        with pytest.raises(HTTPError) as error:
            post(server, {"type": "unknown"})
    finally:
        server.stop()

    assert error.value.code == 400


def test_vibration_request_reports_disconnected_ring():
    server = VibrationControlServer(lambda _kind: False, port=0)
    server.start()
    try:
        with pytest.raises(HTTPError) as error:
            post(server, {"type": "continuous"})
    finally:
        server.stop()

    assert error.value.code == 409


def test_event_request_routes_app_and_event():
    received = []
    server = VibrationControlServer(
        lambda _kind: True,
        request_event=lambda app, event: received.append((app, event)) or True,
        port=0,
    )
    server.start()
    try:
        status, body = post(
            server,
            {"app": "com.openai.codex", "event": "taskComplete"},
            path="/event",
        )
    finally:
        server.stop()

    assert status == 200
    assert body == {"ok": True, "triggered": True}
    assert received == [("com.openai.codex", "taskComplete")]


def test_disabled_event_is_successful_but_not_triggered():
    server = VibrationControlServer(
        lambda _kind: True,
        request_event=lambda _app, _event: None,
        port=0,
    )
    server.start()
    try:
        status, body = post(
            server,
            {"app": "com.openai.codex", "event": "taskComplete"},
            path="/event",
        )
    finally:
        server.stop()

    assert status == 200
    assert body == {"ok": True, "triggered": False}


def test_connection_status_is_exposed():
    state = {
        "status": "connected",
        "connected": True,
        "device": {"name": "BCL60392D5", "address": "ring-id"},
        "devices": [],
        "lastError": None,
    }
    server = VibrationControlServer(
        lambda _kind: True,
        get_connection=lambda: state,
        port=0,
    ).start()
    try:
        status, body = get(server, "/connection")
    finally:
        server.stop()

    assert status == 200
    assert body == state


def test_connection_commands_route_to_callbacks():
    calls = []
    server = VibrationControlServer(
        lambda _kind: True,
        request_scan=lambda: calls.append(("scan",)) or True,
        request_connect=lambda address, name: calls.append(
            ("connect", address, name)
        ) or True,
        request_disconnect=lambda: calls.append(("disconnect",)) or True,
        port=0,
    ).start()
    try:
        assert post(server, {}, "/connection/scan")[0] == 202
        assert post(
            server,
            {"address": "ring-id", "name": "BCL60392D5"},
            "/connection/connect",
        )[0] == 202
        assert post(server, {}, "/connection/disconnect")[0] == 202
    finally:
        server.stop()

    assert calls == [
        ("scan",),
        ("connect", "ring-id", "BCL60392D5"),
        ("disconnect",),
    ]
