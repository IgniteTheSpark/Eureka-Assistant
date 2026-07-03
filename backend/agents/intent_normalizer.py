"""Deterministic validation for Flash dispatcher output.

The dispatcher is an LLM semantic classifier. This module enforces the backend
execution contract before sub-skill agents run: each intent must be atomic and
must not route scheduled future items into record-style custom skills.
"""
from __future__ import annotations

import re
from typing import Any


_MONEY_RE = re.compile(r"\d+(?:\.\d+)?\s*(?:块钱|块|元|人民币|rmb|RMB|¥)")
_CLAUSE_SPLIT_RE = re.compile(r"[。；;，,]|然后|另外|还有|对了|再就是")

_SCHEDULE_WORD_RE = re.compile(
    r"(有一场|有一个|要|需要|参加|去|约|预约|安排|提醒|比赛|球赛|训练|课程|课)"
)
_TIME_WORD_RE = re.compile(
    r"(今天|明天|后天|早上|上午|中午|下午|晚上|今晚|周[一二三四五六日天]|"
    r"\d{1,2}\s*(?:点|时|[:：]))"
)
_RANGE_RE = re.compile(
    r"(\d{1,2}\s*(?:点|时|[:：])?\s*(?:到|~|-|—|－)\s*\d{1,2}\s*(?:点|时|[:：])?)|"
    r"(\d+(?:\.\d+)?\s*(?:小时|个小时|分钟))|全天|一整天"
)
_DONE_RECORD_WORD_RE = re.compile(
    r"(赢|输了?|比分|成绩|得分|打了|跑了|练了|完成|感觉|复盘|记录一下)"
)


def _match_custom_skill(itype: str, custom_map: dict[str, dict]) -> str | None:
    """Resolve dispatcher-emitted type to a real custom-skill key."""
    if not itype or not custom_map:
        return None
    if itype in custom_map:
        return itype
    low = itype.strip().lower()
    for key, meta in custom_map.items():
        kl = key.lower()
        if kl == low or kl.startswith(low) or low.startswith(kl):
            return key
        if (meta.get("display_name") or "").strip().lower() == low:
            return key
    return None


def _split_multi_expense_intent(intent: dict[str, Any]) -> list[dict[str, Any]]:
    source = str(intent.get("source_text") or "")
    if len(_MONEY_RE.findall(source)) < 2:
        return [intent]
    clauses = [c.strip() for c in _CLAUSE_SPLIT_RE.split(source) if c.strip()]
    money_clauses = [c for c in clauses if _MONEY_RE.search(c)]
    if len(money_clauses) < 2:
        return [intent]
    out: list[dict[str, Any]] = []
    for clause in money_clauses:
        cloned = dict(intent)
        cloned["source_text"] = clause
        out.append(cloned)
    return out


def _normalize_scheduled_custom_intent(
    intent: dict[str, Any],
    custom_skill_map: dict[str, dict],
) -> dict[str, Any]:
    matched = _match_custom_skill(str(intent.get("type") or ""), custom_skill_map)
    if not matched:
        return intent
    source = str(intent.get("source_text") or "")
    scheduled = (
        _SCHEDULE_WORD_RE.search(source)
        and _TIME_WORD_RE.search(source)
        and not _DONE_RECORD_WORD_RE.search(source)
    )
    if not scheduled:
        return intent
    cloned = dict(intent)
    cloned["type"] = "event" if _RANGE_RE.search(source) else "todo"
    return cloned


def normalize_intents(
    intents: list[Any],
    custom_skill_map: dict[str, dict],
) -> list[dict[str, Any]]:
    """Return executable, atomic intents.

    Invariants:
    - one expense intent creates at most one expense record;
    - record-style custom skills cannot steal future scheduled activities;
    - malformed non-dict dispatcher entries are dropped.
    """
    out: list[dict[str, Any]] = []
    for raw in intents:
        if not isinstance(raw, dict):
            continue
        split = _split_multi_expense_intent(raw) if raw.get("type") == "expense" else [raw]
        for item in split:
            out.append(_normalize_scheduled_custom_intent(item, custom_skill_map))
    return out
