"""
Regression test for the empty-DingTalk-doc bug.

Root cause: the chat Assistant intermittently calls tool_create_task with an
empty `content` for "把刚刚那个回答放到钉钉文档" requests, producing a doc with a
title but no body. The fix adds a backend safety net in task_skill.run_task_intent:
when content is empty + the request references prior chat content + we have the
session, recover the body from the last substantive assistant reply.

This test exercises that recovery logic directly (no LLM, no MCP), so it is
deterministic. It fails if the helpers are removed/regressed.

Run:
    docker compose run --rm backend python -m scripts.test_content_fallback
"""
import asyncio
import sys
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete

from db.database import AsyncSessionLocal
from db.models import Session as DBSession, Message, Task, Asset
import agents.task_skill as task_skill
from agents.task_skill import (
    _references_prior_content,
    _recover_prior_reply,
    run_task_intent,
)

ANSWER = "地球之所以是圆的，是因为引力使物质均匀分布形成球体。"
ECHO = "已记录 1 项内容。"


def check(name: str, cond: bool) -> bool:
    print(f"  {'✓' if cond else '✗'} {name}")
    return cond


async def main() -> int:
    ok = True

    # ── Pure predicate: which phrasings count as a back-reference ──
    print("[_references_prior_content]")
    ok &= check("'把刚刚那个问题的答案放到钉钉文档里吗' → True",
                _references_prior_content("可以帮我把刚刚那个问题的答案放到钉钉文档里吗"))
    ok &= check("'把上面那段分析同步到钉钉文档' → True",
                _references_prior_content("把上面那段分析同步到钉钉文档"))
    ok &= check("'创建一个明天下午三点的会议' → False",
                not _references_prior_content("创建一个明天下午三点的会议"))
    ok &= check("'存到钉钉文档'(无引用) → False",
                not _references_prior_content("存到钉钉文档"))

    # ── DB recovery: latest substantive agent reply, skipping status echoes ──
    print("[_recover_prior_reply]")
    uid = "default"
    sid = None
    async with AsyncSessionLocal() as db:
        sess = DBSession(user_id=uid, session_type="chat", title="fallback-test")
        db.add(sess)
        await db.flush()
        sid = sess.id
        base = datetime.now(timezone.utc)
        # Real answer first, then a status echo as the MOST RECENT message —
        # recovery must skip the echo and return the answer.
        db.add(Message(session_id=sid, user_id=uid, role="agent", text=ANSWER,
                       created_at=base))
        db.add(Message(session_id=sid, user_id=uid, role="agent", text=ECHO,
                       created_at=base + timedelta(seconds=1)))
        await db.commit()

    captured = {}
    task_id = asset_id = None
    try:
        recovered = await _recover_prior_reply(str(sid), uid)
        ok &= check(f"recovers the answer, skips echo (got {recovered[:18]!r}…)",
                    recovered == ANSWER)
        ok &= check("bad session_id → '' (no crash)",
                    await _recover_prior_reply("not-a-uuid", uid) == "")

        # ── End-to-end wiring: run_task_intent with empty content (the LLM
        #    dropped it) must hand the recovered body to the async tail. Stub
        #    the tail so we capture its content without touching any MCP. ──
        print("[run_task_intent content recovery]")
        orig = task_skill._run_task_async

        async def _spy(**kwargs):
            captured.update(kwargs)

        task_skill._run_task_async = _spy
        try:
            res = await run_task_intent(
                user_text="可以帮我把刚刚那个问题的答案放到钉钉文档里吗",
                session_id=str(sid),
                user_id=uid,
                content="",  # simulate the LLM dropping the body
            )
            task_id, asset_id = res.get("task_id"), res.get("asset_id")
            await asyncio.sleep(0.05)  # let create_task schedule the stub
        finally:
            task_skill._run_task_async = orig

        ok &= check(f"empty content → tail gets recovered body "
                    f"(got {captured.get('content', '')[:18]!r}…)",
                    captured.get("content") == ANSWER)
    finally:
        async with AsyncSessionLocal() as db:
            if task_id:
                await db.execute(delete(Task).where(Task.id == uuid.UUID(task_id)))
            if asset_id:
                await db.execute(delete(Asset).where(Asset.id == uuid.UUID(asset_id)))
            await db.execute(delete(Message).where(Message.session_id == sid))
            await db.execute(delete(DBSession).where(DBSession.id == sid))
            await db.commit()

    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
