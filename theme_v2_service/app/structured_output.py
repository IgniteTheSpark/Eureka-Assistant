from __future__ import annotations

import json
import re
from typing import Any


_FENCED_JSON_RE = re.compile(
    r"^```(?:json)?\s*(?P<body>[\s\S]*?)\s*```$",
    re.IGNORECASE,
)


def extract_json_object(content: str) -> dict[str, Any] | None:
    """Return one JSON object while tolerating model presentation text."""

    normalized = content.strip()
    fenced = _FENCED_JSON_RE.match(normalized)
    if fenced is not None:
        normalized = fenced.group("body").strip()

    for candidate in (normalized, content.strip()):
        try:
            decoded = json.loads(candidate)
        except (json.JSONDecodeError, TypeError, ValueError):
            continue
        if isinstance(decoded, dict):
            return decoded

    decoder = json.JSONDecoder()
    starts = [index for index, character in enumerate(normalized) if character == "{"]
    candidates: list[tuple[int, int, dict[str, Any]]] = []
    for start in starts:
        try:
            decoded, end = decoder.raw_decode(normalized, start)
        except (json.JSONDecodeError, TypeError, ValueError):
            continue
        if isinstance(decoded, dict):
            candidates.append((start, end, decoded))
    top_level = [
        candidate
        for candidate in candidates
        if not any(
            outer_start <= candidate[0]
            and outer_end >= candidate[1]
            and (outer_start, outer_end) != candidate[:2]
            for outer_start, outer_end, _ in candidates
        )
    ]
    if top_level:
        return max(top_level, key=lambda candidate: candidate[0])[2]
    return None
