"""
Web-search pipeline step (§14.9) — used by the report engine for the `briefing`
genre (会前调研 / 外部调研).

Architecture (§14.9, deliberate):
- This is a PIPELINE STEP, **not** a content-skill tool. Content skills stay
  tool-less (data pre-injected — DeepSeek tool-calling is documented-flaky here).
  The pipeline deterministically searches first, then injects the results as
  「带出处的资料」 for the content skill to cite.
- Grounding wall: user data stays grounded (his numbers come from his records);
  every external claim must be attributable to one of these results (the content
  skill cites 「据 <source>」). Results are archived in the report's spec_json
  (存证、可引用).

Provider (§14.9「择一接」, key-driven like core/llm.py):
- BOCHA_API_KEY  → 博查 (api.bochaai.com) — China-hosted, reliable 国内 inbound
  (same reason the text LLM is DeepSeek-direct). Preferred in prod.
- TAVILY_API_KEY → Tavily (api.tavily.com) — dev-box fallback outside China.
- Neither key   → search disabled; the briefing degrades gracefully to a
  user-data-only report (the pipeline notes 「未联网」 in the material).
"""
from __future__ import annotations

import asyncio
from urllib.parse import urlparse

import httpx

from config import settings

_TIMEOUT = 12.0          # per query — search is one phase of an SSE-streamed run
MAX_QUERIES = 3          # dispatcher emits 1–3; hard cap regardless
PER_QUERY_RESULTS = 6
MAX_TOTAL_RESULTS = 10   # what actually gets injected into the content prompt


def provider() -> str | None:
    """Active provider name, or None when web-search is unconfigured."""
    if settings.bocha_api_key.strip():
        return "bocha"
    if settings.tavily_api_key.strip():
        return "tavily"
    return None


def _domain(url: str) -> str:
    try:
        return urlparse(url).netloc or ""
    except ValueError:
        return ""


def _norm(title: str, url: str, snippet: str, source: str = "", date: str = "") -> dict:
    """One sourced result —「带出处的资料」 unit the content skill cites."""
    return {
        "title": (title or "").strip()[:160],
        "url": (url or "").strip(),
        "snippet": (snippet or "").strip()[:500],
        "source": (source or "").strip() or _domain(url),
        "date": (date or "").strip()[:10],
    }


async def _bocha(client: httpx.AsyncClient, query: str, count: int) -> list[dict]:
    resp = await client.post(
        "https://api.bochaai.com/v1/web-search",
        headers={"Authorization": f"Bearer {settings.bocha_api_key.strip()}"},
        json={"query": query, "summary": True, "count": count, "freshness": "noLimit"},
    )
    resp.raise_for_status()
    pages = (((resp.json().get("data") or {}).get("webPages") or {}).get("value") or [])
    return [
        _norm(p.get("name", ""), p.get("url", ""),
              p.get("summary") or p.get("snippet") or "",
              p.get("siteName", ""), (p.get("datePublished") or "")[:10])
        for p in pages
    ]


async def _tavily(client: httpx.AsyncClient, query: str, count: int) -> list[dict]:
    resp = await client.post(
        "https://api.tavily.com/search",
        headers={"Authorization": f"Bearer {settings.tavily_api_key.strip()}"},
        json={"query": query, "max_results": count, "search_depth": "basic"},
    )
    resp.raise_for_status()
    return [
        _norm(r.get("title", ""), r.get("url", ""), r.get("content") or "")
        for r in (resp.json().get("results") or [])
    ]


async def search_web(queries: list[str]) -> list[dict]:
    """Run 1–MAX_QUERIES queries against the configured provider; return deduped,
    capped, sourced results. Any failure (timeout / quota / bad key) degrades to
    fewer-or-zero results — the briefing must never die on the search step."""
    prov = provider()
    qs = [q.strip() for q in (queries or []) if isinstance(q, str) and q.strip()][:MAX_QUERIES]
    if prov is None or not qs:
        return []
    fetch = _bocha if prov == "bocha" else _tavily
    out: list[dict] = []
    seen: set[str] = set()
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        batches = await asyncio.gather(
            *(fetch(client, q, PER_QUERY_RESULTS) for q in qs),
            return_exceptions=True,
        )
    for batch in batches:
        if isinstance(batch, BaseException):
            continue  # one query failing must not kill the others
        for r in batch:
            if not r["url"] or r["url"] in seen:
                continue
            seen.add(r["url"])
            out.append(r)
    return out[:MAX_TOTAL_RESULTS]
