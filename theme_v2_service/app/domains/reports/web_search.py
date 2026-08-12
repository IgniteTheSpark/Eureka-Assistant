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
    questions = [
        (index, value.strip())
        for index, value in enumerate(brief.questions[:8])
        if value.strip()
    ]
    if not questions:
        questions = [(0, "公开背景与关键信息")]
    entities = [
        entity
        for entity in brief.entities
        if entity.enabled
        and not (entity.kind == "person" and not (entity.qualifier or "").strip())
    ]
    queries: list[WebQuery] = []
    seen: set[str] = set()
    freshness = _FRESHNESS_TEXT[brief.freshness]
    entity_names = [entity.name.strip().casefold() for entity in entities]

    def relevant_questions(entity_name: str) -> list[tuple[int, str]]:
        own_name = entity_name.casefold()
        own = [item for item in questions if own_name in item[1].casefold()]
        generic = [
            item
            for item in questions
            if not any(name and name in item[1].casefold() for name in entity_names)
        ]
        return [*own, *generic]

    def add_query(entity, question_index: int, question: str) -> None:
        qualifier = (entity.qualifier or "").strip()
        name = entity.name.strip()
        parts = (
            [question, qualifier, freshness]
            if name.casefold() in question.casefold()
            else [name, qualifier, question, freshness]
        )
        normalized = " ".join(" ".join(part for part in parts if part).split())[:300]
        fingerprint = normalized.casefold()
        if not normalized or fingerprint in seen or len(queries) >= 6:
            return
        seen.add(fingerprint)
        queries.append(
            WebQuery(
                id=f"web-{len(queries) + 1}",
                text=normalized,
                entity_ids=[entity.id],
                entity_terms=[name],
                question_ids=[f"question-{question_index + 1}"],
            )
        )

    # The first pass guarantees at least one bounded query per confirmed entity.
    selected_by_entity: dict[str, list[tuple[int, str]]] = {}
    for entity in entities:
        selected = relevant_questions(entity.name.strip())
        selected_by_entity[entity.id] = selected
        question_index, question = selected[0] if selected else questions[0]
        add_query(entity, question_index, question)

    # Only after coverage is guaranteed do remaining slots deepen each entity.
    depth = 1
    while len(queries) < 6:
        added = False
        for entity in entities:
            selected = selected_by_entity[entity.id]
            if depth >= len(selected):
                continue
            question_index, question = selected[depth]
            before = len(queries)
            add_query(entity, question_index, question)
            added = added or len(queries) > before
            if len(queries) >= 6:
                break
        if not added:
            break
        depth += 1
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
    if query.entity_terms and not any(
        term.casefold() in haystack
        for entity_term in query.entity_terms
        for term in _meaningful_tokens(entity_term)
    ):
        return False
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
