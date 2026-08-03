from datetime import datetime
import json

import httpx
import pytest

from app.domains.reports.providers import (
    PermanentProviderError,
    RetryableProviderError,
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
        sources = await _provider(client).search(["safe aggregate query"])

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
    }
    assert [source.url for source in sources] == [
        "https://example.gov/guide",
        "https://example.edu/paper",
    ]
    assert sources[0].accessed_at == "2026-08-03T10:00:00Z"
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
        sources = await _provider(client).search(["query one", "query two"])

    assert len(requests) == 2
    assert [source.url for source in sources] == [
        "https://example.com/one",
        "https://example.com/two",
    ]


async def test_provider_normalizes_deepseek_open_page_action_url():
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
        sources = await _provider(client).search(["safe query"])

    assert [source.model_dump() for source in sources] == [
        {
            "title": "openai.com",
            "url": "https://openai.com/",
            "snippet": "",
            "accessed_at": "2026-08-03T10:00:00Z",
            "authoritative": False,
        }
    ]


@pytest.mark.parametrize("status", [408, 409, 429, 500, 503])
async def test_retryable_http_statuses(status: int):
    transport = httpx.MockTransport(
        lambda request: httpx.Response(status, request=request)
    )
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(RetryableProviderError):
            await _provider(client).search(["safe query"])


@pytest.mark.parametrize("status", [400, 401, 403, 404, 422])
async def test_permanent_http_statuses(status: int):
    transport = httpx.MockTransport(
        lambda request: httpx.Response(status, request=request)
    )
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(PermanentProviderError):
            await _provider(client).search(["safe query"])


async def test_success_without_verifiable_url_is_permanent_failure():
    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, json={"output": []})
    )
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(PermanentProviderError, match="verifiable URL"):
            await _provider(client).search(["safe query"])


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
            await _provider(client).search(["safe query"])


async def test_timeout_is_retryable():
    def handle(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("slow", request=request)

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(handle)
    ) as client:
        with pytest.raises(RetryableProviderError):
            await _provider(client).search(["safe query"])
