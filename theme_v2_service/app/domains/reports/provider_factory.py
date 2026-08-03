import httpx

from app.config import Settings
from app.domains.reports.providers import (
    UnavailableWebSearchProvider,
    WebSearchProvider,
)
from app.domains.reports.providers_deepseek_web import (
    DeepSeekResponsesWebSearchProvider,
)


def build_report_web_search_provider(
    settings: Settings,
    client: httpx.AsyncClient,
) -> WebSearchProvider:
    if not settings.report_web_enabled:
        return UnavailableWebSearchProvider()
    api_key = settings.report_web_api_key_value()
    if not api_key:
        return UnavailableWebSearchProvider()
    endpoint = f"{settings.report_web_api_url.rstrip('/')}/responses"
    return DeepSeekResponsesWebSearchProvider(
        client=client,
        endpoint=endpoint,
        api_key=api_key,
        model=settings.report_web_model,
        timeout_seconds=settings.report_web_timeout_seconds,
    )
