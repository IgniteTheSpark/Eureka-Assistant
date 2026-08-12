from datetime import datetime
import asyncio
import json

import httpx
import pytest

from app.domains.reports.providers import (
    PermanentProviderError,
    RetryableProviderError,
    WebQuery,
)
from app.domains.reports.providers_deepseek_web import (
    DeepSeekResponsesWebSearchProvider,
)


def _provider(
    client: httpx.AsyncClient,
) -> DeepSeekResponsesWebSearchProvider:
    return DeepSeekResponsesWebSearchProvider(
        client=client,
        endpoint="https://api.deepseek.test/responses",
        api_key="deepseek-secret",
        model="deepseek-v4-flash",
        timeout_seconds=12,
        clock=lambda: datetime(2026, 8, 3, 10, 0, 0),
    )


def _query(text: str, *, query_id: str = "web-1") -> WebQuery:
    return WebQuery(
        id=query_id,
        text=text,
        entity_ids=["entity-1"],
        question_ids=["question-1"],
    )


async def test_provider_forces_web_search_and_normalizes_citations():
    requests: list[httpx.Request] = []

    def handle(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json={
                "output": [
                    {
                        "type": "web_search_call",
                        "action": {
                            "sources": [
                                {
                                    "title": "Official guidance",
                                    "url": "https://example.gov/guide",
                                    "snippet": "Official summary",
                                }
                            ]
                        },
                    },
                    {
                        "type": "message",
                        "content": [
                            {
                                "type": "output_text",
                                "text": "Research result",
                                "annotations": [
                                    {
                                        "type": "url_citation",
                                        "title": "Research paper",
                                        "url": "https://example.edu/paper",
                                        "start_index": 0,
                                        "end_index": 15,
                                    },
                                    {
                                        "type": "url_citation",
                                        "title": "Duplicate",
                                        "url": "https://example.gov/guide",
                                    },
                                ],
                            }
                        ],
                    },
                ]
            },
        )

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(handle)
    ) as client:
        sources = await _provider(client).search([_query("safe aggregate query")])

    assert len(requests) == 1
    assert requests[0].headers["authorization"] == "Bearer deepseek-secret"
    assert json.loads(requests[0].content) == {
        "model": "deepseek-v4-flash",
        "input": (
            "Search the public web for the following topic. Return a concise "
            "answer with verifiable URL citations. Topic: safe aggregate query"
        ),
        "tools": [{"type": "web_search"}],
        "tool_choice": {"type": "web_search"},
        "include": ["web_search_call.action.sources"],
    }
    assert [source.url for source in sources] == [
        "https://example.gov/guide",
        "https://example.edu/paper",
    ]
    assert sources[0].accessed_at == "2026-08-03T10:00:00Z"
    assert sources[0].query_id == "web-1"
    assert sources[0].entity_ids == ["entity-1"]
    assert sources[1].snippet == "Research result"


async def test_provider_calls_once_per_query_and_keeps_stable_url_order():
    requests: list[httpx.Request] = []

    def handle(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        query = json.loads(request.content)["input"]
        suffix = "one" if query.endswith("query one") else "two"
        return httpx.Response(
            200,
            json={
                "output": [
                    {
                        "type": "web_search_call",
                        "action": {
                            "sources": [
                                {
                                    "title": suffix,
                                    "url": f"https://example.com/{suffix}",
                                    "snippet": suffix,
                                }
                            ]
                        },
                    }
                ]
            },
        )

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(handle)
    ) as client:
        sources = await _provider(client).search(
            [_query("query one", query_id="web-1"), _query("query two", query_id="web-2")]
        )

    assert len(requests) == 2
    assert [source.url for source in sources] == [
        "https://example.com/one",
        "https://example.com/two",
    ]


async def test_provider_runs_queries_with_bounded_concurrency():
    class ConcurrentProvider(DeepSeekResponsesWebSearchProvider):
        active = 0
        max_active = 0
        first_wave_started = asyncio.Event()

        async def _request(self, query: str):
            self.active += 1
            self.max_active = max(self.max_active, self.active)
            if self.active == 3:
                self.first_wave_started.set()
            await asyncio.wait_for(self.first_wave_started.wait(), timeout=0.5)
            self.active -= 1
            return {
                "output": [
                    {
                        "type": "web_search_call",
                        "action": {
                            "sources": [
                                {
                                    "title": query,
                                    "url": f"https://example.com/{query}",
                                    "snippet": f"Public result for {query}",
                                }
                            ]
                        },
                    }
                ]
            }

    async with httpx.AsyncClient() as client:
        provider = ConcurrentProvider(
            client=client,
            endpoint="https://api.deepseek.test/responses",
            api_key="deepseek-secret",
        )
        sources = await provider.search(
            [
                _query(f"query-{index}", query_id=f"web-{index}")
                for index in range(1, 7)
            ]
        )

    assert provider.max_active == 3
    assert [source.query_id for source in sources] == [
        "web-1",
        "web-2",
        "web-3",
        "web-4",
        "web-5",
        "web-6",
    ]


async def test_provider_keeps_successful_sources_when_one_query_fails():
    class PartialProvider(DeepSeekResponsesWebSearchProvider):
        async def _request(self, query: str):
            if query == "query two":
                raise RetryableProviderError("one query timed out")
            return {
                "output": [
                    {
                        "type": "web_search_call",
                        "action": {
                            "sources": [
                                {
                                    "title": query,
                                    "url": f"https://example.com/{query[-3:]}",
                                    "snippet": f"Public result for {query}",
                                }
                            ]
                        },
                    }
                ]
            }

    async with httpx.AsyncClient() as client:
        provider = PartialProvider(
            client=client,
            endpoint="https://api.deepseek.test/responses",
            api_key="deepseek-secret",
        )
        sources = await provider.search(
            [
                _query("query one", query_id="web-1"),
                _query("query two", query_id="web-2"),
                _query("query three", query_id="web-3"),
            ]
        )

    assert [source.query_id for source in sources] == ["web-1", "web-3"]


async def test_provider_raises_when_all_queries_fail():
    class FailingProvider(DeepSeekResponsesWebSearchProvider):
        async def _request(self, query: str):
            del query
            raise RetryableProviderError("all queries timed out")

    async with httpx.AsyncClient() as client:
        provider = FailingProvider(
            client=client,
            endpoint="https://api.deepseek.test/responses",
            api_key="deepseek-secret",
        )
        with pytest.raises(RetryableProviderError, match="all queries"):
            await provider.search(
                [
                    _query("query one", query_id="web-1"),
                    _query("query two", query_id="web-2"),
                ]
            )


async def test_provider_rejects_deepseek_open_page_action_without_evidence():
    def handle(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "output": [
                    {
                        "type": "reasoning",
                        "content": [
                            {"type": "reasoning_text", "text": "redacted"}
                        ],
                    },
                    {
                        "type": "web_search_call",
                        "action": {
                            "type": "open_page",
                            "url": "https://openai.com/",
                        },
                    },
                    {
                        "type": "message",
                        "content": [
                            {
                                "type": "output_text",
                                "text": "redacted",
                                "annotations": [],
                            }
                        ],
                    },
                ]
            },
        )

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(handle)
    ) as client:
        with pytest.raises(PermanentProviderError, match="verifiable URL"):
            await _provider(client).search([_query("safe query")])


async def test_provider_normalizes_completed_open_pages_with_final_answer():
    def handle(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "output": [
                    {
                        "type": "web_search_call",
                        "status": "completed",
                        "action": {
                            "type": "open_page",
                            "url": (
                                "https://example.com/current-squad"
                                "#ws_call_id=private-trace"
                            ),
                        },
                    },
                    {
                        "type": "web_search_call",
                        "status": "failed",
                        "action": {
                            "type": "open_page",
                            "url": "https://failed.example.com/page",
                        },
                    },
                    {
                        "type": "message",
                        "status": "completed",
                        "content": [
                            {
                                "type": "output_text",
                                "text": (
                                    "The safe query is supported by the current "
                                    "squad page and public team information."
                                ),
                                "annotations": [],
                            }
                        ],
                    },
                ]
            },
        )

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(handle)
    ) as client:
        sources = await _provider(client).search([_query("safe query")])

    assert [source.url for source in sources] == [
        "https://example.com/current-squad"
    ]
    assert sources[0].title == "example.com"
    assert "safe query" in sources[0].snippet


@pytest.mark.parametrize("status", [408, 409, 429, 500, 503])
async def test_retryable_http_statuses(status: int):
    transport = httpx.MockTransport(
        lambda request: httpx.Response(status, request=request)
    )
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(RetryableProviderError):
            await _provider(client).search([_query("safe query")])


@pytest.mark.parametrize("status", [400, 401, 403, 404, 422])
async def test_permanent_http_statuses(status: int):
    transport = httpx.MockTransport(
        lambda request: httpx.Response(status, request=request)
    )
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(PermanentProviderError):
            await _provider(client).search([_query("safe query")])


async def test_success_without_verifiable_url_is_permanent_failure():
    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, json={"output": []})
    )
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(PermanentProviderError, match="verifiable URL"):
            await _provider(client).search([_query("safe query")])


async def test_malformed_success_payload_is_permanent_failure():
    transport = httpx.MockTransport(
        lambda request: httpx.Response(
            200,
            content=b"not-json",
            headers={"content-type": "application/json"},
        )
    )
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(PermanentProviderError, match="invalid"):
            await _provider(client).search([_query("safe query")])


async def test_timeout_is_retryable():
    def handle(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("slow", request=request)

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(handle)
    ) as client:
        with pytest.raises(RetryableProviderError):
            await _provider(client).search([_query("safe query")])
