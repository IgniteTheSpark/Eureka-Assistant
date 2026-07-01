"""Flash completion reply agent.

Generates one short confirmation sentence after cards have already been created.
This agent is read-only: no tools, no routing, no writes.
"""

from __future__ import annotations

import asyncio
import json
import re
from typing import Any

from google.adk.agents import LlmAgent

from core.agent_runner import run_agent
from core.llm import FLASH_SKILL_MODEL


FLASH_REPLY_TIMEOUT_SECONDS = 1.2

FLASH_REPLY_INSTRUCTION = """
你是 UReka 里的 Reka。用户刚刚随口记录了一段内容，系统已经把它整理成结构化卡片。

你的任务：基于用户原话和已生成的卡片，回复一句自然、温暖、具体的确认。

要求：
- 中文。
- 只输出一句，最多两句。
- 要让用户感觉你听懂了他刚刚说的内容。
- 可以轻轻点出关键内容、时间、数量或行动，但不要像报表。
- 只能使用用户原话和卡片里已有的信息，不要编造。
- 不要出现 asset_id、tool name、JSON、字段名、内部判断。
- 不要说「已记录 N 项内容」或类似机械计数。
- 不要夸张鼓励、不要连续感叹号、不要卖萌。
- 如果有多个卡片，可以自然概括其中最重要的 2-3 个。
- 如果有需要确认的联系人或信息，可以温和提醒。

输入会包含：
source_text: 用户原话
cards: 已生成的用户可见卡片摘要
pending: 需要确认的事项
suggest_skill: 可选的技能建议

只返回最终给用户看的那句话。
""".strip()


def _slim_card(card: dict[str, Any]) -> dict[str, Any]:
    out = {
        "type": card.get("card_type") or "",
        "title": card.get("title") or "",
        "subtitle": card.get("subtitle") or "",
    }
    meta = []
    for item in card.get("meta_fields") or []:
        if not isinstance(item, dict):
            continue
        value = item.get("value")
        if value not in (None, ""):
            meta.append(str(value)[:32])
    if meta:
        out["meta"] = meta[:4]
    if card.get("suggest_skill"):
        out["suggest_skill"] = str(card.get("suggest_skill"))[:20]
    return {k: v for k, v in out.items() if v not in ("", [], None)}


def _clean_reply(text: str) -> str:
    s = (text or "").strip()
    s = re.sub(r"^```(?:json|text)?\s*", "", s).replace("```", "").strip()
    s = s.strip("\"' \n\t")
    # Guard against accidental structured output or leaked internals.
    banned = ("asset_id", "event_id", "tool_create", "payload", "JSON", "{", "}")
    if not s or any(b in s for b in banned):
        return ""
    if re.search(r"已记录\s*\d+\s*项内容", s):
        return ""
    # Keep it as a compact completion line even if the model rambles.
    parts = re.split(r"(?<=[。！？!?])\s*", s)
    compact = "".join(parts[:2]).strip()
    return compact[:80]


async def generate_flash_summary(
    source_text: str,
    cards: list[dict],
    derived_assets: list[dict],
    pending: list[dict] | None = None,
    suggest_skill: str | None = None,
    user_id: str = "default",
) -> str:
    if not cards and not pending:
        return ""

    agent = LlmAgent(
        name="flash_reply",
        model=FLASH_SKILL_MODEL,
        instruction=FLASH_REPLY_INSTRUCTION,
        tools=[],
    )
    payload = {
        "source_text": source_text[:500],
        "cards": [_slim_card(c) for c in cards[:8]],
        "pending": [
            {
                "type": p.get("skill") or p.get("status") or "pending",
                "title": (p.get("source_text") or "")[:40],
            }
            for p in (pending or [])[:4]
        ],
        "suggest_skill": suggest_skill or None,
        "asset_count": len(derived_assets or []),
    }
    msg = json.dumps(payload, ensure_ascii=False)
    try:
        result = await asyncio.wait_for(
            run_agent(agent, msg, user_id),
            timeout=FLASH_REPLY_TIMEOUT_SECONDS,
        )
    except Exception:
        return ""
    return _clean_reply(result.text)
