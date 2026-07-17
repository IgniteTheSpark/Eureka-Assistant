import queue
import threading

import pytest

from ring_desktop.demo_session import (
    CaptureContext,
    DemoEventBroker,
    DemoMode,
    DemoSessionController,
)


def test_acquire_creates_idle_lease_and_serializable_snapshot():
    controller = DemoSessionController(now=lambda: 10.0, lease_seconds=5)

    snapshot = controller.acquire("browser-1")

    assert snapshot == {
        "session_id": "browser-1",
        "mode": "idle",
        "generation": 1,
        "lease_expires_at": 15.0,
    }


def test_acquire_rejects_blank_session_id():
    controller = DemoSessionController()

    for session_id in ("", "   "):
        with pytest.raises(ValueError):
            controller.acquire(session_id)


def test_heartbeat_only_renews_the_active_unexpired_session():
    now = [10.0]
    controller = DemoSessionController(now=lambda: now[0], lease_seconds=5)
    controller.acquire("browser-1")

    now[0] = 12.0
    assert controller.heartbeat("other-browser") is False
    assert controller.heartbeat("browser-1") is True
    assert controller.snapshot()["lease_expires_at"] == 17.0
    assert controller.snapshot()["generation"] == 1

    now[0] = 18.0
    assert controller.heartbeat("browser-1") is False
    assert controller.snapshot()["mode"] == "standalone"


def test_set_mode_requires_active_session_and_demo_mode():
    controller = DemoSessionController(now=lambda: 10.0, lease_seconds=5)
    controller.acquire("browser-1")

    with pytest.raises(ValueError):
        controller.set_mode("other-browser", DemoMode.FLASH)
    with pytest.raises(ValueError):
        controller.set_mode("browser-1", DemoMode.STANDALONE)
    with pytest.raises(ValueError):
        controller.set_mode("browser-1", "flash")


def test_mode_change_invalidates_capture():
    now = [10.0]
    controller = DemoSessionController(now=lambda: now[0], lease_seconds=5)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.FLASH)
    capture = controller.capture_context()

    snapshot = controller.set_mode("browser-1", DemoMode.VIBE)

    assert snapshot["generation"] == 3
    assert controller.accept_capture(capture) is False


def test_run_if_current_rejects_callback_after_generation_change():
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.VIBE)
    capture = controller.capture_context()
    called = []
    controller.set_mode("browser-1", DemoMode.IDLE)

    accepted = controller.run_if_current(capture, lambda: called.append("action"))

    assert accepted is False
    assert called == []


def test_run_if_current_executes_callback_for_current_generation():
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.VIBE)
    capture = controller.capture_context()
    called = []

    accepted = controller.run_if_current(capture, lambda: called.append("action"))

    assert accepted is True
    assert called == ["action"]


def test_run_if_current_holds_authorization_through_callback():
    controller = DemoSessionController(lease_seconds=30)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.VIBE)
    capture = controller.capture_context()
    callback_entered = threading.Event()
    transition_started = threading.Event()
    transition_done = threading.Event()
    order = []

    def transition_mode():
        assert callback_entered.wait(1)
        transition_started.set()
        controller.set_mode("browser-1", DemoMode.IDLE)
        order.append("transition")
        transition_done.set()

    transition_thread = threading.Thread(target=transition_mode)
    transition_thread.start()

    def authorized_action():
        callback_entered.set()
        assert transition_started.wait(1)
        assert transition_done.is_set() is False
        order.append("action")

    accepted = controller.run_if_current(capture, authorized_action)
    transition_thread.join(timeout=1)

    assert accepted is True
    assert transition_thread.is_alive() is False
    assert order == ["action", "transition"]
    assert controller.snapshot()["mode"] == "idle"


def test_setting_current_mode_renews_lease_without_changing_generation():
    now = [10.0]
    controller = DemoSessionController(now=lambda: now[0], lease_seconds=5)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.FLASH)

    now[0] = 12.0
    snapshot = controller.set_mode("browser-1", DemoMode.FLASH)

    assert snapshot["generation"] == 2
    assert snapshot["lease_expires_at"] == 17.0


def test_release_only_clears_active_session_and_invalidates_capture():
    controller = DemoSessionController(now=lambda: 10.0, lease_seconds=5)
    controller.acquire("browser-1")
    capture = controller.capture_context()

    assert controller.release("other-browser") is False
    assert controller.release("browser-1") is True
    assert controller.release("browser-1") is False
    assert controller.snapshot() == {
        "session_id": None,
        "mode": "standalone",
        "generation": 2,
        "lease_expires_at": None,
    }
    assert controller.accept_capture(capture) is False


def test_expired_lease_restores_standalone():
    now = [10.0]
    controller = DemoSessionController(now=lambda: now[0], lease_seconds=5)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.FLASH)
    now[0] = 16.0

    assert controller.tick() is True
    assert controller.tick() is False
    assert controller.snapshot()["mode"] == "standalone"
    assert controller.snapshot()["generation"] == 3


def test_capture_context_is_a_frozen_value_object():
    controller = DemoSessionController()

    context = controller.capture_context()

    assert context == CaptureContext(None, DemoMode.STANDALONE, 0)
    with pytest.raises(AttributeError):
        context.generation = 1


def test_state_changes_publish_serialized_mode_events():
    now = [10.0]
    controller = DemoSessionController(now=lambda: now[0], lease_seconds=5)
    subscriber = controller.events.subscribe()

    acquired = controller.acquire("browser-1")
    changed = controller.set_mode("browser-1", DemoMode.FLASH)
    controller.release("browser-1")

    assert subscriber.get_nowait() == {"event": "mode.changed", "data": acquired}
    assert subscriber.get_nowait() == {"event": "mode.changed", "data": changed}
    assert subscriber.get_nowait()["data"]["mode"] == "standalone"


def test_event_broker_unsubscribes_and_drops_oldest_message_when_full():
    broker = DemoEventBroker()
    subscriber = broker.subscribe()

    for number in range(65):
        broker.publish("number", {"value": number})

    assert subscriber.qsize() == 64
    assert subscriber.get_nowait()["data"] == {"value": 1}
    broker.unsubscribe(subscriber)
    broker.publish("number", {"value": 65})
    while True:
        try:
            last = subscriber.get_nowait()
        except queue.Empty:
            break
    assert last["data"] == {"value": 64}


def test_event_broker_overflow_survives_concurrent_consumer_drain():
    broker = DemoEventBroker()
    subscriber = broker.subscribe()
    for number in range(64):
        broker.publish("number", {"value": number})

    real_put_nowait = subscriber.put_nowait
    drain_happened = [False]

    def put_nowait_with_concurrent_drain(message):
        try:
            real_put_nowait(message)
        except queue.Full:
            if not drain_happened[0]:
                drain_happened[0] = True
                while True:
                    try:
                        subscriber.get_nowait()
                    except queue.Empty:
                        break
            raise

    subscriber.put_nowait = put_nowait_with_concurrent_drain

    broker.publish("number", {"value": 64})

    assert drain_happened[0] is True
    assert subscriber.get_nowait() == {
        "event": "number",
        "data": {"value": 64},
    }


def test_event_broker_isolates_caller_and_subscriber_mutations():
    broker = DemoEventBroker()
    first_subscriber = broker.subscribe()
    second_subscriber = broker.subscribe()
    payload = {"nested": {"values": ["original"]}}

    broker.publish("snapshot", payload)
    payload["nested"]["values"].append("caller mutation")
    first_message = first_subscriber.get_nowait()
    first_message["event"] = "mutated"
    first_message["data"]["nested"]["values"].append("subscriber mutation")

    assert second_subscriber.get_nowait() == {
        "event": "snapshot",
        "data": {"nested": {"values": ["original"]}},
    }
