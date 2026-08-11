"""Run opt-in live DeepSeek evaluation for natural custom-Skill routing."""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import litellm

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.config import get_settings
from app.domains.capture.agent_runner import run_agent_once
from app.domains.capture.dispatcher import decode_dispatcher_output
from app.domains.capture.intent_normalizer import normalize_intents
from app.domains.capture.skill_factory import make_dispatcher_agent
from evals.capture_semantic_cases import (
    CUSTOM_SKILLS,
    SEMANTIC_CASES,
    assert_semantic_routes,
)


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("--case", action="append", dest="case_ids")
    return parser.parse_args()


def _configure_logging() -> None:
    logging.basicConfig(level=logging.WARNING)
    for name in ("LiteLLM", "litellm", "httpx", "httpcore"):
        logging.getLogger(name).setLevel(logging.ERROR)
    litellm.suppress_debug_info = True


def _route_summary(intents) -> str:
    return ",".join(
        f"{intent.type}:{intent.operation}:{intent.custom_skill_id or '-'}"
        for intent in intents
    )


async def main() -> int:
    args = _arguments()
    if args.repeat < 1 or args.repeat > 10:
        print("failed: --repeat must be between 1 and 10")
        return 2
    model = os.environ.get("CAPTURE_AGENT_MODEL", "").strip()
    api_key = os.environ.get("CAPTURE_AGENT_API_KEY", "").strip()
    if not model or not api_key:
        print("pending: CAPTURE_AGENT_MODEL and CAPTURE_AGENT_API_KEY are required")
        return 2
    selected = [
        case
        for case in SEMANTIC_CASES
        if not args.case_ids or case.case_id in set(args.case_ids)
    ]
    if args.case_ids and len(selected) != len(set(args.case_ids)):
        known = ",".join(case.case_id for case in SEMANTIC_CASES)
        print(f"failed: unknown --case; known={known}")
        return 2

    _configure_logging()
    settings = get_settings()
    dispatcher = make_dispatcher_agent(CUSTOM_SKILLS)
    reference = datetime(2026, 8, 11, 15, 30, tzinfo=ZoneInfo("Asia/Shanghai"))
    failures = 0
    total = len(selected) * args.repeat
    for repetition in range(1, args.repeat + 1):
        for case in selected:
            result = None
            message = (
                f"reference_datetime={reference.isoformat()}\n"
                "BEGIN_UNTRUSTED_TRANSCRIPT\n"
                f"{case.utterance}\n"
                "END_UNTRUSTED_TRANSCRIPT"
            )
            try:
                result = await run_agent_once(
                    dispatcher,
                    message,
                    None,
                    model=model,
                    api_key=api_key,
                    timeout_seconds=settings.capture_agent_timeout_seconds,
                    recording_id=f"semantic-eval-{repetition}-{case.case_id}",
                    intent_ordinal=-1,
                )
                raw = decode_dispatcher_output(
                    result.text,
                    fallback_text=case.utterance,
                )
                normalized = normalize_intents(
                    raw,
                    custom_skill_names={skill.machine_name for skill in CUSTOM_SKILLS},
                    custom_skills=CUSTOM_SKILLS,
                )
                assert_semantic_routes(case, raw, stage="raw")
                assert_semantic_routes(case, normalized, stage="normalized")
            except Exception as exc:
                failures += 1
                provider_text = result.text[:500] if result is not None else ""
                print(
                    f"FAIL repeat={repetition} case={case.case_id} "
                    f"utterance={case.utterance!r} reason={exc} "
                    f"provider_text={provider_text!r}"
                )
            else:
                print(
                    f"PASS repeat={repetition} case={case.case_id} "
                    f"routes={_route_summary(normalized)}"
                )
    print(f"summary passed={total - failures}/{total} failures={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
