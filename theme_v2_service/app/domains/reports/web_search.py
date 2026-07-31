import re
from urllib.parse import urlparse

from app.domains.reports.providers import (
    ProviderError,
    RetryableProviderError,
    WebSearchProvider,
    WebSource,
)
from app.domains.reports.schemas import CapabilityExecution, TimeRange


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


def _sanitize_fragment(value: str, sensitive_values: list[str]) -> str:
    sanitized = value
    for sensitive in sorted(
        {item.strip() for item in sensitive_values if item.strip()},
        key=len,
        reverse=True,
    ):
        sanitized = sanitized.replace(sensitive, " ")
    sensitive_tokens = {
        token.casefold()
        for item in sensitive_values
        for token in re.findall(r"[\w\u3400-\u9fff-]+", item)
        if len(token) >= 2
    }
    tokens = re.findall(r"[\w\u3400-\u9fff-]+", sanitized)
    return " ".join(
        token
        for token in tokens
        if token.casefold() not in sensitive_tokens
    )


def build_web_queries(
    *,
    report_goal: str,
    capabilities: set[str],
    time_range: TimeRange | None,
    aggregate_terms: list[str],
    sensitive_values: list[str],
) -> list[str]:
    goal = _sanitize_fragment(report_goal, sensitive_values)
    capability_text = " ".join(sorted(capabilities))
    date_text = ""
    if time_range is not None:
        dates = [
            value.date().isoformat()
            for value in (time_range.from_at, time_range.to_at)
            if value is not None
        ]
        date_text = " ".join(dates)
    base = " ".join(item for item in (goal, capability_text, date_text) if item)
    candidates = [base]
    candidates.extend(
        " ".join(
            item
            for item in (
                goal,
                _sanitize_fragment(term, sensitive_values),
                capability_text,
                date_text,
            )
            if item
        )
        for term in aggregate_terms[:2]
    )
    queries = []
    for candidate in candidates:
        normalized = " ".join(candidate.split())[:500]
        if normalized and normalized not in queries:
            queries.append(normalized)
    return queries[:3]


def _is_authoritative(url: str, domains: set[str]) -> bool:
    hostname = (urlparse(url).hostname or "").casefold().rstrip(".")
    return any(
        hostname == domain.casefold().rstrip(".")
        or hostname.endswith(f".{domain.casefold().rstrip('.')}")
        for domain in domains
    )


async def execute_web_search(
    *,
    policy: str,
    provider: WebSearchProvider,
    queries: list[str],
    authoritative_domains: set[str] | None = None,
) -> CapabilityExecution:
    if policy == "none":
        return CapabilityExecution(policy=policy, status="not_requested")
    try:
        sources = await provider.search(queries)
    except ProviderError as exc:
        if policy == "optional":
            return CapabilityExecution(policy=policy, status="failed_degraded")
        raise RequiredWebSearchFailed("required Web Search failed") from exc

    accepted: list[WebSource] = sources
    if policy == "authoritative_only":
        domains = authoritative_domains or set(DEFAULT_AUTHORITATIVE_DOMAINS)
        accepted = [
            source.model_copy(update={"authoritative": True})
            for source in sources
            if _is_authoritative(source.url, domains)
        ]
        if not accepted:
            raise AuthoritativeSourcesUnavailable(
                "no qualified authoritative Web source"
            )
    return CapabilityExecution(
        policy=policy,
        status="succeeded",
        sources=[source.model_dump(mode="json") for source in accepted],
    )
