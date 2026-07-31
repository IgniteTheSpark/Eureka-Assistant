from collections.abc import Awaitable, Callable

from app.config import get_settings
from app.db.models import WorkflowJob
from app.domains.notifications.maintenance import (
    NOTIFICATION_PRUNE_JOB_TYPE,
    handle_notification_prune,
)


JobHandler = Callable[[WorkflowJob], Awaitable[None]]
REPORT_PLANNER_JOB_TYPE = "report_planner"
REPORT_PIPELINE_JOB_TYPE = "report_pipeline"


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
registry.register(NOTIFICATION_PRUNE_JOB_TYPE, handle_notification_prune)

_settings = get_settings()
if _settings.report_planner_enabled and _settings.report_planner_model:
    from app.domains.reports.planner import planner_handler
    from app.domains.reports.providers_litellm import LiteLLMPlannerProvider
    from app.domains.reports.templates import get_template_registry

    registry.register(
        REPORT_PLANNER_JOB_TYPE,
        planner_handler(
            provider=LiteLLMPlannerProvider(
                model=_settings.report_planner_model,
                api_key=_settings.report_provider_api_key,
                timeout_seconds=_settings.report_provider_timeout_seconds,
            ),
            registry=get_template_registry(),
        ),
    )
