import re
from urllib.parse import urlparse

from app.domains.reports.providers import (
    ProviderError,
    RetryableProviderError,
    WebQuery,
    WebSearchProvider,
    WebSource,
)
from app.domains.reports.schemas import CapabilityExecution, PublicResearchBrief


DEFAULT_AUTHORITATIVE_DOMAINS = frozenset(
    {
        "gov.cn",
        "edu.cn",
        "who.int",
        "unicef.org",
        "iso.org",
        "w3.org",
    }
)


class RequiredWebSearchFailed(RetryableProviderError):
    pass


class AuthoritativeSourcesUnavailable(RequiredWebSearchFailed):
    pass


_FRESHNESS_TEXT = {
    "current": "最新 当前",
    "recent_year": "最近一年",
    "historical": "历史 发展",
    "not_applicable": "",
}


def build_web_queries(brief: PublicResearchBrief) -> list[WebQuery]:
    """Build bounded public queries without accepting raw Event/Asset content."""
    questions = [value.strip() for value in brief.questions if value.strip()][:8]
    if not questions:
        questions = ["公开背景与关键信息"]
    queries: list[WebQuery] = []
    seen: set[str] = set()
    freshness = _FRESHNESS_TEXT[brief.freshness]
    for entity in brief.entities:
        if not entity.enabled:
            continue
        qualifier = (entity.qualifier or "").strip()
        if entity.kind == "person" and not qualifier:
            continue
        for question_index, question in enumerate(questions):
            parts = [entity.name.strip(), qualifier, question, freshness]
            text = " ".join(part for part in parts if part)
            normalized = " ".join(text.split())[:300]
            fingerprint = normalized.casefold()
            if not normalized or fingerprint in seen:
                continue
            seen.add(fingerprint)
            queries.append(
                WebQuery(
                    id=f"web-{len(queries) + 1}",
                    text=normalized,
                    entity_ids=[entity.id],
                    question_ids=[f"question-{question_index + 1}"],
                )
            )
            if len(queries) >= 6:
                return queries
    return queries


def _is_authoritative(url: str, domains: set[str]) -> bool:
    hostname = (urlparse(url).hostname or "").casefold().rstrip(".")
    return any(
        hostname == domain.casefold().rstrip(".")
        or hostname.endswith(f".{domain.casefold().rstrip('.')}")
        for domain in domains
    )


def _is_https(url: str) -> bool:
    parsed = urlparse(url)
    return parsed.scheme.casefold() == "https" and bool(parsed.hostname)


def _meaningful_tokens(value: str) -> set[str]:
    tokens = re.findall(r"[A-Za-z0-9][A-Za-z0-9._-]+|[\u3400-\u9fff]{2,}", value)
    return {token.casefold() for token in tokens if len(token) >= 2}


def _source_is_relevant(
    source: WebSource,
    *,
    query_by_id: dict[str, WebQuery],
) -> bool:
    if not _is_https(source.url):
        return False
    if not source.title.strip() or len(source.snippet.strip()) < 8:
        return False
    query = query_by_id.get(source.query_id)
    if query is None:
        return False
    haystack = f"{source.title} {source.snippet}".casefold()
    query_tokens = _meaningful_tokens(query.text)
    return any(token in haystack for token in query_tokens)


async def execute_web_search(
    *,
    policy: str,
    provider: WebSearchProvider,
    queries: list[WebQuery],
    authoritative_domains: set[str] | None = None,
) -> CapabilityExecution:
    if policy == "none":
        return CapabilityExecution(policy=policy, status="not_requested")
    if not queries:
        if policy == "optional":
            return CapabilityExecution(policy=policy, status="failed_degraded")
        raise RequiredWebSearchFailed("required Web Search has no qualified query")
    try:
        sources = await provider.search(queries)
    except ProviderError as exc:
        if policy == "optional":
            return CapabilityExecution(policy=policy, status="failed_degraded")
        raise RequiredWebSearchFailed("required Web Search failed") from exc

    query_by_id = {query.id: query for query in queries}
    accepted = [
        source
        for source in sources
        if _source_is_relevant(source, query_by_id=query_by_id)
    ]
    if policy == "authoritative_only":
        domains = authoritative_domains or set(DEFAULT_AUTHORITATIVE_DOMAINS)
        accepted = [
            source.model_copy(update={"authoritative": True})
            for source in accepted
            if _is_authoritative(source.url, domains)
        ]
        if not accepted:
            raise AuthoritativeSourcesUnavailable(
                "no qualified authoritative Web source"
            )
    elif not accepted:
        if policy == "optional":
            return CapabilityExecution(policy=policy, status="failed_degraded")
        raise RequiredWebSearchFailed("no relevant substantive Web source")
    return CapabilityExecution(
        policy=policy,
        status="succeeded",
        sources=[source.model_dump(mode="json") for source in accepted],
    )
