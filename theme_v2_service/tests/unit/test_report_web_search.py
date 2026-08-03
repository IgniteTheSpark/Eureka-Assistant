from datetime import datetime

import pytest

from app.domains.reports import providers as report_providers
from app.domains.reports.providers import (
    PermanentProviderError,
    RetryableProviderError,
    WebSource,
)
from app.domains.reports.schemas import TimeRange
from app.domains.reports.web_search import (
    AuthoritativeSourcesUnavailable,
    RequiredWebSearchFailed,
    build_web_queries,
    execute_web_search,
)


class FakeSearch:
    def __init__(self, *, sources=None, error=None):
        self.sources = sources or []
        self.error = error
        self.calls = 0

    async def search(self, queries):
        self.calls += 1
        if self.error:
            raise self.error
        return self.sources


def _source(url: str) -> WebSource:
    return WebSource(
        title="Source title",
        url=url,
        snippet="A qualified summary",
        accessed_at="2026-07-31T10:00:00Z",
    )


def test_query_builder_removes_names_addresses_and_raw_text():
    queries = build_web_queries(
        report_goal="为果果分析睡眠变化并参考上海市静安区南京西路 100 号",
        capabilities={"daily_log", "time_series_measurement"},
        time_range=TimeRange(
            **{
                "from": datetime(2026, 7, 1),
                "to": datetime(2026, 7, 31),
            }
        ),
        aggregate_terms=["儿童 睡眠 规律", "原始记录全文: 昨晚哭了三次"],
        sensitive_values=["果果", "上海市静安区南京西路 100 号", "昨晚哭了三次"],
    )

    serialized = " ".join(queries)
    assert "果果" not in serialized
    assert "南京西路" not in serialized
    assert "昨晚哭了三次" not in serialized
    assert "daily_log" in serialized
    assert "2026-07-01" in serialized


async def test_none_policy_never_calls_provider():
    provider = FakeSearch(sources=[_source("https://example.gov/source")])

    execution = await execute_web_search(
        policy="none",
        provider=provider,
        queries=["unused"],
    )

    assert provider.calls == 0
    assert execution.status == "not_requested"


async def test_unavailable_provider_fails_without_network_access():
    with pytest.raises(PermanentProviderError, match="not enabled"):
        await report_providers.UnavailableWebSearchProvider().search(
            ["safe query"]
        )


async def test_optional_failure_degrades_without_failing_report():
    provider = FakeSearch(error=RetryableProviderError("temporary"))

    execution = await execute_web_search(
        policy="optional",
        provider=provider,
        queries=["safe query"],
    )

    assert execution.status == "failed_degraded"
    assert execution.sources == []


async def test_required_failure_is_retryable():
    provider = FakeSearch(error=RetryableProviderError("temporary"))

    with pytest.raises(RequiredWebSearchFailed):
        await execute_web_search(
            policy="required",
            provider=provider,
            queries=["safe query"],
        )


async def test_authoritative_only_rejects_ordinary_sources_without_fallback():
    provider = FakeSearch(
        sources=[
            _source("https://commercial.example/article"),
            _source("https://health.example.gov/guidance"),
            _source("https://research.example.edu/paper"),
        ]
    )

    execution = await execute_web_search(
        policy="authoritative_only",
        provider=provider,
        queries=["safe query"],
        authoritative_domains={"example.gov", "example.edu"},
    )
    assert [item["url"] for item in execution.sources] == [
        "https://health.example.gov/guidance",
        "https://research.example.edu/paper",
    ]
    assert all(item["authoritative"] for item in execution.sources)

    with pytest.raises(AuthoritativeSourcesUnavailable):
        await execute_web_search(
            policy="authoritative_only",
            provider=FakeSearch(
                sources=[_source("https://commercial.example/article")]
            ),
            queries=["safe query"],
            authoritative_domains={"example.gov"},
        )
