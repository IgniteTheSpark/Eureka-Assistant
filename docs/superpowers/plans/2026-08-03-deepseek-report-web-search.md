# DeepSeek Report Web Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unused Bocha/Tavily report search adapters with one opt-in DeepSeek V4 Flash Responses API web-search provider that preserves the current report pipeline contract.

**Architecture:** Keep `WebSearchProvider` as the pipeline boundary. Add a DeepSeek-specific HTTP adapter and a small pure provider factory; use `UnavailableWebSearchProvider` when search is disabled. Settings own readiness validation and effective-key fallback, while the pipeline, checkpoints, report schemas, and mobile API remain unchanged.

**Tech Stack:** Python 3.12, FastAPI, Pydantic Settings, HTTPX, Pytest, Docker Compose, DeepSeek Responses API.

## Global Constraints

- DeepSeek is the only external web-search supplier; remove all Bocha/Tavily runtime code and configuration.
- `REPORT_WEB_ENABLED` defaults to `false`; the local Theme V2 acceptance environment explicitly enables it.
- `REPORT_WEB_MODEL` defaults to the exact value `deepseek-v4-flash`.
- `REPORT_WEB_API_KEY` falls back to `REPORT_PROVIDER_API_KEY` without logging either value.
- Planner and Generator remain unable to invoke web search directly.
- The existing `none / optional / required / authoritative_only` policy, checkpoints, retry semantics, privacy sanitizer, report schema, and mobile API do not change.
- No database migration and no new Python dependency.

---

### Task 1: DeepSeek-only settings and unavailable provider

**Files:**
- Modify: `theme_v2_service/app/config.py`
- Modify: `theme_v2_service/app/domains/reports/providers.py`
- Modify: `theme_v2_service/tests/unit/test_config.py`
- Modify: `theme_v2_service/tests/unit/test_report_generation_security.py`

**Interfaces:**
- Produces: `Settings.report_web_enabled: bool`, `Settings.report_web_model: str`, `Settings.report_web_api_url: str`, `Settings.report_web_api_key: str | None`.
- Produces: `Settings.report_web_api_key_value() -> str | None` and `Settings.report_web_available() -> bool`.
- Produces: `UnavailableWebSearchProvider.search(queries: list[str]) -> list[WebSource]`, which raises `PermanentProviderError`.

- [ ] **Step 1: Write failing settings and unavailable-provider tests**

Add these assertions to `test_theme_v2_defaults_are_isolated` in `theme_v2_service/tests/unit/test_config.py`:

```python
    assert settings.report_web_enabled is False
    assert settings.report_web_model == "deepseek-v4-flash"
    assert settings.report_web_api_url == "https://api.deepseek.com"
    assert settings.report_web_api_key_value() is None
    assert settings.report_web_available() is False
```

Add these tests to the same file:

```python
def test_report_web_key_falls_back_to_shared_report_key():
    settings = Settings(
        jwt_secret="test-secret",
        report_web_enabled=True,
        report_provider_api_key="shared-secret",
    )

    assert settings.report_web_api_key_value() == "shared-secret"
    assert settings.report_web_available() is True
    assert settings.provider_readiness_errors() == []


def test_enabled_report_web_search_requires_key_and_http_url():
    missing_key = Settings(jwt_secret="test-secret", report_web_enabled=True)
    invalid_url = Settings(
        jwt_secret="test-secret",
        report_web_enabled=True,
        report_web_api_key="secret",
        report_web_api_url="file:///tmp/search",
    )

    assert missing_key.provider_readiness_errors() == [
        "REPORT_WEB_API_KEY or REPORT_PROVIDER_API_KEY is required",
    ]
    assert invalid_url.provider_readiness_errors() == [
        "REPORT_WEB_API_URL must be an absolute HTTP(S) URL",
    ]
```

Add this test to `theme_v2_service/tests/unit/test_report_web_search.py`:

```python
from app.domains.reports.providers import (
    PermanentProviderError,
    RetryableProviderError,
    UnavailableWebSearchProvider,
    WebSource,
)


async def test_unavailable_provider_fails_without_network_access():
    with pytest.raises(PermanentProviderError, match="not enabled"):
        await UnavailableWebSearchProvider().search(["safe query"])
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
cd theme_v2_service
pytest tests/unit/test_config.py tests/unit/test_report_web_search.py -q
```

Expected: failures for missing `report_web_*` settings, `report_web_api_key_value`, `report_web_available`, and `UnavailableWebSearchProvider`.

- [ ] **Step 3: Implement the settings and unavailable provider**

Replace the Bocha/Tavily fields in `Settings` with:

```python
    report_web_enabled: bool = False
    report_web_model: str = "deepseek-v4-flash"
    report_web_api_url: str = "https://api.deepseek.com"
    report_web_api_key: str | None = None
    report_web_timeout_seconds: float = 20.0
```

Add the URL import and methods:

```python
from urllib.parse import urlparse


    def report_web_api_key_value(self) -> str | None:
        return self.report_web_api_key or self.report_provider_api_key

    def report_web_available(self) -> bool:
        parsed = urlparse(self.report_web_api_url)
        return bool(
            self.report_web_enabled
            and self.report_web_model.strip()
            and self.report_web_api_key_value()
            and parsed.scheme in {"http", "https"}
            and parsed.netloc
        )
```

Append the following checks inside `provider_readiness_errors`:

```python
        if self.report_web_enabled:
            if not self.report_web_api_key_value():
                errors.append(
                    "REPORT_WEB_API_KEY or REPORT_PROVIDER_API_KEY is required"
                )
            parsed = urlparse(self.report_web_api_url)
            if parsed.scheme not in {"http", "https"} or not parsed.netloc:
                errors.append("REPORT_WEB_API_URL must be an absolute HTTP(S) URL")
            if not self.report_web_model.strip():
                errors.append("REPORT_WEB_MODEL is required")
```

Add this class after `WebSearchProvider` in `providers.py`:

```python
class UnavailableWebSearchProvider:
    async def search(self, queries: list[str]) -> list[WebSource]:
        raise PermanentProviderError("report Web Search is not enabled")
```

Update the environment-name cleanup tuple in `test_theme_v2_defaults_are_isolated` to include the four `REPORT_WEB_*` names so local shell values cannot affect the default test.

- [ ] **Step 4: Run focused tests and verify they pass**

Run:

```bash
cd theme_v2_service
pytest tests/unit/test_config.py tests/unit/test_report_generation_security.py tests/unit/test_report_web_search.py -q
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit the settings boundary**

```bash
git add theme_v2_service/app/config.py theme_v2_service/app/domains/reports/providers.py theme_v2_service/tests/unit/test_config.py theme_v2_service/tests/unit/test_report_generation_security.py theme_v2_service/tests/unit/test_report_web_search.py
git commit -m "feat: configure DeepSeek report web search"
```

---

### Task 2: DeepSeek Responses API provider

**Files:**
- Create: `theme_v2_service/app/domains/reports/providers_deepseek_web.py`
- Create: `theme_v2_service/tests/unit/test_report_deepseek_web_provider.py`
- Delete: `theme_v2_service/app/domains/reports/providers_web.py`
- Modify: `theme_v2_service/tests/unit/test_report_web_search.py`

**Interfaces:**
- Consumes: `WebSource`, `RetryableProviderError`, and `PermanentProviderError` from `providers.py`.
- Produces: `DeepSeekResponsesWebSearchProvider(client, endpoint, api_key, model, timeout_seconds, clock)` implementing `search(queries: list[str]) -> list[WebSource]`.

- [ ] **Step 1: Write failing request and normalization tests**

Create `theme_v2_service/tests/unit/test_report_deepseek_web_provider.py` with fixtures that assert the exact contract:

```python
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


def _provider(client: httpx.AsyncClient) -> DeepSeekResponsesWebSearchProvider:
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

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        sources = await _provider(client).search(["safe aggregate query"])

    assert len(requests) == 1
    assert requests[0].headers["authorization"] == "Bearer deepseek-secret"
    assert json.loads(requests[0].content) == {
        "model": "deepseek-v4-flash",
        "input": "safe aggregate query",
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
    def handle(request: httpx.Request) -> httpx.Response:
        query = json.loads(request.content)["input"]
        suffix = "one" if query == "query one" else "two"
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

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        sources = await _provider(client).search(["query one", "query two"])

    assert [source.url for source in sources] == [
        "https://example.com/one",
        "https://example.com/two",
    ]
```

- [ ] **Step 2: Write failing error-classification tests**

Append:

```python
@pytest.mark.parametrize("status", [408, 409, 429, 500, 503])
async def test_retryable_http_statuses(status: int):
    transport = httpx.MockTransport(lambda request: httpx.Response(status))
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(RetryableProviderError):
            await _provider(client).search(["safe query"])


@pytest.mark.parametrize("status", [400, 401, 403, 404, 422])
async def test_permanent_http_statuses(status: int):
    transport = httpx.MockTransport(lambda request: httpx.Response(status))
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

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        with pytest.raises(RetryableProviderError):
            await _provider(client).search(["safe query"])
```

- [ ] **Step 3: Run provider tests and verify the module is missing**

Run:

```bash
cd theme_v2_service
pytest tests/unit/test_report_deepseek_web_provider.py -q
```

Expected: collection fails because `providers_deepseek_web` does not exist.

- [ ] **Step 4: Implement the DeepSeek adapter**

Create `providers_deepseek_web.py` with these public behaviors and helpers:

```python
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


def _valid_url(value: object) -> str | None:
    if not isinstance(value, str) or not value.startswith(("https://", "http://")):
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
                if current is None or len(source.title) + len(source.snippet) > len(current.title) + len(current.snippet):
                    unique[source.url] = source
        if queries and not unique:
            raise PermanentProviderError(
                "DeepSeek Web Search returned no verifiable URL"
            )
        return list(unique.values())

    async def _request(self, query: str) -> dict[str, Any]:
        try:
            response = await self.client.post(
                self.endpoint,
                headers={"Authorization": f"Bearer {self.api_key}"},
                json={
                    "model": self.model,
                    "input": query,
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
            raise RetryableProviderError("DeepSeek Web Search timed out") from exc
        except httpx.HTTPStatusError as exc:
            status = exc.response.status_code
            error_type = (
                RetryableProviderError
                if status in {408, 409, 429} or status >= 500
                else PermanentProviderError
            )
            raise error_type("DeepSeek Web Search rejected the request") from exc
        except httpx.HTTPError as exc:
            raise RetryableProviderError("DeepSeek Web Search transport failed") from exc
        except ValueError as exc:
            raise PermanentProviderError("invalid DeepSeek Web Search response") from exc

    def _normalize(self, payload: dict[str, Any]) -> list[WebSource]:
        accessed_at = _timestamp(self.clock())
        candidates: list[tuple[str, str, str]] = []
        output = payload.get("output")
        for item in output if isinstance(output, list) else []:
            if not isinstance(item, dict):
                continue
            action = item.get("action")
            sources = action.get("sources") if isinstance(action, dict) else None
            for source in sources if isinstance(sources, list) else []:
                if not isinstance(source, dict):
                    continue
                url = _valid_url(source.get("url"))
                if url:
                    candidates.append(
                        (
                            str(source.get("title") or source.get("name") or url),
                            url,
                            str(source.get("snippet") or source.get("content") or ""),
                        )
                    )
            content = item.get("content")
            for block in content if isinstance(content, list) else []:
                if not isinstance(block, dict):
                    continue
                text = str(block.get("text") or "")
                annotations = block.get("annotations")
                for annotation in annotations if isinstance(annotations, list) else []:
                    if not isinstance(annotation, dict):
                        continue
                    url = _valid_url(annotation.get("url"))
                    if not url:
                        continue
                    start = annotation.get("start_index")
                    end = annotation.get("end_index")
                    snippet = text
                    if isinstance(start, int) and isinstance(end, int):
                        snippet = text[max(0, start):max(start, end)]
                    candidates.append(
                        (str(annotation.get("title") or url), url, snippet)
                    )
        return [
            WebSource(
                title=title[:500],
                url=url,
                snippet=snippet[:2000],
                accessed_at=accessed_at,
            )
            for title, url, snippet in candidates
        ]
```

Delete `providers_web.py` and remove its Bocha-specific provider test from `test_report_web_search.py`; the policy tests remain unchanged.

- [ ] **Step 5: Run provider and policy tests**

Run:

```bash
cd theme_v2_service
pytest tests/unit/test_report_deepseek_web_provider.py tests/unit/test_report_web_search.py -q
```

Expected: all tests pass, including request payload, citations, stable deduplication, and error classes.

- [ ] **Step 6: Commit the DeepSeek provider**

```bash
git add theme_v2_service/app/domains/reports/providers_deepseek_web.py theme_v2_service/app/domains/reports/providers_web.py theme_v2_service/tests/unit/test_report_deepseek_web_provider.py theme_v2_service/tests/unit/test_report_web_search.py
git commit -m "feat: search report sources with DeepSeek"
```

---

### Task 3: Provider factory, worker wiring, and Bocha/Tavily removal

**Files:**
- Create: `theme_v2_service/app/domains/reports/provider_factory.py`
- Create: `theme_v2_service/tests/unit/test_report_provider_factory.py`
- Modify: `theme_v2_service/app/jobs/registry.py`
- Modify: `docker-compose.theme-v2.yml`
- Modify: `.env.theme-v2.example`

**Interfaces:**
- Consumes: the settings fields from Task 1 and `DeepSeekResponsesWebSearchProvider` from Task 2.
- Produces: `build_report_web_search_provider(settings: Settings, client: httpx.AsyncClient) -> WebSearchProvider`.

- [ ] **Step 1: Write the failing provider-factory tests**

Create `theme_v2_service/tests/unit/test_report_provider_factory.py`:

```python
import httpx

from app.config import Settings
from app.domains.reports.provider_factory import build_report_web_search_provider
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
        report_web_api_url="https://api.deepseek.test",
    )
    async with httpx.AsyncClient() as client:
        provider = build_report_web_search_provider(settings, client)
        assert isinstance(provider, DeepSeekResponsesWebSearchProvider)
        assert provider.endpoint == "https://api.deepseek.test/responses"
        assert provider.api_key == "shared-secret"
        assert provider.model == "deepseek-v4-flash"
```

- [ ] **Step 2: Run the factory test and verify it fails**

Run:

```bash
cd theme_v2_service
pytest tests/unit/test_report_provider_factory.py -q
```

Expected: collection fails because `provider_factory.py` does not exist.

- [ ] **Step 3: Implement the factory and wire the worker**

Create `provider_factory.py`:

```python
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
```

In `registry.py`, import `build_report_web_search_provider`, remove the old `ConfiguredWebSearchProvider` import, and replace its construction with:

```python
                web_search=build_report_web_search_provider(_settings, client),
```

In `docker-compose.theme-v2.yml`, replace the Bocha/Tavily variables with:

```yaml
  REPORT_WEB_ENABLED: ${REPORT_WEB_ENABLED:-false}
  REPORT_WEB_MODEL: ${REPORT_WEB_MODEL:-deepseek-v4-flash}
  REPORT_WEB_API_URL: ${REPORT_WEB_API_URL:-https://api.deepseek.com}
  REPORT_WEB_API_KEY: ${REPORT_WEB_API_KEY:-${REPORT_PROVIDER_API_KEY:-}}
  REPORT_WEB_TIMEOUT_SECONDS: ${REPORT_WEB_TIMEOUT_SECONDS:-20}
```

In `.env.theme-v2.example`, replace the supplier section with:

```dotenv
# DeepSeek V4 Flash Responses API web search. Disabled by default.
REPORT_WEB_ENABLED=false
REPORT_WEB_MODEL=deepseek-v4-flash
REPORT_WEB_API_URL=https://api.deepseek.com
REPORT_WEB_API_KEY=
REPORT_WEB_TIMEOUT_SECONDS=20
```

- [ ] **Step 4: Run factory, config, and report tests**

Run:

```bash
cd theme_v2_service
pytest tests/unit/test_report_provider_factory.py tests/unit/test_config.py tests/unit/test_report_web_search.py tests/unit/test_report_deepseek_web_provider.py -q
```

Expected: all tests pass.

- [ ] **Step 5: Prove Bocha/Tavily runtime references are gone**

Run from the repository root:

```bash
rg -n "BOCHA|TAVILY|bocha|tavily|ConfiguredWebSearchProvider" theme_v2_service/app theme_v2_service/tests docker-compose.theme-v2.yml .env.theme-v2.example
```

Expected: no matches.

- [ ] **Step 6: Commit worker and deployment wiring**

```bash
git add theme_v2_service/app/domains/reports/provider_factory.py theme_v2_service/tests/unit/test_report_provider_factory.py theme_v2_service/app/jobs/registry.py docker-compose.theme-v2.yml .env.theme-v2.example
git commit -m "refactor: remove legacy report search providers"
```

---

### Task 4: Full verification and real DeepSeek contract smoke test

**Files:**
- Modify only if a verified contract mismatch is found: `theme_v2_service/app/domains/reports/providers_deepseek_web.py`
- Modify only with the matching regression test: `theme_v2_service/tests/unit/test_report_deepseek_web_provider.py`

**Interfaces:**
- Consumes: the completed DeepSeek provider and existing report pipeline.
- Produces: a verified provider contract and a healthy independent Theme V2 Docker stack.

- [ ] **Step 1: Run the full service suite**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest -q
```

Expected: the complete Theme V2 service suite passes.

- [ ] **Step 2: Enable DeepSeek search in the local acceptance environment**

Add these non-secret values to the local ignored `.env` only if they are absent:

```dotenv
REPORT_WEB_ENABLED=true
REPORT_WEB_MODEL=deepseek-v4-flash
REPORT_WEB_API_URL=https://api.deepseek.com
```

Do not copy or print the existing API key; Compose reuses `REPORT_PROVIDER_API_KEY` through the configured fallback.

- [ ] **Step 3: Rebuild and check readiness**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml up -d --build api worker
curl -fsS http://127.0.0.1:8100/ready
```

Expected: `{"status":"ready"}` and both `api` and `worker` remain healthy/running.

- [ ] **Step 4: Run a minimal provider contract smoke test without exposing content**

Run a Python one-liner inside the worker that loads `get_settings`, builds the provider, searches the aggregate query `2026 workplace meeting preparation research`, and prints only the source count plus parsed URL host names. Do not print headers, raw JSON, snippets, or environment values.

Expected: at least one source and at least one non-empty HTTP(S) host name.

- [ ] **Step 5: Exercise the optional policy and the complete report pipeline**

Inside the worker, call `execute_web_search` with `policy="optional"`, the configured DeepSeek provider, and the same aggregate smoke query. Print only `execution.status`, source count, and URL host names. Then run the existing complete report E2E test:

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test pytest tests/e2e/test_report_generation_flow.py -q
```

Expected: the real optional search returns `completed` with at least one verified URL, and the existing load-evidence → web-search → content-generation → persistence E2E test passes. The provider unit tests continue proving that only the dedicated search adapter emits a `tools` field.

- [ ] **Step 6: Commit only contract-driven corrections**

If Step 4 exposed a documented response-shape difference, add the exact response fixture to the provider test, make the smallest parser correction, rerun Tasks 2–4 tests, then commit:

```bash
git add theme_v2_service/app/domains/reports/providers_deepseek_web.py theme_v2_service/tests/unit/test_report_deepseek_web_provider.py
git commit -m "fix: match DeepSeek web search response contract"
```

If no correction was required, do not create an empty commit.
