import pytest

from app.domains.reports import providers as report_providers
from app.domains.reports.providers import (
    PermanentProviderError,
    RetryableProviderError,
    WebQuery,
    WebSource,
)
from app.domains.reports.schemas import PublicResearchBrief, ResearchEntity
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
        self.queries = []

    async def search(self, queries):
        self.calls += 1
        self.queries.append(queries)
        if self.error:
            raise self.error
        return self.sources


def _query() -> WebQuery:
    return WebQuery(
        id="web-1",
        text="皇家马德里 当前阵容",
        entity_ids=["real-madrid"],
        question_ids=["question-1"],
    )


def _source(url: str, *, title: str = "皇家马德里官方阵容") -> WebSource:
    return WebSource(
        title=title,
        url=url,
        snippet="皇家马德里公布了当前一线队阵容与球员资料。",
        accessed_at="2026-08-07T10:00:00Z",
        query_id="web-1",
        entity_ids=["real-madrid"],
        question_ids=["question-1"],
    )


def test_query_builder_uses_only_confirmed_public_entities_and_questions():
    brief = PublicResearchBrief(
        entities=[
            ResearchEntity(
                id="real-madrid",
                kind="organization",
                name="皇家马德里",
            ),
            ResearchEntity(
                id="barcelona",
                kind="organization",
                name="巴塞罗那",
            ),
            ResearchEntity(
                id="kevin",
                kind="person",
                name="Kevin",
                qualifier="Eureka CEO",
            ),
        ],
        questions=["当前一线队阵容", "球队建设策略"],
        freshness="current",
    )

    queries = build_web_queries(brief)
    serialized = " ".join(query.text for query in queries)

    assert len(queries) == 6
    assert "皇家马德里 当前一线队阵容 最新 当前" in serialized
    assert "巴塞罗那 球队建设策略 最新 当前" in serialized
    assert "Kevin Eureka CEO" in serialized
    assert "counterparty" not in serialized
    assert "free_text" not in serialized
    assert "内部预算" not in serialized
    assert all(query.entity_ids and query.question_ids for query in queries)


def test_query_builder_covers_each_competitor_before_spending_extra_queries():
    brief = PublicResearchBrief(
        entities=[
            ResearchEntity(id="plaud", kind="organization", name="Plaud"),
            ResearchEntity(id="blinq", kind="organization", name="Blinq"),
            ResearchEntity(
                id="ticnotes",
                kind="organization",
                name="TicNotes",
            ),
        ],
        questions=[
            "Plaud 的录音与总结能力",
            "Blinq 的联系人交换体验",
            "TicNotes 的会议记录能力",
        ],
        freshness="current",
    )

    queries = build_web_queries(brief)
    by_entity = {
        entity_id: [query for query in queries if query.entity_ids == [entity_id]]
        for entity_id in ("plaud", "blinq", "ticnotes")
    }

    assert all(by_entity.values())
    assert "Blinq" not in by_entity["plaud"][0].text
    assert "TicNotes" not in by_entity["plaud"][0].text
    assert "Plaud" not in by_entity["blinq"][0].text
    assert "Plaud" not in by_entity["ticnotes"][0].text
    assert by_entity["ticnotes"][0].entity_terms == ["TicNotes"]


def test_ambiguous_person_never_becomes_a_query():
    brief = PublicResearchBrief(
        entities=[
            ResearchEntity(
                id="kevin",
                kind="person",
                name="Kevin",
            )
        ],
        questions=["职业背景"],
    )

    assert build_web_queries(brief) == []


async def test_none_policy_never_calls_provider():
    provider = FakeSearch(sources=[_source("https://realmadrid.com/squad")])

    execution = await execute_web_search(
        policy="none",
        provider=provider,
        queries=[_query()],
    )

    assert provider.calls == 0
    assert execution.status == "not_requested"


async def test_unavailable_provider_fails_without_network_access():
    with pytest.raises(PermanentProviderError, match="not enabled"):
        await report_providers.UnavailableWebSearchProvider().search([_query()])


async def test_optional_failure_degrades_without_failing_report():
    provider = FakeSearch(error=RetryableProviderError("temporary"))

    execution = await execute_web_search(
        policy="optional",
        provider=provider,
        queries=[_query()],
    )

    assert execution.status == "failed_degraded"
    assert execution.sources == []


async def test_required_failure_is_retryable():
    provider = FakeSearch(error=RetryableProviderError("temporary"))

    with pytest.raises(RequiredWebSearchFailed):
        await execute_web_search(
            policy="required",
            provider=provider,
            queries=[_query()],
        )


async def test_source_qualification_rejects_url_only_http_and_irrelevant_results():
    provider = FakeSearch(
        sources=[
            _source("http://realmadrid.com/insecure"),
            _source("https://realmadrid.com/empty").model_copy(
                update={"snippet": ""}
            ),
            _source(
                "https://example.com/law",
                title="Completely unrelated commercial law",
            ).model_copy(update={"snippet": "A generic legal counterparty note."}),
        ]
    )

    execution = await execute_web_search(
        policy="optional",
        provider=provider,
        queries=[_query()],
    )

    assert execution.status == "failed_degraded"
    assert execution.sources == []


async def test_source_qualification_requires_the_confirmed_entity_name():
    query = WebQuery(
        id="web-1",
        text="Blinq 联系人交换体验 最新 当前",
        entity_ids=["blinq"],
        entity_terms=["Blinq"],
        question_ids=["question-1"],
    )
    provider = FakeSearch(
        sources=[
            WebSource(
                title="Plaud AI recording review",
                url="https://example.com/plaud",
                snippet="A detailed review of Plaud recording and summary features.",
                accessed_at="2026-08-07T10:00:00Z",
                query_id="web-1",
                entity_ids=["blinq"],
                question_ids=["question-1"],
            )
        ]
    )

    execution = await execute_web_search(
        policy="optional",
        provider=provider,
        queries=[query],
    )

    assert execution.status == "failed_degraded"
    assert execution.sources == []


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
        queries=[_query()],
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
            queries=[_query()],
            authoritative_domains={"example.gov"},
        )
