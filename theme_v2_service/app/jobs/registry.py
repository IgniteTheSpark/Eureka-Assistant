from collections.abc import Awaitable, Callable

from app.db.models import WorkflowJob


JobHandler = Callable[[WorkflowJob], Awaitable[None]]


class JobHandlerRegistry:
    def __init__(self) -> None:
        self._handlers: dict[str, JobHandler] = {}

    def register(self, job_type: str, handler: JobHandler) -> None:
        if job_type in self._handlers:
            raise ValueError(f"job type already registered: {job_type}")
        self._handlers[job_type] = handler

    def resolve(self, job_type: str) -> JobHandler:
        try:
            return self._handlers[job_type]
        except KeyError as exc:
            raise KeyError(f"unknown job type: {job_type}") from exc


registry = JobHandlerRegistry()
