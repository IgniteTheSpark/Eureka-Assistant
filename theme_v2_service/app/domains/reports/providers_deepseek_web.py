from collections.abc import Callable
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlparse

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


def _valid_url(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    if not value.startswith(("https://", "http://")):
        return None
    return value


class DeepSeekResponsesWebSearchProvider:
    def __init__(
        self,
        *,
        client: httpx.AsyncClient,
        endpoint: str,
        api_key: str,
        model: str = "deepseek-v4-flash",
        timeout_seconds: float = 20.0,
        clock: Callable[[], datetime] = utc_now,
    ) -> None:
        self.client = client
        self.endpoint = endpoint
        self.api_key = api_key
        self.model = model
        self.timeout_seconds = timeout_seconds
        self.clock = clock

    async def search(self, queries: list[str]) -> list[WebSource]:
        unique: dict[str, WebSource] = {}
        for query in queries:
            payload = await self._request(query)
            for source in self._normalize(payload):
                current = unique.get(source.url)
                if current is None or self._detail_score(
                    source
                ) > self._detail_score(current):
                    unique[source.url] = source
        if queries and not unique:
            raise PermanentProviderError(
                "DeepSeek Web Search returned no verifiable URL"
            )
        return list(unique.values())

    @staticmethod
    def _detail_score(source: WebSource) -> int:
        return len(source.title) + len(source.snippet)

    async def _request(self, query: str) -> dict[str, Any]:
        try:
            response = await self.client.post(
                self.endpoint,
                headers={"Authorization": f"Bearer {self.api_key}"},
                json={
                    "model": self.model,
                    "input": (
                        "Search the public web for the following topic. "
                        "Return a concise answer with verifiable URL citations. "
                        f"Topic: {query}"
                    ),
                    "tools": [{"type": "web_search"}],
                    "tool_choice": {"type": "web_search"},
                },
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
            payload = response.json()
            if not isinstance(payload, dict):
                raise ValueError("response must be an object")
            return payload
        except httpx.TimeoutException as exc:
            raise RetryableProviderError(
                "DeepSeek Web Search timed out"
            ) from exc
        except httpx.HTTPStatusError as exc:
            status = exc.response.status_code
            error_type = (
                RetryableProviderError
                if status in {408, 409, 429} or status >= 500
                else PermanentProviderError
            )
            raise error_type(
                "DeepSeek Web Search rejected the request"
            ) from exc
        except httpx.HTTPError as exc:
            raise RetryableProviderError(
                "DeepSeek Web Search transport failed"
            ) from exc
        except ValueError as exc:
            raise PermanentProviderError(
                "invalid DeepSeek Web Search response"
            ) from exc

    def _normalize(self, payload: dict[str, Any]) -> list[WebSource]:
        accessed_at = _timestamp(self.clock())
        candidates: list[tuple[str, str, str]] = []
        output = payload.get("output")
        for item in output if isinstance(output, list) else []:
            if not isinstance(item, dict):
                continue
            candidates.extend(self._source_candidates(item))
            candidates.extend(self._citation_candidates(item))
        return [
            WebSource(
                title=title[:500],
                url=url,
                snippet=snippet[:2000],
                accessed_at=accessed_at,
            )
            for title, url, snippet in candidates
        ]

    @staticmethod
    def _source_candidates(item: dict[str, Any]) -> list[tuple[str, str, str]]:
        action = item.get("action")
        sources = action.get("sources") if isinstance(action, dict) else None
        candidates = []
        action_url = (
            _valid_url(action.get("url")) if isinstance(action, dict) else None
        )
        if action_url:
            candidates.append(
                (urlparse(action_url).hostname or action_url, action_url, "")
            )
        for source in sources if isinstance(sources, list) else []:
            if not isinstance(source, dict):
                continue
            url = _valid_url(source.get("url"))
            if not url:
                continue
            candidates.append(
                (
                    str(source.get("title") or source.get("name") or url),
                    url,
                    str(
                        source.get("snippet")
                        or source.get("content")
                        or ""
                    ),
                )
            )
        return candidates

    @staticmethod
    def _citation_candidates(
        item: dict[str, Any],
    ) -> list[tuple[str, str, str]]:
        content = item.get("content")
        candidates = []
        for block in content if isinstance(content, list) else []:
            if not isinstance(block, dict):
                continue
            text = str(block.get("text") or "")
            annotations = block.get("annotations")
            for annotation in (
                annotations if isinstance(annotations, list) else []
            ):
                if not isinstance(annotation, dict):
                    continue
                url = _valid_url(annotation.get("url"))
                if not url:
                    continue
                snippet = text
                start = annotation.get("start_index")
                end = annotation.get("end_index")
                if isinstance(start, int) and isinstance(end, int):
                    snippet = text[max(0, start) : max(start, end)]
                candidates.append(
                    (str(annotation.get("title") or url), url, snippet)
                )
        return candidates
