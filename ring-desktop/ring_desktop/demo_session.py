from __future__ import annotations

import copy
import queue
import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Callable, Optional


class DemoMode(str, Enum):
    STANDALONE = "standalone"
    IDLE = "idle"
    FLASH = "flash"
    VIBE = "vibe"


@dataclass(frozen=True)
class CaptureContext:
    session_id: Optional[str]
    mode: DemoMode
    generation: int


class DemoEventBroker:
    def __init__(self):
        self._lock = threading.Lock()
        self._subscribers = set()

    def subscribe(self) -> queue.Queue:
        subscriber = queue.Queue(maxsize=64)
        with self._lock:
            self._subscribers.add(subscriber)
        return subscriber

    def unsubscribe(self, subscriber: queue.Queue) -> None:
        with self._lock:
            self._subscribers.discard(subscriber)

    def publish(self, event: str, payload: dict) -> None:
        message = copy.deepcopy({"event": event, "data": payload})
        with self._lock:
            subscribers = tuple(self._subscribers)
        for subscriber in subscribers:
            subscriber_message = copy.deepcopy(message)
            while True:
                try:
                    subscriber.put_nowait(subscriber_message)
                    break
                except queue.Full:
                    try:
                        subscriber.get_nowait()
                    except queue.Empty:
                        continue


class DemoSessionController:
    def __init__(
        self,
        now: Callable[[], float] = time.monotonic,
        lease_seconds: float = 10.0,
        events: Optional[DemoEventBroker] = None,
    ):
        if lease_seconds <= 0:
            raise ValueError("lease_seconds must be positive")
        self._now = now
        self._lease_seconds = lease_seconds
        self.events = events or DemoEventBroker()
        self._lock = threading.RLock()
        self._session_id = None
        self._mode = DemoMode.STANDALONE
        self._generation = 0
        self._lease_expires_at = None

    def acquire(self, session_id: str) -> dict:
        self._validate_session_id(session_id)
        with self._lock:
            self._expire_locked()
            self._session_id = session_id
            self._mode = DemoMode.IDLE
            self._generation += 1
            self._renew_lease_locked()
            return self._publish_mode_changed_locked()

    def heartbeat(self, session_id: str) -> bool:
        self._validate_session_id(session_id)
        with self._lock:
            self._expire_locked()
            if session_id != self._session_id:
                return False
            self._renew_lease_locked()
            return True

    def set_mode(self, session_id: str, mode: DemoMode) -> dict:
        self._validate_session_id(session_id)
        if not isinstance(mode, DemoMode) or mode is DemoMode.STANDALONE:
            raise ValueError("mode must be idle, flash, or vibe")
        with self._lock:
            self._expire_locked()
            if session_id != self._session_id:
                raise ValueError("session is not active")
            self._renew_lease_locked()
            if mode is self._mode:
                return self._snapshot_locked()
            self._mode = mode
            self._generation += 1
            return self._publish_mode_changed_locked()

    def release(self, session_id: str) -> bool:
        self._validate_session_id(session_id)
        with self._lock:
            self._expire_locked()
            if session_id != self._session_id:
                return False
            self._restore_standalone_locked()
            return True

    def tick(self) -> bool:
        with self._lock:
            return self._expire_locked()

    def capture_context(self) -> CaptureContext:
        with self._lock:
            self._expire_locked()
            return self._capture_context_locked()

    def accept_capture(self, context: CaptureContext) -> bool:
        with self._lock:
            self._expire_locked()
            return context == self._capture_context_locked()

    def snapshot(self) -> dict:
        with self._lock:
            self._expire_locked()
            return self._snapshot_locked()

    @staticmethod
    def _validate_session_id(session_id: str) -> None:
        if not isinstance(session_id, str) or not session_id.strip():
            raise ValueError("session_id must not be blank")

    def _renew_lease_locked(self) -> None:
        self._lease_expires_at = self._now() + self._lease_seconds

    def _expire_locked(self) -> bool:
        if (
            self._session_id is None
            or self._lease_expires_at is None
            or self._now() < self._lease_expires_at
        ):
            return False
        self._restore_standalone_locked()
        return True

    def _restore_standalone_locked(self) -> None:
        self._session_id = None
        self._mode = DemoMode.STANDALONE
        self._generation += 1
        self._lease_expires_at = None
        self._publish_mode_changed_locked()

    def _capture_context_locked(self) -> CaptureContext:
        return CaptureContext(self._session_id, self._mode, self._generation)

    def _snapshot_locked(self) -> dict:
        return {
            "session_id": self._session_id,
            "mode": self._mode.value,
            "generation": self._generation,
            "lease_expires_at": self._lease_expires_at,
        }

    def _publish_mode_changed_locked(self) -> dict:
        snapshot = self._snapshot_locked()
        self.events.publish("mode.changed", snapshot)
        return snapshot
