from collections.abc import Callable
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import httpx

from app.db.base import utc_now
from app.domains.reports.providers import (
    PermanentProviderError,
    RetryableProviderError,
    WebQuery,
    WebSource,
)


def _timestamp(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _valid_url(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    parsed = urlsplit(value)
    if parsed.scheme.casefold() != "https" or not parsed.netloc:
        return None
    return urlunsplit(("https", parsed.netloc, parsed.path, parsed.query, ""))


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

    async def search(self, queries: list[WebQuery]) -> list[WebSource]:
        unique: dict[str, WebSource] = {}
        for query in queries:
            payload = await self._request(query.text)
            for source in self._normalize(payload, query=query):
                current = unique.get(source.url)
                if current is None:
                    unique[source.url] = source
                    continue
                preferred = (
                    source
                    if self._detail_score(source) > self._detail_score(current)
                    else current
                )
                unique[source.url] = preferred.model_copy(
                    update={
                        "entity_ids": list(
                            dict.fromkeys([*current.entity_ids, *source.entity_ids])
                        ),
                        "question_ids": list(
                            dict.fromkeys(
                                [*current.question_ids, *source.question_ids]
                            )
                        ),
                    }
                )
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
                    "include": ["web_search_call.action.sources"],
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

    def _normalize(
        self,
        payload: dict[str, Any],
        *,
        query: WebQuery,
    ) -> list[WebSource]:
        accessed_at = _timestamp(self.clock())
        candidates: list[tuple[str, str, str]] = []
        output = payload.get("output")
        for item in output if isinstance(output, list) else []:
            if not isinstance(item, dict):
                continue
            candidates.extend(self._source_candidates(item))
            candidates.extend(self._citation_candidates(item))
        if not candidates:
            answer = self._final_answer(output)
            if answer:
                for item in output if isinstance(output, list) else []:
                    candidate = self._completed_open_page(item, snippet=answer)
                    if candidate is not None:
                        candidates.append(candidate)
                    if len(candidates) >= 5:
                        break
        return [
            WebSource(
                title=title[:500],
                url=url,
                snippet=snippet[:2000],
                accessed_at=accessed_at,
                query_id=query.id,
                entity_ids=query.entity_ids,
                question_ids=query.question_ids,
            )
            for title, url, snippet in candidates
            if title.strip() and snippet.strip()
        ]

    @staticmethod
    def _final_answer(output: object) -> str:
        answers = []
        for item in output if isinstance(output, list) else []:
            if not isinstance(item, dict) or item.get("type") != "message":
                continue
            content = item.get("content")
            for block in content if isinstance(content, list) else []:
                if not isinstance(block, dict) or block.get("type") != "output_text":
                    continue
                text = str(block.get("text") or "").strip()
                if text:
                    answers.append(text)
        return max(answers, key=len, default="")[:2000]

    @staticmethod
    def _completed_open_page(
        item: object,
        *,
        snippet: str,
    ) -> tuple[str, str, str] | None:
        if not isinstance(item, dict) or item.get("type") != "web_search_call":
            return None
        if item.get("status") != "completed":
            return None
        action = item.get("action")
        if not isinstance(action, dict) or action.get("type") != "open_page":
            return None
        url = _valid_url(action.get("url"))
        if url is None:
            return None
        hostname = urlsplit(url).hostname or "Public source"
        return hostname.removeprefix("www."), url, snippet

    @staticmethod
    def _source_candidates(item: dict[str, Any]) -> list[tuple[str, str, str]]:
        action = item.get("action")
        sources = action.get("sources") if isinstance(action, dict) else None
        candidates = []
        for source in sources if isinstance(sources, list) else []:
            if not isinstance(source, dict):
                continue
            url = _valid_url(source.get("url"))
            if not url:
                continue
            title = str(source.get("title") or source.get("name") or "").strip()
            snippet = str(
                source.get("snippet") or source.get("content") or ""
            ).strip()
            if not title or not snippet:
                continue
            candidates.append(
                (
                    title,
                    url,
                    snippet,
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
                title = str(annotation.get("title") or "").strip()
                if title and snippet.strip():
                    candidates.append((title, url, snippet.strip()))
        return candidates
