import json
import re
from typing import Any

from app.domains.reports.providers import GeneratorRequest, GeneratorResult


HTML_TAG_RE = re.compile(r"<\s*/?\s*[a-zA-Z][^>]*>")
NUMBER_RE = re.compile(r"(?<![\w-])-?\d+(?:\.\d+)?")
UUID_RE = re.compile(
    r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-"
    r"[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b"
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

    evidence_text = json.dumps(
        {
            "evidence": request.evidence_bundle,
            "sources": request.external_sources,
        },
        ensure_ascii=False,
        default=str,
    )
    allowed_numbers = set(NUMBER_RE.findall(evidence_text))
    claimed_numbers = set(NUMBER_RE.findall(result.content_md))
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
