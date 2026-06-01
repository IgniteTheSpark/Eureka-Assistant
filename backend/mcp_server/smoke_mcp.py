"""
Smoke test — third-party MCP roundtrip (task-skill → external MCP).

Exercises the full async task flow end-to-end against whatever MCPs are
enabled (default: `fake_external`), and asserts the placeholder asset
transitions pending → done with a real external_id / external_url. This is the
automated check for milestone #7 ("untested MCP"): one command proves the
orchestration (sync head → asyncio tail → LLM tool pick → MCP call →
extract external ref → asset done) actually works.

Standalone (no pytest dependency — the backend image ships no test deps):

    docker compose exec backend python -m mcp_server.smoke_mcp

Exit code 0 = PASS, 1 = FAIL. Creates one Task + external_ref Asset in the
dev DB and deletes them again on the way out (use --keep to leave them for a
visual UI check of the pending→done card).
"""
import argparse
import asyncio
import sys
import time
import uuid

from sqlalchemy import select, delete

from agents.mcp_config import MCP_SERVERS
from agents.task_skill import run_task_intent
from db.database import AsyncSessionLocal
from db.models import Asset, Task


async def _poll_until_terminal(task_id: str, timeout: float = 45.0) -> dict:
    """Poll the tasks row until status is done/failed or we time out."""
    tid = uuid.UUID(task_id)
    deadline = time.monotonic() + timeout
    last_status = "?"
    while time.monotonic() < deadline:
        async with AsyncSessionLocal() as db:
            t = (await db.execute(select(Task).where(Task.id == tid))).scalar_one_or_none()
            if t is not None:
                if t.status != last_status:
                    print(f"[smoke]   task status → {t.status}")
                    last_status = t.status
                if t.status in ("done", "failed"):
                    asset = None
                    if t.result_asset_id:
                        asset = (await db.execute(
                            select(Asset).where(Asset.id == t.result_asset_id)
                        )).scalar_one_or_none()
                    return {
                        "status":     t.status,
                        "error":      t.error_message,
                        "mcp_target": t.mcp_target,
                        "payload":    asset.payload if asset is not None else None,
                    }
        await asyncio.sleep(1)
    return {"status": "timeout", "error": f"no terminal state within {timeout}s"}


async def _cleanup(task_id: str, asset_id: str | None) -> None:
    # Order matters: tasks.result_asset_id FK references assets, so the Task
    # row must go first or the Asset delete violates the constraint.
    async with AsyncSessionLocal() as db:
        await db.execute(delete(Task).where(Task.id == uuid.UUID(task_id)))
        if asset_id:
            await db.execute(delete(Asset).where(Asset.id == uuid.UUID(asset_id)))
        await db.commit()


async def main() -> int:
    ap = argparse.ArgumentParser(description="MCP roundtrip smoke test")
    ap.add_argument("--keep", action="store_true",
                    help="leave the created Task + Asset in the DB (for a UI check)")
    ap.add_argument("--text", default="把这条笔记『MCP 冒烟测试』同步到 Notion",
                    help="user_text to dispatch through the task-skill")
    args = ap.parse_args()

    print(f"[smoke] enabled MCPs: {list(MCP_SERVERS)}")
    if not MCP_SERVERS:
        print("[smoke] FAIL: no MCPs enabled — set EUREKA_MCP_ENABLED (default fake_external)")
        return 1

    print(f"[smoke] dispatch: {args.text!r}")
    head = await run_task_intent(user_text=args.text, user_id="default")
    print(f"[smoke] sync head: ok={head.get('ok')} task_id={head.get('task_id')} "
          f"status={head.get('status')}")
    if not head.get("ok"):
        print(f"[smoke] FAIL: sync head error: {head.get('error')}")
        return 1

    task_id  = head["task_id"]
    asset_id = head.get("asset_id")
    result = await _poll_until_terminal(task_id)
    print(f"[smoke] terminal: status={result['status']} mcp_target={result.get('mcp_target')!r}")

    ok = True
    if result["status"] != "done":
        print(f"[smoke] FAIL: task did not complete (status={result['status']}, "
              f"error={result.get('error')!r})")
        ok = False
    else:
        payload = result.get("payload") or {}
        missing = [k for k in ("external_id", "external_url") if not payload.get(k)]
        if payload.get("status") != "done" or missing:
            print(f"[smoke] FAIL: asset payload incomplete (missing={missing}): {payload}")
            ok = False
        else:
            print(f"[smoke] PASS: synced to {payload.get('external_system')} "
                  f"id={payload.get('external_id')} url={payload.get('external_url')}")

    if args.keep:
        print(f"[smoke] --keep: leaving task={task_id} asset={asset_id} in DB")
    else:
        await _cleanup(task_id, asset_id)
        print("[smoke] cleaned up test task + asset")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
