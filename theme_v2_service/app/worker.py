import asyncio
import signal

from app.config import get_settings
from app.domains.notifications.maintenance import run_notification_prune_scheduler
from app.domains.reports.maintenance import run_report_maintenance_scheduler
from app.domains.reports.templates import get_template_registry
from app.domains.triggers.maintenance import run_trigger_maintenance_scheduler
from app.jobs.registry import registry
from app.jobs.runner import run_worker


async def serve() -> None:
    get_template_registry()
    readiness_errors = get_settings().runtime_readiness_errors()
    if readiness_errors:
        raise RuntimeError("; ".join(readiness_errors))
    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for stop_signal in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(stop_signal, stop_event.set)
    scheduler_tasks = (
        asyncio.create_task(
            run_notification_prune_scheduler(stop_event=stop_event)
        ),
        asyncio.create_task(
            run_trigger_maintenance_scheduler(stop_event=stop_event)
        ),
        asyncio.create_task(
            run_report_maintenance_scheduler(stop_event=stop_event)
        ),
    )
    try:
        await run_worker(registry, stop_event=stop_event)
    finally:
        stop_event.set()
        await asyncio.gather(*scheduler_tasks)


def main() -> None:
    asyncio.run(serve())


if __name__ == "__main__":
    main()
