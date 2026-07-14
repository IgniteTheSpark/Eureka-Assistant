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


@pytest.mark.parametrize(
    ("bundle", "gesture", "action"),
    [
        ("com.openai.codex", "double", {"type": "voice"}),
        ("com.openai.codex", "triple", {"type": "key", "value": "enter"}),
        ("com.openai.codex", "up", {"type": "scroll", "value": "up"}),
        ("com.openai.codex", "down", {"type": "scroll", "value": "down"}),
        ("com.alibaba.DingTalkMac", "double", {"type": "voice"}),
        (
            "com.alibaba.DingTalkMac",
            "triple",
            {"type": "key", "value": "enter"},
        ),
        ("com.alibaba.DingTalkMac", "up", {"type": "key", "value": "up"}),
        (
            "com.alibaba.DingTalkMac",
            "down",
            {"type": "key", "value": "down"},
        ),
    ],
)
def test_vibe_allows_only_the_explicit_app_gesture_actions(
    bundle, gesture, action
):
    assert app.resolve_demo_action(
        mode="vibe",
        bundle=bundle,
        gesture=gesture,
        config={bundle: {gesture: action}},
    ) == action


@pytest.mark.parametrize(
    ("bundle", "gesture", "action"),
    [
        (
            "com.openai.codex",
            "longPress",
            {"type": "key", "value": "cmd+a;backspace"},
        ),
        ("com.openai.codex", "single", {"type": "voice"}),
        ("com.openai.codex", "triple", {"type": "key", "value": "cmd+a"}),
        ("com.openai.codex", "up", {"type": "key", "value": "up"}),
        (
            "com.alibaba.DingTalkMac",
            "longPress",
            {"type": "key", "value": "cmd+a;backspace"},
        ),
        (
            "com.alibaba.DingTalkMac",
            "up",
            {"type": "scroll", "value": "up"},
        ),
    ],
)
def test_vibe_rejects_unsupported_or_repurposed_actions(bundle, gesture, action):
    assert app.resolve_demo_action(
        mode="vibe",
        bundle=bundle,
        gesture=gesture,
        config={bundle: {gesture: action}},
    ) is None


@pytest.mark.parametrize(
    ("bundle", "up_action"),
    [
        ("com.openai.codex", {"type": "scroll", "value": "up"}),
        ("com.alibaba.DingTalkMac", {"type": "key", "value": "up"}),
    ],
)
def test_serialize_mapping_hides_actions_outside_the_vibe_allowlist(
    bundle, up_action
):
    config = {
        "default": {
            "longPress": {"type": "key", "value": "cmd+a;backspace"},
            "single": {"type": "voice"},
        },
        bundle: {
            "double": {"type": "voice"},
            "triple": {"type": "key", "value": "enter"},
            "up": up_action,
            "down": {"type": "key", "value": "cmd+a"},
        },
    }

    assert app.serialize_mapping(config, bundle) == {
        "double": "Voice",
        "triple": "Enter",
        "up": "Scroll up" if bundle == "com.openai.codex" else "Up",
    }


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
    ring_app._recording_active = False
    ring_app._asr_active_count = 0
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


@pytest.mark.parametrize(
    ("source_bundle", "next_bundle"),
    [
        ("com.openai.codex", "com.apple.Safari"),
        ("com.alibaba.DingTalkMac", "com.openai.codex"),
    ],
)
def test_vibe_recording_does_not_start_after_frontmost_app_changes(
    monkeypatch, source_bundle, next_bundle
):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.VIBE)
    ring_app = _bare_ring_app(controller)
    ring_app._frontmost = source_bundle
    ring_app._rec = Recorder(on_capture=ring_app._on_capture)
    subscriber = controller.events.subscribe()

    def resolve_then_switch_app(*_args, **_kwargs):
        with ring_app._state_lock:
            ring_app._frontmost = next_bundle
        return {"type": "voice"}

    monkeypatch.setattr(app, "resolve_demo_action", resolve_then_switch_app)

    ring_app._on_gesture(2)

    assert ring_app._rec.recording is False
    assert ring_app.last == "double->-"
    with pytest.raises(queue.Empty):
        subscriber.get_nowait()


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
    "action",
    [
        {"type": "key", "value": "enter"},
        {"type": "scroll", "value": "up"},
    ],
)
@pytest.mark.parametrize(
    "next_bundle", ["com.apple.Safari", "com.alibaba.DingTalkMac"]
)
def test_vibe_non_voice_action_does_not_dispatch_after_frontmost_app_changes(
    monkeypatch, action, next_bundle
):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.VIBE)
    ring_app = _bare_ring_app(controller)
    ring_app._frontmost = "com.openai.codex"
    ring_app._rec = Recorder(on_capture=ring_app._on_capture)
    dispatched = []

    def resolve_then_switch_app(*_args, **_kwargs):
        with ring_app._state_lock:
            ring_app._frontmost = next_bundle
        return action

    monkeypatch.setattr(app, "resolve_demo_action", resolve_then_switch_app)
    monkeypatch.setattr(app, "dispatch", dispatched.append)

    ring_app._on_gesture(3)

    assert dispatched == []
    assert ring_app.last == "triple->-"


def test_vibe_dispatch_holds_frontmost_authorization_through_side_effect(
    monkeypatch,
):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.VIBE)
    ring_app = _bare_ring_app(controller)
    ring_app._frontmost = "com.openai.codex"
    ring_app._rec = Recorder(on_capture=ring_app._on_capture)
    dispatch_entered = threading.Event()
    switch_started = threading.Event()
    switch_done = threading.Event()
    order = []
    monkeypatch.setattr(
        app,
        "resolve_demo_action",
        lambda *_args, **_kwargs: {"type": "key", "value": "enter"},
    )

    def switch_frontmost_app():
        assert dispatch_entered.wait(1)
        switch_started.set()
        with ring_app._state_lock:
            ring_app._frontmost = "com.apple.Safari"
        order.append("switch")
        switch_done.set()

    switch_thread = threading.Thread(target=switch_frontmost_app)
    switch_thread.start()

    def dispatch_while_switch_waits(_action):
        dispatch_entered.set()
        assert switch_started.wait(1)
        assert switch_done.is_set() is False
        order.append("dispatch")

    monkeypatch.setattr(app, "dispatch", dispatch_while_switch_waits)

    ring_app._on_gesture(3)
    switch_thread.join(timeout=1)

    assert switch_thread.is_alive() is False
    assert order == ["dispatch", "switch"]


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


def test_vibe_asr_exception_does_not_set_failure_after_frontmost_app_changes(
    monkeypatch,
):
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

    def fail_asr(_wav):
        raise RuntimeError("ASR unavailable")

    threads = _defer_transcription(monkeypatch, fail_asr)
    ring_app._on_gesture(2)
    ring_app._rec.feed(b"adpcm")
    ring_app._on_gesture(2)
    assert len(threads) == 1
    with ring_app._state_lock:
        ring_app._frontmost = "com.apple.Safari"

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
        "recording": False,
        "asrProcessing": False,
    }


@pytest.mark.parametrize("transcript", ["captured thought", ""])
def test_demo_snapshot_tracks_recording_and_asr_through_transcript_terminal(
    monkeypatch, transcript
):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.FLASH)
    ring_app = _bare_ring_app(controller)
    ring_app._frontmost = "com.apple.Safari"
    ring_app._rec = Recorder(on_capture=ring_app._on_capture)
    monkeypatch.setattr(app, "load_config", lambda _path: {})
    threads = _defer_transcription(monkeypatch, lambda _wav: transcript)

    assert ring_app._demo_state_snapshot()["recording"] is False
    assert ring_app._demo_state_snapshot()["asrProcessing"] is False

    ring_app._on_gesture(2)

    assert ring_app._demo_state_snapshot()["recording"] is True
    assert ring_app._demo_state_snapshot()["asrProcessing"] is False

    ring_app._rec.feed(b"adpcm")
    ring_app._on_gesture(2)

    assert len(threads) == 1
    assert ring_app._demo_state_snapshot()["recording"] is False
    assert ring_app._demo_state_snapshot()["asrProcessing"] is True

    threads[0].run()

    assert ring_app._demo_state_snapshot()["recording"] is False
    assert ring_app._demo_state_snapshot()["asrProcessing"] is False


def test_activity_state_is_current_when_each_lifecycle_event_is_published(
    monkeypatch,
):
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.FLASH)
    ring_app = _bare_ring_app(controller)
    ring_app._frontmost = "com.apple.Safari"
    ring_app._rec = Recorder(on_capture=ring_app._on_capture)
    monkeypatch.setattr(app, "load_config", lambda _path: {})
    lifecycle_snapshots = {}
    real_publish = controller.events.publish

    def capture_snapshot(event, payload):
        if event in {
            "recording.started",
            "recording.stopped",
            "asr.started",
            "transcript.ready",
        }:
            lifecycle_snapshots[event] = ring_app._demo_state_snapshot()
        real_publish(event, payload)

    monkeypatch.setattr(controller.events, "publish", capture_snapshot)
    _stub_transcription(monkeypatch)

    ring_app._on_gesture(2)
    ring_app._rec.feed(b"adpcm")
    ring_app._on_gesture(2)

    assert lifecycle_snapshots["recording.started"]["recording"] is True
    assert lifecycle_snapshots["recording.stopped"]["recording"] is False
    assert lifecycle_snapshots["asr.started"]["asrProcessing"] is True
    assert lifecycle_snapshots["transcript.ready"]["asrProcessing"] is False
