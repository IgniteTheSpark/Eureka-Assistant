import json
import socket
import threading
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import pytest

from ring_desktop.control_api import VibrationControlServer
from ring_desktop.demo_session import DemoEventBroker, DemoMode, DemoSessionController
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


def error_json(error):
    return json.loads(error.read())


def read_sse_event(response):
    event = None
    data = None
    while True:
        line = response.readline().decode().rstrip("\r\n")
        if not line:
            return event, json.loads(data)
        if line.startswith("event: "):
            event = line.removeprefix("event: ")
        elif line.startswith("data: "):
            data = line.removeprefix("data: ")


class TrackingDemoEventBroker(DemoEventBroker):
    def __init__(self):
        super().__init__()
        self.unsubscribed = threading.Event()

    def unsubscribe(self, subscriber):
        super().unsubscribe(subscriber)
        self.unsubscribed.set()


class SubscribeHookDemoEventBroker(TrackingDemoEventBroker):
    def __init__(self):
        super().__init__()
        self.on_subscribe = None

    def subscribe(self):
        subscriber = super().subscribe()
        if self.on_subscribe is not None:
            self.on_subscribe()
        return subscriber


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


def test_demo_endpoints_manage_session_lifecycle():
    controller = DemoSessionController(now=lambda: 10.0, lease_seconds=30)
    server = VibrationControlServer(
        lambda _kind: True,
        demo_controller=controller,
        demo_events=controller.events,
        port=0,
    ).start()
    try:
        status, body = get(server, "/demo/status")
        assert status == 200
        assert body == {
            "ok": True,
            "session_id": None,
            "mode": "standalone",
            "generation": 0,
            "lease_expires_at": None,
        }

        status, body = post(server, {"sessionId": "browser-1"}, "/demo/session")
        assert status == 200
        assert body["mode"] == "idle"

        status, body = post(
            server,
            {"sessionId": "browser-1", "mode": "flash"},
            "/demo/mode",
        )
        assert status == 200
        assert body["mode"] == "flash"

        assert post(server, {"sessionId": "browser-1"}, "/demo/heartbeat") == (
            200,
            {"ok": True},
        )
        assert post(server, {"sessionId": "browser-1"}, "/demo/release") == (
            200,
            {"ok": True},
        )
        assert get(server, "/demo/status")[1]["mode"] == "standalone"
    finally:
        server.stop()


@pytest.mark.parametrize(
    ("path", "payload", "error_message"),
    [
        ("/demo/session", {}, "invalid demo session"),
        ("/demo/session", [], "invalid JSON object"),
        ("/demo/heartbeat", {"sessionId": "other"}, "invalid demo session"),
        (
            "/demo/mode",
            {"sessionId": "browser-1", "mode": "standalone"},
            "invalid demo session or mode",
        ),
        ("/demo/release", {"sessionId": "other"}, "invalid demo session"),
    ],
)
def test_demo_endpoints_reject_invalid_requests(path, payload, error_message):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    server = VibrationControlServer(
        lambda _kind: True,
        demo_controller=controller,
        demo_events=controller.events,
        port=0,
    ).start()
    try:
        with pytest.raises(HTTPError) as error:
            post(server, payload, path)
    finally:
        server.stop()

    assert error.value.code in {400, 409}
    assert error_json(error.value) == {"ok": False, "error": error_message}


def test_demo_routes_are_disabled_without_controller():
    server = VibrationControlServer(lambda _kind: True, port=0).start()
    try:
        with pytest.raises(HTTPError) as error:
            get(server, "/demo/status")
    finally:
        server.stop()

    assert error.value.code == 404
    assert error_json(error.value) == {"ok": False, "error": "demo disabled"}


def test_options_and_demo_response_return_only_allowed_local_cors_origin():
    controller = DemoSessionController()
    server = VibrationControlServer(
        lambda _kind: True,
        demo_controller=controller,
        demo_events=controller.events,
        port=0,
    ).start()
    try:
        request = Request(
            f"http://127.0.0.1:{server.port}/demo/status",
            method="OPTIONS",
            headers={
                "Origin": "http://localhost:5173",
                "Access-Control-Request-Headers": "content-type",
                "Access-Control-Request-Method": "GET",
            },
        )
        with urlopen(request, timeout=2) as response:
            assert response.status == 204
            assert (
                response.headers["Access-Control-Allow-Origin"]
                == "http://localhost:5173"
            )
            assert response.headers["Access-Control-Allow-Methods"] == (
                "GET, POST, OPTIONS"
            )
            assert response.headers["Access-Control-Allow-Headers"] == "Content-Type"

        request = Request(
            f"http://127.0.0.1:{server.port}/demo/status",
            headers={"Origin": "http://127.0.0.1:5173"},
        )
        with urlopen(request, timeout=2) as response:
            assert (
                response.headers["Access-Control-Allow-Origin"]
                == "http://127.0.0.1:5173"
            )

        request = Request(
            f"http://127.0.0.1:{server.port}/demo/status",
            method="OPTIONS",
            headers={"Origin": "https://example.com"},
        )
        with urlopen(request, timeout=2) as response:
            assert response.headers["Access-Control-Allow-Origin"] is None
    finally:
        server.stop()


def test_demo_events_streams_snapshot_and_broker_events_then_unsubscribes():
    broker = TrackingDemoEventBroker()
    controller = DemoSessionController(lease_seconds=30, events=broker)
    server = VibrationControlServer(
        lambda _kind: True,
        demo_controller=controller,
        demo_events=broker,
        port=0,
    ).start()
    response = None
    try:
        request = Request(
            f"http://127.0.0.1:{server.port}/demo/events",
            headers={"Origin": "http://localhost:5173"},
        )
        response = urlopen(request, timeout=2)
        assert response.headers["Content-Type"] == "text/event-stream"
        assert response.headers["Cache-Control"] == "no-cache"
        assert response.headers["Access-Control-Allow-Origin"] == (
            "http://localhost:5173"
        )
        assert read_sse_event(response) == (
            "snapshot",
            {
                "session_id": None,
                "mode": "standalone",
                "generation": 0,
                "lease_expires_at": None,
            },
        )

        changed = controller.acquire("browser-1")
        assert read_sse_event(response) == ("mode.changed", changed)

        response.fp.raw._sock.shutdown(socket.SHUT_RDWR)
        response.close()
        response = None
        for _ in range(3):
            broker.publish("disconnect.probe", {})
            if broker.unsubscribed.wait(0.2):
                break
        assert broker.unsubscribed.is_set()
    finally:
        if response is not None:
            response.close()
        server.stop()


def test_server_stop_unsubscribes_open_demo_event_stream():
    broker = TrackingDemoEventBroker()
    controller = DemoSessionController(lease_seconds=30, events=broker)
    server = VibrationControlServer(
        lambda _kind: True,
        demo_controller=controller,
        demo_events=broker,
        port=0,
    ).start()
    response = urlopen(
        f"http://127.0.0.1:{server.port}/demo/events",
        timeout=2,
    )
    try:
        assert read_sse_event(response)[0] == "snapshot"

        server.stop()

        assert broker.unsubscribed.is_set()
    finally:
        response.close()


def test_demo_events_filters_mode_event_already_covered_by_snapshot():
    broker = SubscribeHookDemoEventBroker()
    controller = DemoSessionController(lease_seconds=30, events=broker)
    broker.on_subscribe = lambda: controller.acquire("browser-1")
    server = VibrationControlServer(
        lambda _kind: True,
        demo_controller=controller,
        demo_events=broker,
        port=0,
    ).start()
    response = None
    try:
        response = urlopen(
            f"http://127.0.0.1:{server.port}/demo/events",
            timeout=2,
        )
        snapshot_event, snapshot = read_sse_event(response)
        assert snapshot_event == "snapshot"
        assert snapshot["generation"] == 1

        changed = controller.set_mode("browser-1", DemoMode.FLASH)

        assert read_sse_event(response) == ("mode.changed", changed)
        assert changed["generation"] > snapshot["generation"]
    finally:
        if response is not None:
            response.close()
        server.stop()


def test_server_rejects_non_loopback_bind_address():
    with pytest.raises(ValueError, match="127.0.0.1"):
        VibrationControlServer(lambda _kind: True, host="0.0.0.0", port=0)
