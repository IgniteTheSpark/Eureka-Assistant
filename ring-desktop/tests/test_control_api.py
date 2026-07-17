import http.client
import json
import socket
import threading
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import pytest

from ring_desktop.control_api import VibrationControlServer
from ring_desktop.demo_session import DemoEventBroker, DemoMode, DemoSessionController
from ring_desktop.vibration import VibrationType


def post(server, payload, path="/vibrate", headers=None):
    request_headers = {"Content-Type": "application/json"}
    if headers is not None:
        request_headers.update(headers)
    request = Request(
        f"http://127.0.0.1:{server.port}{path}",
        data=json.dumps(payload).encode(),
        headers=request_headers,
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
        self.subscribed = threading.Event()
        self.unsubscribed = threading.Event()
        self.dequeued = threading.Event()

    def subscribe(self):
        subscriber = super().subscribe()
        real_get = subscriber.get

        def observed_get(*args, **kwargs):
            message = real_get(*args, **kwargs)
            self.dequeued.set()
            return message

        subscriber.get = observed_get
        self.subscribed.set()
        return subscriber

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
        get_demo_state=lambda: {
            "activeApp": "com.openai.codex",
            "mapping": {"double": "Voice"},
            "recording": True,
            "asrProcessing": False,
        },
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
            "activeApp": "com.openai.codex",
            "mapping": {"double": "Voice"},
            "recording": True,
            "asrProcessing": False,
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


@pytest.mark.parametrize(
    "path",
    [
        "/vibrate",
        "/event",
        "/connection/scan",
        "/connection/connect",
        "/connection/disconnect",
        "/demo/session",
        "/demo/heartbeat",
        "/demo/mode",
        "/demo/release",
    ],
)
@pytest.mark.parametrize("origin", ["https://evil.example", "null"])
def test_all_browser_write_requests_reject_untrusted_origins(path, origin):
    controller = DemoSessionController(lease_seconds=30)
    server = VibrationControlServer(
        lambda _kind: True,
        request_event=lambda _app, _event: True,
        request_scan=lambda: True,
        request_connect=lambda _address, _name: True,
        request_disconnect=lambda: True,
        demo_controller=controller,
        demo_events=controller.events,
        port=0,
    ).start()
    try:
        with pytest.raises(HTTPError) as error:
            post(server, {}, path, headers={"Origin": origin})
    finally:
        server.stop()

    assert error.value.code == 403
    assert error_json(error.value) == {
        "ok": False,
        "error": "origin not allowed",
    }


def test_browser_write_requires_content_type_even_from_allowed_origin():
    received = []
    server = VibrationControlServer(
        lambda kind: received.append(kind) or True,
        port=0,
    ).start()
    try:
        connection = http.client.HTTPConnection("127.0.0.1", server.port, timeout=2)
        connection.request(
            "POST",
            "/vibrate",
            body=json.dumps({"type": "gradient"}),
            headers={"Origin": "http://localhost:5173"},
        )
        response = connection.getresponse()
        status = response.status
        body = json.loads(response.read())
        connection.close()
    finally:
        server.stop()

    assert status == 415
    assert body == {
        "ok": False,
        "error": "content type required",
    }
    assert received == []


def test_allowed_browser_send_beacon_text_plain_write_is_preserved():
    received = []
    server = VibrationControlServer(
        lambda kind: received.append(kind) or True,
        port=0,
    ).start()
    try:
        status, body = post(
            server,
            {"type": "gradient"},
            headers={
                "Origin": "http://localhost:5173",
                "Content-Type": "text/plain;charset=UTF-8",
            },
        )
    finally:
        server.stop()

    assert status == 200
    assert body == {"ok": True, "type": "gradient"}
    assert received == [VibrationType.GRADIENT]


def test_native_write_without_origin_keeps_accepting_non_browser_content_type():
    received = []
    server = VibrationControlServer(
        lambda kind: received.append(kind) or True,
        port=0,
    ).start()
    try:
        status, body = post(
            server,
            {"type": "gradient"},
            headers={"Content-Type": "text/plain"},
        )
    finally:
        server.stop()

    assert status == 200
    assert body == {"ok": True, "type": "gradient"}
    assert received == [VibrationType.GRADIENT]


@pytest.mark.parametrize("transition_before_activity_read", [False, True])
def test_demo_status_never_combines_activity_with_a_different_generation(
    transition_before_activity_read,
):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    flash_snapshot = controller.set_mode("browser-1", DemoMode.FLASH)

    def get_demo_state():
        if transition_before_activity_read:
            current = controller.set_mode("browser-1", DemoMode.VIBE)
            return {
                "recording": False,
                "asrProcessing": False,
                "_activityContext": {
                    "sessionId": current["session_id"],
                    "mode": current["mode"],
                    "generation": current["generation"],
                },
            }
        activity = {
            "recording": True,
            "asrProcessing": True,
            "_activityContext": {
                "sessionId": flash_snapshot["session_id"],
                "mode": flash_snapshot["mode"],
                "generation": flash_snapshot["generation"],
            },
        }
        controller.set_mode("browser-1", DemoMode.VIBE)
        return activity

    server = VibrationControlServer(
        lambda _kind: True,
        demo_controller=controller,
        demo_events=controller.events,
        get_demo_state=get_demo_state,
        port=0,
    ).start()
    try:
        status, body = get(server, "/demo/status")
    finally:
        server.stop()

    assert status == 200
    assert body["mode"] == "vibe"
    assert body["generation"] == 3
    assert body["recording"] is False
    assert body["asrProcessing"] is False
    assert "_activityContext" not in body


def test_demo_status_preserves_same_context_activity_without_exposing_metadata():
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    current = controller.set_mode("browser-1", DemoMode.FLASH)
    server = VibrationControlServer(
        lambda _kind: True,
        demo_controller=controller,
        demo_events=controller.events,
        get_demo_state=lambda: {
            "recording": True,
            "asrProcessing": True,
            "_activityContext": {
                "sessionId": current["session_id"],
                "mode": current["mode"],
                "generation": current["generation"],
            },
        },
        port=0,
    ).start()
    try:
        status, body = get(server, "/demo/status")
    finally:
        server.stop()

    assert status == 200
    assert body["mode"] == "flash"
    assert body["generation"] == 2
    assert body["recording"] is True
    assert body["asrProcessing"] is True
    assert "_activityContext" not in body


def test_demo_events_streams_snapshot_and_broker_events_then_unsubscribes():
    broker = TrackingDemoEventBroker()
    controller = DemoSessionController(lease_seconds=30, events=broker)
    server = VibrationControlServer(
        lambda _kind: True,
        demo_controller=controller,
        demo_events=broker,
        get_demo_state=lambda: {
            "activeApp": "com.openai.codex",
            "mapping": {"triple": "Enter"},
            "recording": False,
            "asrProcessing": True,
        },
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
                "activeApp": "com.openai.codex",
                "mapping": {"triple": "Enter"},
                "recording": False,
                "asrProcessing": True,
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
    stopped = False
    try:
        assert read_sse_event(response)[0] == "snapshot"

        server.stop()
        stopped = True

        assert broker.unsubscribed.is_set()
    finally:
        response.close()
        if not stopped:
            server.stop()


def test_server_stop_closes_stalled_demo_event_socket():
    broker = TrackingDemoEventBroker()
    controller = DemoSessionController(lease_seconds=30, events=broker)
    server = VibrationControlServer(
        lambda _kind: True,
        demo_controller=controller,
        demo_events=broker,
        port=0,
    ).start()
    client = socket.create_connection(("127.0.0.1", server.port), timeout=2)
    client.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024)
    client.sendall(
        b"GET /demo/events HTTP/1.1\r\n"
        b"Host: 127.0.0.1\r\n"
        b"Connection: keep-alive\r\n\r\n"
    )
    stopped = False
    try:
        assert broker.subscribed.wait(1)
        broker.publish("large.event", {"blob": "x" * (8 * 1024 * 1024)})
        assert broker.dequeued.wait(1)
        time.sleep(0.2)

        server.stop()
        stopped = True

        assert broker.unsubscribed.is_set()
        client.settimeout(1)
        try:
            while client.recv(65536):
                pass
        except ConnectionResetError:
            pass
        except socket.timeout:
            pytest.fail("stalled SSE socket remained open after server.stop()")
    finally:
        client.close()
        if not stopped:
            server.stop()


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
