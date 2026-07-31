import asyncio
import signal

from app.jobs.registry import registry
from app.jobs.runner import run_worker


async def serve() -> None:
    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for stop_signal in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(stop_signal, stop_event.set)
    await run_worker(registry, stop_event=stop_event)


def main() -> None:
    asyncio.run(serve())


if __name__ == "__main__":
    main()
