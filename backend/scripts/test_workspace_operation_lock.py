"""Failure-path contract for the MySQL workspace named-lock wrapper."""

from __future__ import annotations

import asyncio

from core import workspace_operation_lock


class _ConnectHandle:
    def __init__(self, connection):
        self.connection = connection

    def __await__(self):
        async def resolve():
            return self.connection

        return resolve().__await__()

    async def __aenter__(self):
        return self.connection

    async def __aexit__(self, _exc_type, _exc, _tb):
        self.connection.closed = True
        return False


class _FakeEngine:
    def __init__(self, connection):
        self.connection = connection

    def connect(self):
        return _ConnectHandle(self.connection)


class _ReleaseFailureConnection:
    def __init__(self):
        self.calls = 0
        self.invalidated = False
        self.closed = False

    async def scalar(self, _statement, _params):
        self.calls += 1
        if self.calls == 1:
            return 1
        raise RuntimeError("release failed")

    async def invalidate(self):
        self.invalidated = True


class _CancellableReleaseConnection:
    def __init__(self):
        self.calls = 0
        self.invalidated = False
        self.closed = False
        self.release_started = asyncio.Event()
        self.allow_release = asyncio.Event()
        self.released = False

    async def scalar(self, _statement, _params):
        self.calls += 1
        if self.calls == 1:
            return 1
        self.release_started.set()
        await self.allow_release.wait()
        self.released = True
        return 1

    async def invalidate(self):
        self.invalidated = True


async def _with_fake_engine(connection, operation):
    original = workspace_operation_lock.async_engine
    workspace_operation_lock.async_engine = _FakeEngine(connection)
    try:
        return await operation()
    finally:
        workspace_operation_lock.async_engine = original


async def test_release_failure_invalidates_connection_without_masking_success() -> None:
    connection = _ReleaseFailureConnection()

    async def operation():
        async with workspace_operation_lock.user_workspace_operation("user-1"):
            pass

    await _with_fake_engine(connection, operation)
    assert connection.invalidated
    assert connection.closed


async def test_cancellation_cannot_interrupt_release() -> None:
    connection = _CancellableReleaseConnection()

    async def operation():
        async with workspace_operation_lock.user_workspace_operation("user-2"):
            pass

    task = asyncio.create_task(_with_fake_engine(connection, operation))
    await asyncio.wait_for(connection.release_started.wait(), timeout=2)
    task.cancel()
    await asyncio.sleep(0)
    connection.allow_release.set()
    try:
        await asyncio.wait_for(task, timeout=2)
    except asyncio.CancelledError:
        pass
    else:
        raise AssertionError("cancelled operation did not remain cancelled")

    assert connection.released
    assert connection.closed


async def main() -> None:
    await test_release_failure_invalidates_connection_without_masking_success()
    await test_cancellation_cannot_interrupt_release()
    print("PASS - workspace lock release is failure- and cancellation-safe")


if __name__ == "__main__":
    asyncio.run(main())
