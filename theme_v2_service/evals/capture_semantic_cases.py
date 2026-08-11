"""Natural-language routing cases for the opt-in live DeepSeek capture eval."""

from __future__ import annotations

from dataclasses import dataclass

from app.domains.capture.agent import CaptureSkill
from app.domains.capture.dispatcher import FlashIntent


@dataclass(frozen=True)
class ExpectedRoute:
    type: str
    operation: str = "create"
    custom_skill_id: str | None = None


@dataclass(frozen=True)
class SemanticCase:
    case_id: str
    utterance: str
    expected: tuple[ExpectedRoute, ...]


class SemanticRouteMismatch(AssertionError):
    pass


def _routing(
    *,
    intent: str,
    aliases: list[str],
    include: list[str],
    exclude: list[str],
    positive: list[str],
    negative: list[str],
) -> dict:
    return {
        "intent": intent,
        "aliases": aliases,
        "include": include,
        "exclude": exclude,
        "positive_examples": positive,
        "negative_examples": negative,
    }


CUSTOM_SKILLS = (
    CaptureSkill(
        user_skill_id="skill-water",
        machine_name="daily_water_intake",
        display_name="喝水记录",
        description="记录用户实际喝下的白水",
        schema_definition={
            "type": "object",
            "properties": {
                "amount_ml": {
                    "type": "number",
                    "title": "饮水量",
                    "description": "实际喝下的毫升数",
                },
                "occurred_at": {
                    "type": "string",
                    "format": "date-time",
                    "title": "饮水时间",
                    "description": "实际饮水时间",
                },
            },
            "x-capture-enabled": True,
            "x-routing": _routing(
                intent="记录用户已经实际喝下的白水",
                aliases=["喝水", "饮水", "补水"],
                include=["白水", "矿泉水", "纯净水", "饮用水"],
                exclude=[
                    "咖啡",
                    "茶",
                    "牛奶",
                    "酒",
                    "汽水",
                    "购买水",
                    "提醒喝水",
                ],
                positive=["刚喝了500毫升水", "睡前灌了一瓶农夫山泉"],
                negative=["下午喝了一杯拿铁", "买矿泉水花了6块", "提醒我晚上喝水"],
            ),
        },
    ),
    CaptureSkill(
        user_skill_id="skill-running",
        machine_name="running_log",
        display_name="跑步记录",
        description="记录用户已经完成的跑步活动",
        schema_definition={
            "type": "object",
            "properties": {
                "distance_km": {
                    "type": "number",
                    "title": "距离",
                    "description": "已经完成的跑步公里数",
                },
                "pace": {
                    "type": "string",
                    "title": "配速",
                    "description": "本次跑步配速",
                },
            },
            "x-capture-enabled": True,
            "x-routing": _routing(
                intent="记录已经完成的跑步、晨跑或慢跑",
                aliases=["跑步", "晨跑", "慢跑"],
                include=["已经跑完", "刚跑完", "实际跑步成绩"],
                exclude=["未来跑步计划", "跑步提醒", "观看跑步比赛"],
                positive=["刚跑完五公里，配速六分半", "今早绕小区跑了三圈"],
                negative=["明早去跑五公里", "提醒我晚上跑步"],
            ),
        },
    ),
    CaptureSkill(
        user_skill_id="skill-dance",
        machine_name="dance_log",
        display_name="跳舞记录",
        description="记录用户已经完成的舞蹈练习或训练",
        schema_definition={
            "type": "object",
            "properties": {
                "dance_style": {
                    "type": "string",
                    "title": "舞种",
                    "description": "例如 hiphop 或 locking",
                },
                "duration_minutes": {
                    "type": "integer",
                    "title": "时长",
                    "description": "实际练习分钟数",
                },
                "venue": {
                    "type": "string",
                    "title": "地点",
                    "description": "舞蹈练习地点",
                },
            },
            "x-capture-enabled": True,
            "x-routing": _routing(
                intent="记录已经完成的跳舞、街舞或舞蹈训练",
                aliases=["跳舞", "街舞", "舞蹈练习", "hiphop", "locking"],
                include=["已经完成的舞蹈练习", "舞种", "练舞地点"],
                exclude=["未来舞蹈课程", "购买舞蹈课", "观看舞蹈演出"],
                positive=["刚练完一小时 hiphop", "昨晚跳了会 locking"],
                negative=["周六下午三点去上舞蹈课", "买了一节街舞课"],
            ),
        },
    ),
    CaptureSkill(
        user_skill_id="skill-tennis",
        machine_name="tennis_match_log",
        display_name="网球比赛记录",
        description="记录用户已经完成的网球比赛及赛果",
        schema_definition={
            "type": "object",
            "properties": {
                "opponent": {
                    "type": "string",
                    "title": "对手",
                    "description": "本场比赛对手",
                },
                "score": {
                    "type": "string",
                    "title": "比分",
                    "description": "已经结束比赛的比分",
                },
                "result": {
                    "type": "string",
                    "title": "结果",
                    "description": "胜负结果",
                },
            },
            "x-capture-enabled": True,
            "x-routing": _routing(
                intent="记录已经结束的网球比赛、比分和胜负",
                aliases=["网球比赛", "网球赛", "打网球"],
                include=["已完成比赛", "比分", "对手", "胜负"],
                exclude=["未来约球", "网球提醒", "购买网球用品"],
                positive=["昨晚和 Alex 打了一场，6 比 4 赢了"],
                negative=["明天下午和 Alex 打球", "买网球花了80块"],
            ),
        },
    ),
)


def _route(
    route_type: str,
    operation: str = "create",
    skill_id: str | None = None,
) -> ExpectedRoute:
    return ExpectedRoute(route_type, operation, skill_id)


SEMANTIC_CASES = (
    SemanticCase(
        "water_interleaved_quantity",
        "刚刚还喝了123ml的水。",
        (_route("daily_water_intake", skill_id="skill-water"),),
    ),
    SemanticCase(
        "water_late_night",
        "昨天晚上11点多，也喝了80ml的水。",
        (_route("daily_water_intake", skill_id="skill-water"),),
    ),
    SemanticCase(
        "water_cups_natural",
        "下午补了两大杯水。",
        (_route("daily_water_intake", skill_id="skill-water"),),
    ),
    SemanticCase(
        "water_brand_natural",
        "睡前灌了一瓶农夫山泉。",
        (_route("daily_water_intake", skill_id="skill-water"),),
    ),
    SemanticCase(
        "water_latte_negative",
        "下午喝了一杯拿铁。",
        (_route("notes"),),
    ),
    SemanticCase(
        "water_purchase_is_expense",
        "买了两瓶矿泉水花了6块。",
        (_route("expense"),),
    ),
    SemanticCase(
        "water_reminder_is_todo",
        "提醒我晚上九点喝水。",
        (_route("todo"),),
    ),
    SemanticCase(
        "running_natural",
        "刚跑完五公里，配速六分半。",
        (_route("running_log", skill_id="skill-running"),),
    ),
    SemanticCase(
        "running_neighborhood_natural",
        "今早绕小区跑了三圈。",
        (_route("running_log", skill_id="skill-running"),),
    ),
    SemanticCase(
        "running_future_is_todo",
        "明早去跑五公里。",
        (_route("todo"),),
    ),
    SemanticCase(
        "dance_natural",
        "刚在 HHDance 练完 hiphop，一个半小时。",
        (_route("dance_log", skill_id="skill-dance"),),
    ),
    SemanticCase(
        "dance_locking_natural",
        "昨晚跳了会 locking，地点还是工体。",
        (_route("dance_log", skill_id="skill-dance"),),
    ),
    SemanticCase(
        "dance_future_is_todo",
        "周六下午三点去上舞蹈课。",
        (_route("todo"),),
    ),
    SemanticCase(
        "tennis_natural",
        "昨晚和 Alex 打了一场，6 比 4 赢了。",
        (_route("tennis_match_log", skill_id="skill-tennis"),),
    ),
    SemanticCase(
        "tennis_future_is_todo",
        "明天下午和 Alex 打球。",
        (_route("todo"),),
    ),
    SemanticCase(
        "mixed_expense_water",
        "早上吃饭花了28块，刚刚还喝了123ml的水。",
        (
            _route("expense"),
            _route("daily_water_intake", skill_id="skill-water"),
        ),
    ),
    SemanticCase(
        "mixed_dance_expense_water",
        "练了一小时 hiphop，花45块报名费，又喝了500ml水。",
        (
            _route("dance_log", skill_id="skill-dance"),
            _route("expense"),
            _route("daily_water_intake", skill_id="skill-water"),
        ),
    ),
    SemanticCase(
        "mixed_real_dance_water_expense",
        "昨天晚上，我去ABC舞社跳了一个舞，跳的是hiphop，然后跳舞的时候喝了500ml水。然后今天早上吃麦当劳花了35块钱。",
        (
            _route("dance_log", skill_id="skill-dance"),
            _route("daily_water_intake", skill_id="skill-water"),
            _route("expense"),
        ),
    ),
    SemanticCase(
        "mixed_running_expense_water",
        "昨天跑了5公里，晚饭花32块，又喝了200ml水。",
        (
            _route("running_log", skill_id="skill-running"),
            _route("expense"),
            _route("daily_water_intake", skill_id="skill-water"),
        ),
    ),
    SemanticCase(
        "water_update",
        "把刚才那条喝水从500改成300。",
        (_route("daily_water_intake", "update", "skill-water"),),
    ),
    SemanticCase(
        "running_delete",
        "删掉昨晚那条跑步。",
        (_route("running_log", "delete", "skill-running"),),
    ),
    SemanticCase(
        "water_query",
        "帮我看看最近一周喝了多少水。",
        (_route("daily_water_intake", "query", "skill-water"),),
    ),
    SemanticCase(
        "notes_fallback",
        "记一下今天有点累。",
        (_route("notes"),),
    ),
)


def _actual_routes(intents: list[FlashIntent]) -> tuple[ExpectedRoute, ...]:
    return tuple(
        ExpectedRoute(
            type=intent.type,
            operation=intent.operation,
            custom_skill_id=intent.custom_skill_id,
        )
        for intent in intents
    )


def assert_semantic_routes(
    case: SemanticCase,
    intents: list[FlashIntent],
    *,
    stage: str,
) -> None:
    actual = _actual_routes(intents)
    comparable = actual
    if stage == "raw" and len(actual) == len(case.expected):
        protected_builtins = {"todo", "event", "expense", "contact", "qa"}
        comparable = tuple(
            ExpectedRoute(
                type=(
                    expected.type
                    if expected.custom_skill_id
                    and observed.custom_skill_id == expected.custom_skill_id
                    and observed.type not in protected_builtins
                    else observed.type
                ),
                operation=observed.operation,
                custom_skill_id=observed.custom_skill_id,
            )
            for expected, observed in zip(case.expected, actual, strict=True)
        )
    if comparable != case.expected:
        raise SemanticRouteMismatch(
            f"{case.case_id} stage={stage} expected={case.expected!r} actual={actual!r}"
        )
