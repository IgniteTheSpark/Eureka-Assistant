import asyncio

from app import worker


async def test_worker_runs_primary_and_illustration_lanes(monkeypatch):
    calls = []
    stop_event = asyncio.Event()

    async def fake_run_worker(
        registry,
        *,
        stop_event,
        owner,
        include_job_types=None,
        exclude_job_types=None,
    ):
        calls.append(
            {
                "owner": owner,
                "include": include_job_types,
                "exclude": exclude_job_types,
            }
        )

    monkeypatch.setattr(worker, "run_worker", fake_run_worker)

    await worker._run_worker_lanes(stop_event=stop_event, owner="worker-1")

    assert calls == [
        {
            "owner": "worker-1:primary",
            "include": None,
            "exclude": {"report_illustration"},
        },
        {
            "owner": "worker-1:illustration",
            "include": {"report_illustration"},
            "exclude": None,
        },
    ]
