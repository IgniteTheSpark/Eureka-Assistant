from collections.abc import Callable
from datetime import datetime, timezone
from typing import Any

import httpx

from app.db.base import utc_now
from app.domains.reports.providers import (
    PermanentProviderError,
    RetryableProviderError,
    WebSource,
)


def _timestamp(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


class ConfiguredWebSearchProvider:
    def __init__(
        self,
        *,
        client: httpx.AsyncClient,
        bocha_api_key: str | None = None,
        bocha_endpoint: str = "https://api.bochaai.com/v1/web-search",
        tavily_api_key: str | None = None,
        tavily_endpoint: str = "https://api.tavily.com/search",
        timeout_seconds: float = 20.0,
        clock: Callable[[], datetime] = utc_now,
    ) -> None:
        self.client = client
        self.bocha_api_key = bocha_api_key
        self.bocha_endpoint = bocha_endpoint
        self.tavily_api_key = tavily_api_key
        self.tavily_endpoint = tavily_endpoint
        self.timeout_seconds = timeout_seconds
        self.clock = clock

    async def search(self, queries: list[str]) -> list[WebSource]:
        if self.bocha_api_key:
            provider = "bocha"
        elif self.tavily_api_key:
            provider = "tavily"
        else:
            raise PermanentProviderError("no Web Search provider is configured")
        sources: list[WebSource] = []
        for query in queries:
            payload = await self._request(provider, query)
            sources.extend(self._normalize(provider, payload))
        unique: dict[str, WebSource] = {}
        for source in sources:
            unique.setdefault(source.url, source)
        return list(unique.values())

    async def _request(self, provider: str, query: str) -> dict:
        try:
            if provider == "bocha":
                response = await self.client.post(
                    self.bocha_endpoint,
                    headers={"Authorization": f"Bearer {self.bocha_api_key}"},
                    json={"query": query, "count": 10, "summary": True},
                    timeout=self.timeout_seconds,
                )
            else:
                response = await self.client.post(
                    self.tavily_endpoint,
                    json={
                        "api_key": self.tavily_api_key,
                        "query": query,
                        "max_results": 10,
                    },
                    timeout=self.timeout_seconds,
                )
            response.raise_for_status()
            payload = response.json()
            if not isinstance(payload, dict):
                raise ValueError("response must be an object")
            return payload
        except httpx.TimeoutException as exc:
            raise RetryableProviderError("Web Search timed out") from exc
        except httpx.HTTPStatusError as exc:
            error = (
                RetryableProviderError
                if exc.response.status_code >= 500
                else PermanentProviderError
            )
            raise error("Web Search provider rejected the request") from exc
        except (httpx.HTTPError, ValueError) as exc:
            raise RetryableProviderError("invalid Web Search response") from exc

    def _normalize(self, provider: str, payload: dict) -> list[WebSource]:
        raw_items: list[dict[str, Any]]
        if provider == "bocha":
            raw_items = (
                payload.get("data", {})
                .get("webPages", {})
                .get("value", [])
            )
            title_key, snippet_key = "name", "snippet"
        else:
            raw_items = payload.get("results", [])
            title_key, snippet_key = "title", "content"
        accessed_at = _timestamp(self.clock())
        normalized = []
        for item in raw_items:
            if not isinstance(item, dict):
                continue
            title = item.get(title_key)
            url = item.get("url")
            snippet = item.get(snippet_key, "")
            if not isinstance(title, str) or not isinstance(url, str):
                continue
            if not url.startswith(("https://", "http://")):
                continue
            normalized.append(
                WebSource(
                    title=title[:500],
                    url=url,
                    snippet=str(snippet)[:2000],
                    accessed_at=accessed_at,
                )
            )
        return normalized
