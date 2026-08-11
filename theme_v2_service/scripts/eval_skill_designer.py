"""Opt-in live DeepSeek checks for custom Skill scope confirmation and routing."""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import sys
from pathlib import Path

import litellm

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.domains.assets.skill_design import design_skill_step


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repeat", type=int, default=1)
    return parser.parse_args()


def _configure_logging() -> None:
    logging.basicConfig(level=logging.WARNING)
    for name in ("LiteLLM", "litellm", "httpx", "httpcore"):
        logging.getLogger(name).setLevel(logging.ERROR)
    litellm.suppress_debug_info = True


def _questions(result: dict, *, case_id: str) -> tuple[dict, dict]:
    questions = result.get("questions")
    if not isinstance(questions, list) or len(questions) != 2:
        raise AssertionError(f"{case_id}: expected scope and recording-content questions")
    scope, content = questions
    options = scope.get("options")
    if not isinstance(options, list) or not 2 <= len(options) <= 3:
        raise AssertionError(f"{case_id}: expected 2-3 scope options")
    content_options = content.get("options")
    if (
        content.get("type") != "choice"
        or content.get("multiple") is not True
        or not isinstance(content_options, list)
        or len(content_options) < 2
    ):
        raise AssertionError(
            f"{case_id}: expected one multi-choice recording-content question"
        )
    return scope, content


def _choose(options: list[str], keywords: tuple[str, ...]) -> str:
    for option in options:
        if any(keyword in option for keyword in keywords):
            return option
    return options[0]


def _draft(result: dict, *, case_id: str) -> dict:
    draft = result.get("draft")
    if not isinstance(draft, dict):
        raise AssertionError(f"{case_id}: expected a completed draft")
    fields = draft.get("payload_schema")
    profile = draft.get("routing_profile")
    if not isinstance(fields, dict) or not 2 <= len(fields) <= 6:
        raise AssertionError(f"{case_id}: expected 2-6 editable fields")
    if not isinstance(profile, dict) or not str(profile.get("intent") or "").strip():
        raise AssertionError(f"{case_id}: missing routing intent")
    for key in (
        "aliases",
        "include",
        "exclude",
        "positive_examples",
        "negative_examples",
    ):
        if not isinstance(profile.get(key), list) or not profile[key]:
            raise AssertionError(f"{case_id}: missing routing {key}")
    return draft


def _contains_any(values: list[str], keywords: tuple[str, ...]) -> bool:
    text = " ".join(values)
    return any(keyword in text for keyword in keywords)


async def _water_case() -> dict:
    scope, content = _questions(
        await design_skill_step("喝水记录", []),
        case_id="water",
    )
    options = scope["options"]
    if not _contains_any(options, ("白水", "矿泉水", "纯净水")):
        raise AssertionError("water: options do not expose plain-water scope")
    answer = _choose(options, ("只", "仅", "白水"))
    draft = _draft(
        await design_skill_step(
            "喝水记录",
            [
                {"key": scope["key"], "value": answer},
                {"key": content["key"], "value": "饮水量和时间"},
            ],
        ),
        case_id="water",
    )
    profile = draft["routing_profile"]
    if not _contains_any(
        profile["exclude"] + profile["negative_examples"],
        ("咖啡", "茶", "牛奶", "饮料", "购买", "提醒"),
    ):
        raise AssertionError("water: plain-water profile has no beverage/action boundary")
    return {"questions": [scope, content], "answer": answer, "draft": draft}


async def _dance_case() -> dict:
    scope, content = _questions(
        await design_skill_step("跳舞记录", []),
        case_id="dance",
    )
    answer = _choose(scope["options"], ("实际", "练习", "训练", "每次"))
    draft = _draft(
        await design_skill_step(
            "跳舞记录",
            [
                {"key": scope["key"], "value": answer},
                {
                    "key": content["key"],
                    "value": "舞种、时长、舞社地点和感受",
                },
            ],
        ),
        case_id="dance",
    )
    profile = draft["routing_profile"]
    if not _contains_any(
        profile["exclude"] + profile["negative_examples"],
        ("未来", "计划", "提醒", "购买", "观看"),
    ):
        raise AssertionError("dance: completed-activity profile has no future boundary")
    return {"questions": [scope, content], "answer": answer, "draft": draft}


async def _detailed_running_case() -> dict:
    result = await design_skill_step(
        "记录每次已经完成的跑步，回看距离、配速、地点和感受；未来跑步计划不要记录。",
        [],
    )
    if result.get("questions"):
        raise AssertionError("detailed_running: asked a redundant scope question")
    draft = _draft(result, case_id="detailed_running")
    return {"draft": draft}


def _summary(value: dict) -> str:
    questions = value.get("questions") or []
    draft = value["draft"]
    profile = draft["routing_profile"]
    return json.dumps(
        {
            "questions": [question.get("prompt") for question in questions],
            "scope_options": questions[0].get("options") if questions else None,
            "answer": value.get("answer"),
            "display_name": draft.get("display_name"),
            "fields": list(draft["payload_schema"]),
            "routing_profile": profile,
        },
        ensure_ascii=False,
    )


async def main() -> int:
    args = _arguments()
    if args.repeat < 1 or args.repeat > 5:
        print("failed: --repeat must be between 1 and 5")
        return 2
    if not os.environ.get("CAPTURE_AGENT_MODEL", "").strip() or not os.environ.get(
        "CAPTURE_AGENT_API_KEY", ""
    ).strip():
        print("pending: CAPTURE_AGENT_MODEL and CAPTURE_AGENT_API_KEY are required")
        return 2
    _configure_logging()
    cases = {
        "water": _water_case,
        "dance": _dance_case,
        "detailed_running": _detailed_running_case,
    }
    failures = 0
    total = len(cases) * args.repeat
    for repetition in range(1, args.repeat + 1):
        for case_id, evaluate in cases.items():
            try:
                value = await evaluate()
            except Exception as exc:
                failures += 1
                print(f"FAIL repeat={repetition} case={case_id} reason={exc}")
            else:
                print(
                    f"PASS repeat={repetition} case={case_id} "
                    f"result={_summary(value)}"
                )
    print(f"summary passed={total - failures}/{total} failures={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
