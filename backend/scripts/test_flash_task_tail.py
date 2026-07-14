"""Regression contract for Flash task-intent background work."""

from __future__ import annotations

import asyncio

from agents import flash_pipeline, task_skill


async def test_flash_intent_requires_synchronous_task_completion() -> None:
    original = task_skill.run_task_intent
    observed: list[bool] = []

    async def fake_run_task_intent(*, wait_for_completion: bool = False, **_kwargs):
        observed.append(wait_for_completion)
        return {"ok": True, "status": "done"}

    task_skill.run_task_intent = fake_run_task_intent
    try:
        await flash_pipeline._run_intent(
            {"type": "task", "source_text": "同步到钉钉"},
            "同步到钉钉",
            "00000000-0000-0000-0000-000000000001",
            "00000000-0000-0000-0000-000000000002",
            "2026-07-14",
            "demo-user",
        )
    finally:
        task_skill.run_task_intent = original

    assert observed == [True], observed


async def test_wait_for_completion_does_not_detach_the_tail() -> None:
    dispatch = getattr(task_skill, "_dispatch_task_tail", None)
    assert dispatch is not None, "task tail dispatch helper is missing"
    started = asyncio.Event()
    release = asyncio.Event()
    finished = asyncio.Event()

    async def tail() -> None:
        started.set()
        await release.wait()
        finished.set()

    operation = asyncio.create_task(
        dispatch(tail(), wait_for_completion=True)
    )
    await asyncio.wait_for(started.wait(), timeout=2)
    await asyncio.sleep(0)
    assert not operation.done()
    assert not finished.is_set()

    release.set()
    await asyncio.wait_for(operation, timeout=2)
    assert finished.is_set()


async def main() -> None:
    await test_flash_intent_requires_synchronous_task_completion()
    await test_wait_for_completion_does_not_detach_the_tail()
    print("PASS - Flash task tails finish inside the workspace lock lifecycle")


if __name__ == "__main__":
    asyncio.run(main())
