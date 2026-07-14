import json
import logging
import queue
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable, Optional

from .demo_session import DemoEventBroker, DemoMode, DemoSessionController
from .vibration import VibrationType


log = logging.getLogger("ring_desktop.control_api")

ALLOWED_ORIGINS = {"http://localhost:5173", "http://127.0.0.1:5173"}


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
        demo_controller: Optional[DemoSessionController] = None,
        demo_events: Optional[DemoEventBroker] = None,
        get_demo_state: Optional[Callable[[], dict]] = None,
        host: str = "127.0.0.1",
        port: int = 17863,
    ):
        if host != "127.0.0.1":
            raise ValueError("control API must bind to 127.0.0.1")
        callback = request_vibration
        event_callback = request_event
        connection_callback = get_connection
        scan_callback = request_scan
        connect_callback = request_connect
        disconnect_callback = request_disconnect
        demo_state_callback = get_demo_state
        demo_event_broker = (
            demo_events
            if demo_events is not None
            else demo_controller.events if demo_controller is not None else None
        )
        sse_shutdown = threading.Event()
        sse_stop_message = object()
        sse_subscribers = set()
        sse_connections = {}
        sse_condition = threading.Condition()

        self._sse_shutdown = sse_shutdown
        self._sse_stop_message = sse_stop_message
        self._sse_subscribers = sse_subscribers
        self._sse_connections = sse_connections
        self._sse_condition = sse_condition

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == "/connection" and connection_callback is not None:
                    self._json(200, connection_callback())
                elif self.path == "/demo/status":
                    if not self._demo_enabled():
                        return
                    self._json(200, {"ok": True, **self._demo_snapshot()})
                elif self.path == "/demo/events":
                    if not self._demo_enabled(require_events=True):
                        return
                    self._handle_demo_events()
                else:
                    self._json(404, {"ok": False, "error": "not found"})

            def do_POST(self):
                if not self._authorize_browser_write():
                    return
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
                elif self.path == "/demo/session":
                    self._handle_demo_session()
                elif self.path == "/demo/heartbeat":
                    self._handle_demo_heartbeat()
                elif self.path == "/demo/mode":
                    self._handle_demo_mode()
                elif self.path == "/demo/release":
                    self._handle_demo_release()
                else:
                    self._json(404, {"ok": False, "error": "not found"})

            def _authorize_browser_write(self):
                if "Origin" not in self.headers:
                    return True
                origin = self.headers.get("Origin")
                if origin not in ALLOWED_ORIGINS:
                    self._json(403, {"ok": False, "error": "origin not allowed"})
                    return False
                content_type = self.headers.get("Content-Type", "")
                media_type = content_type.partition(";")[0].strip().lower()
                if media_type not in {"application/json", "text/plain"}:
                    self._json(415, {"ok": False, "error": "content type required"})
                    return False
                return True

            def do_OPTIONS(self):
                self.send_response(204)
                self._send_cors_headers()
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header("Access-Control-Allow-Headers", "Content-Type")
                self.send_header("Content-Length", "0")
                self.end_headers()

            def _read_json(self):
                try:
                    size = int(self.headers.get("Content-Length", "0"))
                except (TypeError, ValueError) as error:
                    raise ValueError("invalid content length") from error
                if size < 0:
                    raise ValueError("invalid content length")
                body = json.loads(self.rfile.read(size) or b"{}")
                if not isinstance(body, dict):
                    raise TypeError("JSON body must be an object")
                return body

            def _read_demo_json(self):
                try:
                    return self._read_json()
                except (ValueError, TypeError, json.JSONDecodeError):
                    self._json(400, {"ok": False, "error": "invalid JSON object"})
                    return None

            def _demo_enabled(self, require_events=False):
                if demo_controller is None or (
                    require_events and demo_event_broker is None
                ):
                    self._json(404, {"ok": False, "error": "demo disabled"})
                    return False
                return True

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

            def _handle_demo_session(self):
                if not self._demo_enabled():
                    return
                body = self._read_demo_json()
                if body is None:
                    return
                try:
                    snapshot = demo_controller.acquire(body.get("sessionId", ""))
                except (KeyError, ValueError):
                    self._json(
                        409,
                        {"ok": False, "error": "invalid demo session"},
                    )
                    return
                self._json(200, {"ok": True, **snapshot})

            def _handle_demo_heartbeat(self):
                if not self._demo_enabled():
                    return
                body = self._read_demo_json()
                if body is None:
                    return
                try:
                    accepted = demo_controller.heartbeat(body.get("sessionId", ""))
                except (KeyError, ValueError):
                    accepted = False
                if not accepted:
                    self._json(
                        409,
                        {"ok": False, "error": "invalid demo session"},
                    )
                    return
                self._json(200, {"ok": True})

            def _handle_demo_mode(self):
                if not self._demo_enabled():
                    return
                body = self._read_demo_json()
                if body is None:
                    return
                try:
                    snapshot = demo_controller.set_mode(
                        body.get("sessionId", ""), DemoMode(body.get("mode", ""))
                    )
                except (KeyError, ValueError):
                    self._json(
                        409,
                        {"ok": False, "error": "invalid demo session or mode"},
                    )
                    return
                self._json(200, {"ok": True, **snapshot})

            def _handle_demo_release(self):
                if not self._demo_enabled():
                    return
                body = self._read_demo_json()
                if body is None:
                    return
                try:
                    accepted = demo_controller.release(body.get("sessionId", ""))
                except (KeyError, ValueError):
                    accepted = False
                if not accepted:
                    self._json(
                        409,
                        {"ok": False, "error": "invalid demo session"},
                    )
                    return
                self._json(200, {"ok": True})

            def _handle_demo_events(self):
                subscriber = demo_event_broker.subscribe()
                with sse_condition:
                    if sse_shutdown.is_set():
                        demo_event_broker.unsubscribe(subscriber)
                        return
                    sse_subscribers.add(subscriber)
                    sse_connections[subscriber] = self.connection
                try:
                    self.close_connection = True
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream")
                    self.send_header("Cache-Control", "no-cache")
                    self.send_header("Connection", "keep-alive")
                    self._send_cors_headers()
                    self.end_headers()
                    snapshot = self._demo_snapshot()
                    latest_mode_generation = snapshot["generation"]
                    self._write_sse("snapshot", snapshot)
                    while not sse_shutdown.is_set():
                        try:
                            message = subscriber.get(timeout=10)
                        except queue.Empty:
                            if sse_shutdown.is_set():
                                break
                            self.wfile.write(b": heartbeat\n\n")
                            self.wfile.flush()
                            continue
                        if message is sse_stop_message or sse_shutdown.is_set():
                            break
                        if message["event"] == "mode.changed":
                            generation = message["data"].get("generation")
                            if (
                                isinstance(generation, int)
                                and generation <= latest_mode_generation
                            ):
                                continue
                            if isinstance(generation, int):
                                latest_mode_generation = generation
                        self._write_sse(message["event"], message["data"])
                except (BrokenPipeError, ConnectionResetError, OSError):
                    return
                finally:
                    try:
                        demo_event_broker.unsubscribe(subscriber)
                    finally:
                        with sse_condition:
                            sse_subscribers.discard(subscriber)
                            sse_connections.pop(subscriber, None)
                            sse_condition.notify_all()

            def _demo_snapshot(self):
                desktop_state = (
                    demo_state_callback() if demo_state_callback is not None else {}
                )
                if not isinstance(desktop_state, dict):
                    desktop_state = {}
                else:
                    desktop_state = dict(desktop_state)
                activity_context = desktop_state.pop("_activityContext", None)
                demo_state = demo_controller.snapshot()
                if activity_context is not None and activity_context != {
                    "sessionId": demo_state["session_id"],
                    "mode": demo_state["mode"],
                    "generation": demo_state["generation"],
                }:
                    desktop_state["recording"] = False
                    desktop_state["asrProcessing"] = False
                return {**desktop_state, **demo_state}

            def _write_sse(self, event, payload):
                data = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
                frame = f"event: {event}\ndata: {data}\n\n".encode()
                self.wfile.write(frame)
                self.wfile.flush()

            def _cors_origin(self):
                origin = self.headers.get("Origin")
                return origin if origin in ALLOWED_ORIGINS else None

            def _send_cors_headers(self):
                origin = self._cors_origin()
                if origin is not None:
                    self.send_header("Access-Control-Allow-Origin", origin)
                    self.send_header("Vary", "Origin")

            def _json(self, status, payload):
                data = json.dumps(payload, ensure_ascii=False).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self._send_cors_headers()
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
        self._sse_shutdown.set()
        with self._sse_condition:
            subscribers = tuple(self._sse_subscribers)
            connections = tuple(self._sse_connections.values())
        for subscriber in subscribers:
            while True:
                try:
                    subscriber.put_nowait(self._sse_stop_message)
                    break
                except queue.Full:
                    try:
                        subscriber.get_nowait()
                    except queue.Empty:
                        continue
        for connection in connections:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                connection.close()
            except OSError:
                pass
        self._server.shutdown()
        self._server.server_close()
        self._thread.join(timeout=2)
        with self._sse_condition:
            self._sse_condition.wait_for(lambda: not self._sse_subscribers)
