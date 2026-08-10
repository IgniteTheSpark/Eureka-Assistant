from __future__ import annotations

import re

from app.domains.capture.agent import CaptureSkill
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
_DELETE_WORD_RE = re.compile(r"(删除|删掉|删了|移除|清除|取消这(?:个|条|笔).*(?:记录|代办|日程))")
_UPDATE_WORD_RE = re.compile(r"(改成|改为|修改|更新|更正|纠正|调整为|换成)")
_QUERY_WORD_RE = re.compile(
    r"(帮我看看|看一下|看看|查一下|查询|统计|汇总|多少(?:钱|元|个)?|几个|有哪些|是什么|为什么|怎么样|如何)"
)
_BUILTIN = {"todo", "event", "expense", "contact", "notes", "qa"}


def normalize_intents(
    intents: list[FlashIntent],
    *,
    custom_skill_names: set[str],
    custom_skills: tuple[CaptureSkill, ...] = (),
) -> list[FlashIntent]:
    enabled_custom_skills = tuple(
        skill
        for skill in custom_skills
        if skill.enabled and skill.machine_name not in _BUILTIN
    )
    all_custom_names = {
        *custom_skill_names,
        *(skill.machine_name for skill in enabled_custom_skills),
    }
    normalized: list[FlashIntent] = []
    for intent in intents:
        canonical = _route_custom_skill(intent.model_copy(), enabled_custom_skills)
        lowered = canonical.type.strip().lower()
        if lowered in {"idea", "misc", "other", "note"}:
            canonical.type = "notes"
        elif lowered == "task":
            canonical.type = "qa"
        elif lowered not in _BUILTIN and lowered not in all_custom_names:
            canonical.type = "notes"
        else:
            canonical.type = lowered

        canonical.operation = _canonical_operation(canonical)
        pieces = _split_expense(canonical)
        for piece in pieces:
            normalized.append(
                _normalize_scheduled_custom(piece, all_custom_names)
            )
    return [
        intent.model_copy(
            update={"ordinal": ordinal, "intent_id": f"intent-{ordinal}"}
        )
        for ordinal, intent in enumerate(normalized)
    ]


def _route_custom_skill(
    intent: FlashIntent,
    custom_skills: tuple[CaptureSkill, ...],
) -> FlashIntent:
    if not custom_skills or intent.type.strip().lower() in {
        "todo",
        "event",
        "expense",
        "contact",
        "qa",
    }:
        return intent

    if intent.custom_skill_id:
        matches = [
            skill
            for skill in custom_skills
            if skill.user_skill_id == intent.custom_skill_id
        ]
        if len(matches) == 1:
            return intent.model_copy(
                update={
                    "type": matches[0].machine_name,
                    "custom_skill_id": matches[0].user_skill_id,
                    "routing_error": None,
                }
            )
        return intent.model_copy(
            update={
                "type": "notes",
                "custom_skill_id": None,
                "routing_error": "custom_skill_not_found",
            }
        )

    requested = re.sub(r"[\s_-]+", "", intent.type).casefold()
    source = re.sub(r"\s+", "", intent.source_text).casefold()

    def machine_key(skill: CaptureSkill) -> str:
        return re.sub(r"[\s_-]+", "", skill.machine_name).casefold()

    def display_key(skill: CaptureSkill) -> str:
        return re.sub(r"\s+", "", skill.display_name).casefold()

    tiers = [
        [skill for skill in custom_skills if machine_key(skill) == requested],
        [skill for skill in custom_skills if display_key(skill) == requested],
        [
            skill
            for skill in custom_skills
            if requested
            and (
                machine_key(skill).startswith(requested)
                or display_key(skill).startswith(requested)
                or requested in display_key(skill)
            )
        ],
        [
            skill
            for skill in custom_skills
            if display_key(skill) and display_key(skill) in source
        ],
    ]
    for matches in tiers:
        if len(matches) == 1:
            skill = matches[0]
            return intent.model_copy(
                update={
                    "type": skill.machine_name,
                    "custom_skill_id": skill.user_skill_id,
                    "routing_error": None,
                }
            )
        if len(matches) > 1:
            return intent.model_copy(
                update={
                    "type": "notes",
                    "custom_skill_id": None,
                    "routing_error": "custom_skill_ambiguous",
                }
            )
    return intent


def _canonical_operation(intent: FlashIntent) -> str:
    source = intent.source_text.strip()
    if _DELETE_WORD_RE.search(source):
        return "delete"
    if _UPDATE_WORD_RE.search(source):
        return "update"
    if intent.type == "qa":
        return "answer"
    if _QUERY_WORD_RE.search(source):
        return "query"
    return intent.operation


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
    if intent.type not in custom_skill_names or intent.operation != "create":
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
        update={
            "type": "event" if _RANGE_RE.search(source) else "todo",
            "custom_skill_id": None,
        }
    )
