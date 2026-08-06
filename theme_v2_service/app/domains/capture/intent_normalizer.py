from __future__ import annotations

import re

from app.domains.capture.dispatcher import FlashIntent


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
_BUILTIN = {"todo", "event", "expense", "contact", "notes", "qa"}


def normalize_intents(
    intents: list[FlashIntent],
    *,
    custom_skill_names: set[str],
) -> list[FlashIntent]:
    normalized: list[FlashIntent] = []
    for intent in intents:
        canonical = intent.model_copy()
        lowered = canonical.type.strip().lower()
        if lowered in {"idea", "misc", "other", "note"}:
            canonical.type = "notes"
        elif lowered == "task":
            canonical.type = "qa"
        elif lowered not in _BUILTIN and lowered not in custom_skill_names:
            canonical.type = "notes"
        else:
            canonical.type = lowered

        pieces = _split_expense(canonical)
        for piece in pieces:
            normalized.append(
                _normalize_scheduled_custom(piece, custom_skill_names)
            )
    return normalized


def _split_expense(intent: FlashIntent) -> list[FlashIntent]:
    if intent.type != "expense" or len(_MONEY_RE.findall(intent.source_text)) < 2:
        return [intent]
    clauses = [
        clause.strip()
        for clause in _CLAUSE_SPLIT_RE.split(intent.source_text)
        if clause.strip()
    ]
    money_clauses = [clause for clause in clauses if _MONEY_RE.search(clause)]
    if len(money_clauses) < 2:
        return [intent]
    return [intent.model_copy(update={"source_text": clause}) for clause in money_clauses]


def _normalize_scheduled_custom(
    intent: FlashIntent,
    custom_skill_names: set[str],
) -> FlashIntent:
    if intent.type not in custom_skill_names:
        return intent
    source = intent.source_text
    scheduled = (
        _SCHEDULE_WORD_RE.search(source)
        and _TIME_WORD_RE.search(source)
        and not _DONE_RECORD_WORD_RE.search(source)
    )
    if not scheduled:
        return intent
    return intent.model_copy(
        update={"type": "event" if _RANGE_RE.search(source) else "todo"}
    )
