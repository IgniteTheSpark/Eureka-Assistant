import asyncio
from types import TracebackType

import pytest

from app.auth import maintenance


class _Session:
    def __init__(self) -> None:
        self.commits = 0

    async def __aenter__(self) -> "_Session":
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        return None

    async def commit(self) -> None:
        self.commits += 1


@pytest.mark.asyncio
async def test_challenge_cleanup_scheduler_runs_once_before_stop(monkeypatch):
    stop_event = asyncio.Event()
    session = _Session()
    cleanup_calls = 0

    class _Factory:
        def __call__(self) -> _Session:
            return session

    async def _cleanup(_session: _Session) -> int:
        nonlocal cleanup_calls
        cleanup_calls += 1
        stop_event.set()
        return 1

    monkeypatch.setattr(maintenance, "AsyncSessionFactory", _Factory())
    monkeypatch.setattr(maintenance, "cleanup_expired", _cleanup)

    await maintenance.run_challenge_cleanup_scheduler(
        stop_event=stop_event,
        interval_seconds=3600,
    )

    assert cleanup_calls == 1
    assert session.commits == 1
