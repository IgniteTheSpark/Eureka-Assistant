import json

from ring_desktop import config_window


class Response:
    def __init__(self, body):
        self.body = body

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return None

    def read(self):
        return json.dumps(self.body).encode()


def test_request_control_reads_connection_state():
    captured = {}

    def open_request(request, timeout):
        captured["url"] = request.full_url
        captured["method"] = request.method
        captured["timeout"] = timeout
        return Response({"status": "connected"})

    assert config_window.request_control("/connection", open_request=open_request) == {
        "status": "connected"
    }
    assert captured == {
        "url": "http://127.0.0.1:17863/connection",
        "method": "GET",
        "timeout": 2,
    }


def test_request_control_posts_connection_command():
    captured = {}

    def open_request(request, timeout):
        captured["body"] = json.loads(request.data)
        captured["method"] = request.method
        return Response({"ok": True})

    assert config_window.request_control(
        "/connection/connect",
        {"address": "ring-id", "name": "BCL60392D5"},
        open_request=open_request,
    ) == {"ok": True}
    assert captured == {
        "body": {"address": "ring-id", "name": "BCL60392D5"},
        "method": "POST",
    }
