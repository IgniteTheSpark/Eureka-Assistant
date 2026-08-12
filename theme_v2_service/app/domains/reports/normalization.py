import hashlib
import re
from dataclasses import dataclass

from app.domains.reports.providers import GeneratedSuggestedAction
from app.domains.reports.schemas import ReportCitation, ReportSuggestedAction


CITATION_RE = re.compile(
    r"\[(?P<kind>evidence|source):(?P<value>[^\]\n]+)\]",
    re.IGNORECASE,
)
CITATION_START_RE = re.compile(r"\[(?:evidence|source):", re.IGNORECASE)
LEGACY_ACTIONS_RE = re.compile(
    r"(?ms)^\s*:::actions[^\n]*\n(?P<body>.*?)^\s*:::\s*$"
)
LIST_ITEM_RE = re.compile(r"^(?:\d+\.|[-*])\s+(.+)$")
INLINE_MARKDOWN_RE = re.compile(r"\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`")
WHITESPACE_RE = re.compile(r"\s+")


@dataclass(frozen=True)
class NormalizedReportContent:
    content_md: str
    citations: list[ReportCitation]
    suggested_actions: list[ReportSuggestedAction]
    used_external_sources: list[dict]


def _normalize_action_title(value: str) -> str:
    without_inline_markdown = INLINE_MARKDOWN_RE.sub(
        lambda match: next(
            group for group in match.groups() if group is not None
        ),
        value,
    )
    return WHITESPACE_RE.sub(" ", without_inline_markdown).strip()


def _legacy_action_titles(content_md: str) -> tuple[str, list[str]]:
    titles: list[str] = []

    def replace(match: re.Match[str]) -> str:
        if not titles:
            for line in match.group("body").splitlines():
                item = LIST_ITEM_RE.match(line.strip())
                if item is None:
                    continue
                title = _normalize_action_title(item.group(1))
                if title:
                    titles.append(title[:200])
                if len(titles) == 5:
                    break
        return ""

    return LEGACY_ACTIONS_RE.sub(replace, content_md), titles


def _normalized_actions(
    typed: list[GeneratedSuggestedAction],
    legacy_titles: list[str],
) -> list[ReportSuggestedAction]:
    source = [
        (item.title, item.due_at)
        for item in typed
    ] or [(title, None) for title in legacy_titles]
    actions: list[ReportSuggestedAction] = []
    for index, (raw_title, due_at) in enumerate(source[:5]):
        title = _normalize_action_title(raw_title)
        if not title:
            continue
        due_key = due_at.isoformat() if due_at is not None else ""
        digest = hashlib.sha256(
            f"{index}\0{title}\0{due_key}".encode("utf-8")
        ).hexdigest()[:20]
        actions.append(
            ReportSuggestedAction(
                id=f"action-{digest}",
                title=title[:200],
                due_at=due_at,
            )
        )
    return actions


def normalize_report_content(
    *,
    content_md: str,
    allowed_asset_ids: list[str],
    allowed_evidence_ids: list[str] | None = None,
    external_sources: list[dict],
    suggested_actions: list[GeneratedSuggestedAction],
) -> NormalizedReportContent:
    canonical_citations = re.sub(
        r"\[\[((?:evidence|source):[^\]\n]+)\]\]",
        r"[\1]",
        content_md,
        flags=re.IGNORECASE,
    )
    without_actions, legacy_titles = _legacy_action_titles(canonical_citations)
    allowed_assets = set(allowed_asset_ids)
    allowed_evidence = set(allowed_evidence_ids or allowed_asset_ids)
    sources_by_url = {
        str(source.get("url")): source
        for source in external_sources
        if isinstance(source, dict) and source.get("url")
    }
    citations: list[ReportCitation] = []
    used_source_urls: set[str] = set()
    clean_paragraphs: list[str] = []

    for paragraph in re.split(r"\n\s*\n", without_actions):
        if not paragraph.strip():
            continue
        asset_ids: list[str] = []
        evidence_ids: list[str] = []
        source_urls: list[str] = []

        def replace_citation(match: re.Match[str]) -> str:
            kind = match.group("kind").casefold()
            value = match.group("value").strip()
            if kind == "evidence":
                if value not in allowed_evidence:
                    raise ValueError("unknown report citation")
                if value not in evidence_ids:
                    evidence_ids.append(value)
                if value in allowed_assets and value not in asset_ids:
                    asset_ids.append(value)
            else:
                if value not in sources_by_url:
                    raise ValueError("unknown report citation")
                if value not in source_urls:
                    source_urls.append(value)
                    used_source_urls.add(value)
            return ""

        clean = CITATION_RE.sub(replace_citation, paragraph)
        if CITATION_START_RE.search(clean):
            raise ValueError("malformed report citation")
        clean = re.sub(r"[ \t]{2,}", " ", clean).strip()
        if not clean:
            continue
        clean_paragraphs.append(clean)
        if evidence_ids or source_urls:
            citations.append(
                ReportCitation(
                    paragraph_hash=hashlib.sha256(
                        clean.encode("utf-8")
                    ).hexdigest(),
                    evidence_ids=evidence_ids,
                    asset_ids=asset_ids,
                    source_urls=source_urls,
                )
            )

    return NormalizedReportContent(
        content_md="\n\n".join(clean_paragraphs),
        citations=citations,
        suggested_actions=_normalized_actions(suggested_actions, legacy_titles),
        used_external_sources=[
            source
            for source in external_sources
            if isinstance(source, dict)
            and str(source.get("url")) in used_source_urls
        ],
    )
