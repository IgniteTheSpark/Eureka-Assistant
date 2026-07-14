import queue
import threading

import pytest

from ring_desktop import app
from ring_desktop.demo_session import DemoMode, DemoSessionController
from ring_desktop.recorder import Recorder


def test_status_icon_stays_compact():
    assert app.status_icon("connected", recording=False) == "🟢"
    assert app.status_icon("scanning", recording=False) == "⚪️"
    assert app.status_icon("connected", recording=True) == "🎙"


def test_flash_forces_double_tap_voice_without_app_mapping():
    action = app.resolve_demo_action(
        mode="flash", bundle="com.apple.Safari", gesture="double", config={}
    )

    assert action == {"type": "voice"}


def test_flash_suppresses_non_voice_gestures():
    action = app.resolve_demo_action(
        mode="flash",
        bundle="com.apple.Safari",
        gesture="triple",
        config={"default": {"triple": {"type": "key", "value": "enter"}}},
    )

    assert action is None


def test_vibe_rejects_unsupported_frontmost_app():
    action = app.resolve_demo_action(
        mode="vibe",
        bundle="com.apple.Safari",
        gesture="triple",
        config={"default": {"triple": {"type": "key", "value": "enter"}}},
    )

    assert action is None


@pytest.mark.parametrize(
    "bundle", ["com.openai.codex", "com.alibaba.DingTalkMac"]
)
def test_vibe_resolves_actions_for_supported_frontmost_apps(bundle):
    action = app.resolve_demo_action(
        mode="vibe",
        bundle=bundle,
        gesture="triple",
        config={"default": {"triple": {"type": "key", "value": "enter"}}},
    )

    assert action == {"type": "key", "value": "enter"}


def test_idle_suppresses_all_gestures():
    action = app.resolve_demo_action(
        mode="idle",
        bundle="com.openai.codex",
        gesture="triple",
        config={"default": {"triple": {"type": "key", "value": "enter"}}},
    )

    assert action is None


def test_standalone_keeps_config_routing():
    action = app.resolve_demo_action(
        mode="standalone",
        bundle="com.apple.Safari",
        gesture="triple",
        config={"default": {"triple": {"type": "key", "value": "enter"}}},
    )

    assert action == {"type": "key", "value": "enter"}


def _bare_ring_app(controller=None):
    ring_app = object.__new__(app.RingApp)
    ring_app._demo = controller or DemoSessionController(lease_seconds=30)
    ring_app._state_lock = threading.RLock()
    ring_app._frontmost = None
    ring_app._mapping = {}
    ring_app._capture_context = None
    ring_app.last = "-"
    ring_app.status = "starting"
    return ring_app


def _next_event(subscriber):
    return subscriber.get_nowait()


@pytest.mark.parametrize("next_mode", [DemoMode.IDLE, DemoMode.FLASH])
def test_vibe_recording_does_not_start_after_mode_transition(
    monkeypatch, next_mode
):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.VIBE)
    ring_app = _bare_ring_app(controller)
    ring_app._frontmost = "com.openai.codex"
    ring_app._rec = Recorder(on_capture=ring_app._on_capture)

    def resolve_then_transition(*_args, **_kwargs):
        controller.set_mode("browser-1", next_mode)
        return {"type": "voice"}

    monkeypatch.setattr(app, "resolve_demo_action", resolve_then_transition)

    ring_app._on_gesture(2)

    assert controller.snapshot()["mode"] == next_mode.value
    assert ring_app._rec.recording is False


@pytest.mark.parametrize("next_mode", [DemoMode.IDLE, DemoMode.FLASH])
def test_vibe_recording_does_not_stop_after_mode_transition(
    monkeypatch, next_mode
):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.VIBE)
    ring_app = _bare_ring_app(controller)
    ring_app._frontmost = "com.openai.codex"
    ring_app._rec = Recorder(on_capture=ring_app._on_capture)
    ring_app._rec.start()
    ring_app._capture_context = app.VoiceCaptureContext(
        controller.capture_context(), "com.openai.codex"
    )

    def resolve_then_transition(*_args, **_kwargs):
        controller.set_mode("browser-1", next_mode)
        return {"type": "voice"}

    monkeypatch.setattr(app, "resolve_demo_action", resolve_then_transition)

    ring_app._on_gesture(2)

    assert controller.snapshot()["mode"] == next_mode.value
    assert ring_app._rec.recording is True


@pytest.mark.parametrize("next_mode", [DemoMode.IDLE, DemoMode.FLASH])
def test_vibe_non_voice_action_does_not_dispatch_after_mode_transition(
    monkeypatch, next_mode
):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.VIBE)
    ring_app = _bare_ring_app(controller)
    ring_app._frontmost = "com.openai.codex"
    ring_app._rec = Recorder(on_capture=ring_app._on_capture)
    dispatched = []

    def resolve_then_transition(*_args, **_kwargs):
        controller.set_mode("browser-1", next_mode)
        return {"type": "key", "value": "enter"}

    monkeypatch.setattr(app, "resolve_demo_action", resolve_then_transition)
    monkeypatch.setattr(app, "dispatch", dispatched.append)

    ring_app._on_gesture(3)

    assert controller.snapshot()["mode"] == next_mode.value
    assert dispatched == []


@pytest.mark.parametrize(
    ("mode", "bundle", "config"),
    [
        (DemoMode.FLASH, "com.apple.Safari", {}),
        (
            DemoMode.VIBE,
            "com.openai.codex",
            {"com.openai.codex": {"double": {"type": "voice"}}},
        ),
    ],
)
def test_flash_and_vibe_emit_recording_events_immediately(
    monkeypatch, mode, bundle, config
):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", mode)
    ring_app = _bare_ring_app(controller)
    ring_app._frontmost = bundle
    ring_app._rec = Recorder(on_capture=ring_app._on_capture)
    subscriber = controller.events.subscribe()
    monkeypatch.setattr(app, "load_config", lambda _path: config)

    ring_app._on_gesture(2)

    assert ring_app._rec.recording is True
    assert _next_event(subscriber) == {
        "event": "recording.started",
        "data": {
            "sessionId": "browser-1",
            "generation": 2,
            "mode": mode.value,
        },
    }

    ring_app._on_gesture(2)

    assert ring_app._rec.recording is False
    assert _next_event(subscriber) == {
        "event": "recording.stopped",
        "data": {
            "sessionId": "browser-1",
            "generation": 2,
            "mode": mode.value,
        },
    }


def test_timeout_emits_recording_stopped_even_for_empty_capture(monkeypatch):
    now = [0.0]
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.FLASH)
    ring_app = _bare_ring_app(controller)
    ring_app._frontmost = "com.apple.Safari"
    ring_app._rec = Recorder(
        on_capture=ring_app._on_capture,
        max_dur=1.0,
        now=lambda: now[0],
    )
    subscriber = controller.events.subscribe()
    monkeypatch.setattr(app, "load_config", lambda _path: {})

    ring_app._on_gesture(2)
    assert _next_event(subscriber)["event"] == "recording.started"

    now[0] = 2.0
    ring_app._on_recorder_tick()

    assert ring_app._rec.recording is False
    assert _next_event(subscriber)["event"] == "recording.stopped"


class _ImmediateThread:
    def __init__(self, target, args=(), daemon=None):
        self._target = target
        self._args = args

    def start(self):
        self._target(*self._args)


class _DeferredThread(_ImmediateThread):
    def start(self):
        return None

    def run(self):
        self._target(*self._args)


def _stub_transcription(monkeypatch, text="captured thought"):
    monkeypatch.setattr(app.threading, "Thread", _ImmediateThread)
    monkeypatch.setattr(app.audio, "decode_adpcm", lambda payload: b"pcm:" + payload)
    monkeypatch.setattr(app.audio, "write_wav_temp", lambda pcm: "capture.wav")
    monkeypatch.setattr(app.asr, "transcribe", lambda wav: text)


def _defer_transcription(monkeypatch, transcribe):
    threads = []

    def create_thread(*args, **kwargs):
        thread = _DeferredThread(*args, **kwargs)
        threads.append(thread)
        return thread

    monkeypatch.setattr(app.threading, "Thread", create_thread)
    monkeypatch.setattr(app.audio, "decode_adpcm", lambda payload: b"pcm:" + payload)
    monkeypatch.setattr(app.audio, "write_wav_temp", lambda pcm: "capture.wav")
    monkeypatch.setattr(app.asr, "transcribe", transcribe)
    return threads


def test_flash_capture_publishes_stamped_transcript_without_injecting(monkeypatch):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.FLASH)
    ring_app = _bare_ring_app(controller)
    ring_app._capture_context = app.VoiceCaptureContext(
        controller.capture_context(), "com.apple.Safari"
    )
    subscriber = controller.events.subscribe()
    injected = []
    _stub_transcription(monkeypatch)
    monkeypatch.setattr(app, "type_text", injected.append)

    ring_app._on_capture(b"adpcm")

    assert _next_event(subscriber) == {
        "event": "asr.started",
        "data": {
            "sessionId": "browser-1",
            "generation": 2,
            "mode": "flash",
        },
    }
    assert _next_event(subscriber) == {
        "event": "transcript.ready",
        "data": {
            "sessionId": "browser-1",
            "generation": 2,
            "mode": "flash",
            "text": "captured thought",
        },
    }
    assert injected == []


@pytest.mark.parametrize("mode", [DemoMode.VIBE, DemoMode.STANDALONE])
def test_vibe_and_standalone_capture_inject_text(monkeypatch, mode):
    controller = DemoSessionController(lease_seconds=30)
    if mode is DemoMode.VIBE:
        controller.acquire("browser-1")
        controller.set_mode("browser-1", mode)
    ring_app = _bare_ring_app(controller)
    source_bundle = "com.openai.codex" if mode is DemoMode.VIBE else None
    ring_app._frontmost = source_bundle
    ring_app._capture_context = app.VoiceCaptureContext(
        controller.capture_context(), source_bundle
    )
    subscriber = controller.events.subscribe()
    injected = []
    _stub_transcription(monkeypatch)
    monkeypatch.setattr(app, "type_text", injected.append)

    ring_app._on_capture(b"adpcm")

    assert _next_event(subscriber)["event"] == "asr.started"
    assert injected == ["captured thought"]
    with pytest.raises(queue.Empty):
        subscriber.get_nowait()


def test_stale_capture_is_discarded_after_mode_change(monkeypatch):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.FLASH)
    ring_app = _bare_ring_app(controller)
    ring_app._capture_context = app.VoiceCaptureContext(
        controller.capture_context(), "com.apple.Safari"
    )
    controller.set_mode("browser-1", DemoMode.VIBE)
    subscriber = controller.events.subscribe()
    injected = []
    _stub_transcription(monkeypatch)
    monkeypatch.setattr(app, "type_text", injected.append)

    ring_app._on_capture(b"adpcm")

    assert _next_event(subscriber)["event"] == "asr.started"
    assert injected == []
    assert ring_app.last == "-"
    with pytest.raises(queue.Empty):
        subscriber.get_nowait()


def test_vibe_capture_does_not_inject_after_frontmost_app_changes(monkeypatch):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.VIBE)
    ring_app = _bare_ring_app(controller)
    ring_app._frontmost = "com.openai.codex"
    ring_app._rec = Recorder(on_capture=ring_app._on_capture)
    monkeypatch.setattr(
        app,
        "load_config",
        lambda _path: {
            "com.openai.codex": {"double": {"type": "voice"}}
        },
    )
    injected = []
    monkeypatch.setattr(app, "type_text", injected.append)
    threads = _defer_transcription(monkeypatch, lambda _wav: "captured thought")

    ring_app._on_gesture(2)
    ring_app._rec.feed(b"adpcm")
    ring_app._on_gesture(2)
    assert len(threads) == 1

    ring_app._frontmost = "com.apple.Safari"
    threads[0].run()

    assert injected == []
    assert ring_app.last == "double->🎙停"


def test_stale_asr_exception_does_not_set_visible_failure(monkeypatch):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.FLASH)
    ring_app = _bare_ring_app(controller)
    ring_app._frontmost = "com.apple.Safari"
    ring_app._rec = Recorder(on_capture=ring_app._on_capture)
    monkeypatch.setattr(app, "load_config", lambda _path: {})

    def fail_asr(_wav):
        raise RuntimeError("ASR unavailable")

    threads = _defer_transcription(monkeypatch, fail_asr)
    ring_app._on_gesture(2)
    ring_app._rec.feed(b"adpcm")
    ring_app._on_gesture(2)
    assert len(threads) == 1
    controller.set_mode("browser-1", DemoMode.IDLE)

    threads[0].run()

    assert ring_app.last == "double->🎙停"


def test_status_change_publishes_real_connection_snapshot():
    controller = DemoSessionController(lease_seconds=30)
    ring_app = _bare_ring_app(controller)
    ring_app._ble = type(
        "FakeBLE",
        (),
        {
            "connection_state": lambda self: {
                "status": "connected",
                "connected": True,
                "device": {"name": "Ring", "address": "AA:BB"},
                "devices": [],
                "lastError": None,
            }
        },
    )()
    subscriber = controller.events.subscribe()

    ring_app._on_status("connected")

    assert _next_event(subscriber) == {
        "event": "connection.changed",
        "data": ring_app._ble.connection_state(),
    }


def test_frontmost_events_publish_only_when_bundle_changes(monkeypatch):
    controller = DemoSessionController(lease_seconds=30)
    ring_app = _bare_ring_app(controller)
    ring_app._open_config_requested = threading.Event()
    ring_app._rec = type("FakeRecorder", (), {"recording": False})()
    ring_app._menu = {
        "打开配置…": type("FakeMenuItem", (), {"title": ""})()
    }
    config = {
        "com.openai.codex": {
            "double": {"type": "voice"},
            "triple": {"type": "key", "value": "enter"},
        }
    }
    bundles = iter(
        ["com.openai.codex", "com.openai.codex", "com.apple.Safari"]
    )
    monkeypatch.setattr(app, "frontmost_bundle_id", lambda: next(bundles))
    monkeypatch.setattr(app, "load_config", lambda _path: config)
    subscriber = controller.events.subscribe()

    ring_app._refresh(None)
    ring_app._refresh(None)
    ring_app._refresh(None)

    assert [_next_event(subscriber) for _ in range(4)] == [
        {
            "event": "active_app.changed",
            "data": {"activeApp": "com.openai.codex"},
        },
        {
            "event": "mapping.changed",
            "data": {
                "mapping": {
                    "double": "Voice",
                    "triple": "Enter",
                }
            },
        },
        {
            "event": "active_app.changed",
            "data": {"activeApp": "com.apple.Safari"},
        },
        {"event": "mapping.changed", "data": {"mapping": {}}},
    ]
    with pytest.raises(queue.Empty):
        subscriber.get_nowait()


def test_demo_state_snapshot_exposes_cached_active_app_and_mapping():
    ring_app = _bare_ring_app()
    ring_app._frontmost = "com.openai.codex"
    ring_app._mapping = {"double": "Voice", "triple": "Enter"}

    assert ring_app._demo_state_snapshot() == {
        "activeApp": "com.openai.codex",
        "mapping": {"double": "Voice", "triple": "Enter"},
    }
