from collections.abc import Awaitable, Callable

from app.config import get_settings
from app.db.models import WorkflowJob
from app.domains.capture.asr import TencentS3AsrProvider
from app.domains.capture.jobs import CAPTURE_ASR_JOB_TYPE, capture_asr_handler
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
registry.register(
    CAPTURE_ASR_JOB_TYPE,
    capture_asr_handler(
        TencentS3AsrProvider(
            base_url=_settings.tencent_asr_service_base_url,
            timeout_seconds=_settings.capture_provider_timeout_seconds,
        ),
        poll_interval_seconds=_settings.capture_asr_poll_interval_seconds,
        poll_timeout_seconds=_settings.capture_asr_poll_timeout_seconds,
    ),
)
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

if _settings.report_pipeline_enabled and _settings.report_generator_model:
    import httpx
    from pathlib import Path

    from app.domains.reports.pipeline import report_pipeline_handler
    from app.domains.reports.providers import UnavailableIllustrationProvider
    from app.domains.reports.providers_image import (
        OpenAICompatibleIllustrationProvider,
    )
    from app.domains.reports.providers_litellm import LiteLLMGeneratorProvider
    from app.domains.reports.providers_web import ConfiguredWebSearchProvider
    from app.domains.reports.storage import LocalStorage
    from app.domains.reports.templates import get_template_registry

    async def handle_configured_report_pipeline(job: WorkflowJob) -> None:
        async with httpx.AsyncClient() as client:
            illustration = UnavailableIllustrationProvider()
            if (
                _settings.report_illustration_model
                and _settings.report_illustration_api_url
                and _settings.report_provider_api_key
            ):
                illustration = OpenAICompatibleIllustrationProvider(
                    client=client,
                    endpoint=_settings.report_illustration_api_url,
                    api_key=_settings.report_provider_api_key,
                    model=_settings.report_illustration_model,
                    timeout_seconds=_settings.report_provider_timeout_seconds,
                )
            handler = report_pipeline_handler(
                generator=LiteLLMGeneratorProvider(
                    model=_settings.report_generator_model,
                    api_key=_settings.report_provider_api_key,
                    timeout_seconds=_settings.report_provider_timeout_seconds,
                ),
                web_search=ConfiguredWebSearchProvider(
                    client=client,
                    bocha_api_key=_settings.bocha_api_key,
                    bocha_endpoint=_settings.bocha_api_url,
                    tavily_api_key=_settings.tavily_api_key,
                    tavily_endpoint=_settings.tavily_api_url,
                    timeout_seconds=_settings.report_web_timeout_seconds,
                ),
                illustration=illustration,
                registry=get_template_registry(),
                storage=LocalStorage(Path(_settings.media_root)),
            )
            await handler(job)

    registry.register(
        REPORT_PIPELINE_JOB_TYPE,
        handle_configured_report_pipeline,
    )
