import json
import logging
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable, Optional

from .vibration import VibrationType


log = logging.getLogger("ring_desktop.control_api")


class VibrationControlServer:
    """Local-only API used by Claude hooks and other desktop automations."""

    def __init__(
        self,
        request_vibration: Callable[[VibrationType], bool],
        request_event: Optional[Callable[[str, str], Optional[bool]]] = None,
        get_connection: Optional[Callable[[], dict]] = None,
        request_scan: Optional[Callable[[], bool]] = None,
        request_connect: Optional[Callable[[str, str], bool]] = None,
        request_disconnect: Optional[Callable[[], bool]] = None,
        host: str = "127.0.0.1",
        port: int = 17863,
    ):
        callback = request_vibration
        event_callback = request_event
        connection_callback = get_connection
        scan_callback = request_scan
        connect_callback = request_connect
        disconnect_callback = request_disconnect

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == "/connection" and connection_callback is not None:
                    self._json(200, connection_callback())
                else:
                    self._json(404, {"ok": False, "error": "not found"})

            def do_POST(self):
                if self.path == "/vibrate":
                    self._handle_vibrate()
                elif self.path == "/event":
                    self._handle_event()
                elif self.path == "/connection/scan":
                    self._handle_connection_command(scan_callback)
                elif self.path == "/connection/connect":
                    self._handle_connect()
                elif self.path == "/connection/disconnect":
                    self._handle_connection_command(disconnect_callback)
                else:
                    self._json(404, {"ok": False, "error": "not found"})

            def _read_json(self):
                size = int(self.headers.get("Content-Length", "0"))
                return json.loads(self.rfile.read(size) or b"{}")

            def _handle_vibrate(self):
                try:
                    body = self._read_json()
                    kind = VibrationType(body.get("type", "continuous"))
                except (ValueError, TypeError, json.JSONDecodeError):
                    self._json(400, {"ok": False, "error": "invalid vibration type"})
                    return
                try:
                    accepted = callback(kind)
                except Exception as error:
                    log.warning("vibration API callback failed: %s", error)
                    self._json(500, {"ok": False, "error": "internal error"})
                    return
                if not accepted:
                    self._json(409, {"ok": False, "error": "ring not connected"})
                    return
                self._json(200, {"ok": True, "type": kind.value})

            def _handle_event(self):
                if event_callback is None:
                    self._json(404, {"ok": False, "error": "event routing disabled"})
                    return
                try:
                    body = self._read_json()
                    app = body.get("app")
                    event = body.get("event")
                    if not isinstance(app, str) or not isinstance(event, str):
                        raise ValueError
                except (ValueError, TypeError, json.JSONDecodeError):
                    self._json(400, {"ok": False, "error": "invalid event"})
                    return
                try:
                    accepted = event_callback(app, event)
                except Exception as error:
                    log.warning("event API callback failed: %s", error)
                    self._json(500, {"ok": False, "error": "internal error"})
                    return
                if accepted is None:
                    self._json(200, {"ok": True, "triggered": False})
                elif accepted:
                    self._json(200, {"ok": True, "triggered": True})
                else:
                    self._json(409, {"ok": False, "error": "ring not connected"})

            def _handle_connection_command(self, command):
                if command is None:
                    self._json(404, {"ok": False, "error": "connection control disabled"})
                    return
                if command():
                    self._json(202, {"ok": True})
                else:
                    self._json(503, {"ok": False, "error": "BLE loop unavailable"})

            def _handle_connect(self):
                if connect_callback is None:
                    self._json(404, {"ok": False, "error": "connection control disabled"})
                    return
                try:
                    body = self._read_json()
                    address = body.get("address")
                    name = body.get("name")
                    if not isinstance(address, str) or not isinstance(name, str):
                        raise ValueError
                except (ValueError, TypeError, json.JSONDecodeError):
                    self._json(400, {"ok": False, "error": "invalid device"})
                    return
                if connect_callback(address, name):
                    self._json(202, {"ok": True})
                else:
                    self._json(400, {"ok": False, "error": "device not selected"})

            def _json(self, status, payload):
                data = json.dumps(payload, ensure_ascii=False).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, _format, *_args):
                return

        self._server = ThreadingHTTPServer((host, port), Handler)
        self.port = self._server.server_address[1]
        self._thread = threading.Thread(
            target=self._server.serve_forever,
            name="ring-control-api",
            daemon=True,
        )

    def start(self):
        self._thread.start()
        log.info("local control API listening on 127.0.0.1:%s", self.port)
        return self

    def stop(self):
        self._server.shutdown()
        self._server.server_close()
        self._thread.join(timeout=2)
