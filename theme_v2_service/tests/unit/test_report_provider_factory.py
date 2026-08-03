import httpx

from app.config import Settings
from app.domains.reports.provider_factory import (
    build_report_web_search_provider,
)
from app.domains.reports.providers import UnavailableWebSearchProvider
from app.domains.reports.providers_deepseek_web import (
    DeepSeekResponsesWebSearchProvider,
)
async def test_factory_returns_unavailable_provider_when_search_is_disabled():
    settings = Settings(jwt_secret="test-secret", report_web_enabled=False)
    async with httpx.AsyncClient() as client:
        provider = build_report_web_search_provider(settings, client)
        assert isinstance(provider, UnavailableWebSearchProvider)


async def test_factory_builds_deepseek_provider_with_effective_key():
    settings = Settings(
        jwt_secret="test-secret",
        report_web_enabled=True,
        report_provider_api_key="shared-secret",
        report_web_api_key="",
        report_web_api_url="https://api.deepseek.test",
    )
    async with httpx.AsyncClient() as client:
        provider = build_report_web_search_provider(settings, client)
        assert isinstance(provider, DeepSeekResponsesWebSearchProvider)
        assert provider.endpoint == "https://api.deepseek.test/responses"
        assert provider.api_key == "shared-secret"
        assert provider.model == "deepseek-v4-flash"
