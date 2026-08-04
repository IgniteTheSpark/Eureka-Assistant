import json
import re
from datetime import datetime, timezone
from typing import Any

from app.domains.reports.providers import GeneratorRequest, GeneratorResult


HTML_TAG_RE = re.compile(r"<\s*/?\s*[a-zA-Z][^>]*>")
NUMBER_RE = re.compile(r"(?<![\w-])-?\d+(?:\.\d+)?")
UUID_RE = re.compile(
    r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-"
    r"[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b"
)
CITATION_RE = re.compile(
    r"\[(?P<kind>evidence|source):(?P<value>[^\]\n]+)\]",
    re.IGNORECASE,
)
CITATION_START_RE = re.compile(r"\[(?:evidence|source):", re.IGNORECASE)


def allowed_numeric_claims(request: GeneratorRequest) -> set[str]:
    evidence_text = json.dumps(
        {
            "evidence": request.evidence_bundle,
            "sources": request.external_sources,
        },
        ensure_ascii=False,
        default=str,
    )
    allowed = set(NUMBER_RE.findall(evidence_text))
    records = request.evidence_bundle.get("user_evidence", [])
    if isinstance(records, list):
        allowed.add(str(len(records)))
        counts_by_skill: dict[str, int] = {}
        for record in records:
            if not isinstance(record, dict):
                continue
            skill_id = record.get("skill_id")
            if isinstance(skill_id, str) and skill_id:
                counts_by_skill[skill_id] = counts_by_skill.get(skill_id, 0) + 1
        allowed.update(str(count) for count in counts_by_skill.values())
    allowed.add(str(len(request.external_sources)))
    return allowed


def allowed_citation_tags(request: GeneratorRequest) -> set[str]:
    tags = {
        f"[evidence:{asset_id}]"
        for asset_id in request.execution_plan.resolved_asset_ids
    }
    tags.update(
        f"[source:{url}]"
        for source in request.external_sources
        if isinstance(source, dict)
        and isinstance((url := source.get("url")), str)
        and url.startswith("https://")
    )
    return tags


def _normalized_datetime(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _walk_datetimes(value: Any) -> set[datetime]:
    found: set[datetime] = set()
    if isinstance(value, datetime):
        found.add(_normalized_datetime(value))
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            pass
        else:
            found.add(_normalized_datetime(parsed))
    elif isinstance(value, dict):
        for child in value.values():
            found.update(_walk_datetimes(child))
    elif isinstance(value, list):
        for child in value:
            found.update(_walk_datetimes(child))
    return found


def allowed_action_due_times(request: GeneratorRequest) -> set[datetime]:
    return _walk_datetimes(
        {
            "execution_plan": request.execution_plan.model_dump(mode="python"),
            "evidence": request.evidence_bundle,
        }
    )


def _walk_internal_ids(value: Any, *, key: str = "") -> set[str]:
    found: set[str] = set()
    if isinstance(value, dict):
        for child_key, child in value.items():
            if child_key.endswith("_id") and isinstance(child, str):
                found.add(child)
            found.update(_walk_internal_ids(child, key=child_key))
    elif isinstance(value, list):
        for child in value:
            found.update(_walk_internal_ids(child, key=key))
    return found


def validate_generator_result(
    raw: GeneratorResult | dict,
    *,
    request: GeneratorRequest,
) -> GeneratorResult:
    result = GeneratorResult.model_validate(raw)
    if HTML_TAG_RE.search(result.content_md):
        raise ValueError("model-supplied HTML is not allowed")

    citation_tags = [match.group(0) for match in CITATION_RE.finditer(result.content_md)]
    if CITATION_START_RE.search(CITATION_RE.sub("", result.content_md)):
        raise ValueError("malformed report citation")
    allowed_tags = allowed_citation_tags(request)
    if any(tag not in allowed_tags for tag in citation_tags):
        raise ValueError("citation is not allowed")

    allowed_numbers = allowed_numeric_claims(request)
    action_copy = " ".join(action.title for action in result.suggested_actions)
    if HTML_TAG_RE.search(action_copy):
        raise ValueError("model-supplied HTML is not allowed")
    claimed_numbers = set(NUMBER_RE.findall(f"{result.content_md} {action_copy}"))
    unsupported = claimed_numbers.difference(allowed_numbers)
    if unsupported:
        raise ValueError(
            f"unreferenced numeric claim: {sorted(unsupported)[0]}"
        )
    if claimed_numbers and not re.search(
        r"\[(?:evidence|source):[^\]]+\]",
        result.content_md,
        re.IGNORECASE,
    ):
        raise ValueError("numeric claim requires an evidence or source reference")

    allowed_due_times = allowed_action_due_times(request)
    for action in result.suggested_actions:
        if action.due_at is None:
            continue
        if _normalized_datetime(action.due_at) not in allowed_due_times:
            raise ValueError("suggested action due_at is not grounded")

    internal_ids = set(request.execution_plan.resolved_asset_ids)
    internal_ids.update(_walk_internal_ids(request.evidence_bundle))
    share_copy = " ".join(
        [
            result.share_card_spec.headline,
            result.share_card_spec.summary,
            *result.share_card_spec.highlights,
            result.share_card_spec.time_range,
        ]
    )
    if UUID_RE.search(share_copy) or any(
        internal_id and internal_id in share_copy for internal_id in internal_ids
    ):
        raise ValueError("share-card copy contains an internal identifier")
    return result
