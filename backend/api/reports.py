"""
/api/reports — synthesis/report engine (§6).

  GET    /api/reports        — list (lightweight: no html/md body)
  GET    /api/reports/{id}   — one full report (html + content_md + spec)
  POST   /api/reports        — persist a generated report (md + html + spec)
  DELETE /api/reports/{id}   — delete one

The pipeline (agents/report_pipeline.py) is the usual writer via POST; the
report container lists via GET and the WebView viewer reads one via GET /{id}.
"""
import asyncio
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy import select

from core.auth import get_current_user_id
from core.streaming import sse_event, with_heartbeats
from db.database import AsyncSessionLocal
from db.models import Report

router = APIRouter()

_GENRES = {"data-report", "idea-synthesis", "proposal", "digest", "briefing", "morning-briefing"}


def _meta(r: Report) -> dict:
    """List-row shape — no heavy html/content_md."""
    return {
        "id":          str(r.id),
        "title":       r.title,
        "genre":       r.genre,
        "spec":        r.spec_json or {},
        "suggested_actions": r.suggested_actions or [],  # §6.13 native action bar
        "gen_ms":      r.gen_ms,        # §6.12 batch 0 — may be shown
        "tokens_used": r.tokens_used,   # admin/telemetry
        "created_at":  r.created_at.isoformat() if r.created_at else None,
    }


def _full(r: Report) -> dict:
    return {**_meta(r), "content_md": r.content_md, "html": r.html}


class CreateReportRequest(BaseModel):
    title: str
    genre: str
    content_md: str
    html: str
    spec: dict | None = None


@router.get("/reports")
async def list_reports(
    limit:   int = Query(50, le=200),
    user_id: str = Depends(get_current_user_id),
):
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(Report)
            .where(Report.user_id == user_id)
            .order_by(Report.created_at.desc())
            .limit(limit)
        )).scalars().all()
    return {"ok": True, "reports": [_meta(r) for r in rows]}


@router.get("/reports/{report_id}")
async def get_report(report_id: str, user_id: str = Depends(get_current_user_id)):
    try:
        rid = uuid.UUID(report_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid report id")
    async with AsyncSessionLocal() as db:
        r = (await db.execute(
            select(Report).where(Report.id == rid, Report.user_id == user_id)
        )).scalar_one_or_none()
    if r is None:
        raise HTTPException(status_code=404, detail="report not found")
    return {"ok": True, "report": _full(r)}


@router.post("/reports")
async def create_report(req: CreateReportRequest, user_id: str = Depends(get_current_user_id)):
    genre = req.genre.strip()
    if genre not in _GENRES:
        raise HTTPException(status_code=400, detail=f"invalid genre: {genre}")
    if not req.content_md.strip() or not req.html.strip():
        raise HTTPException(status_code=400, detail="content_md and html are required")
    from agents.report_pipeline import _extract_actions
    r = Report(
        user_id=user_id,
        title=(req.title or "报告").strip()[:255],
        genre=genre,
        content_md=req.content_md,
        html=req.html,
        spec_json=req.spec or {},
        suggested_actions=_extract_actions(req.content_md) or None,
    )
    async with AsyncSessionLocal() as db:
        db.add(r)
        await db.commit()
        await db.refresh(r)
        payload = _full(r)
    return {"ok": True, "report": payload}


class IntakeMessage(BaseModel):
    role: str = "user"
    text: str = ""


class IntakeRequest(BaseModel):
    messages: list[IntakeMessage]


@router.post("/reports/intake")
async def report_intake(req: IntakeRequest, user_id: str = Depends(get_current_user_id)):
    """Guided-dialogue gate (§6.8.2): is the conversation specific enough to
    scope a report, or should the wizard ask one clarifying question?"""
    from agents.report_pipeline import run_intake
    msgs = [{"role": m.role, "text": m.text} for m in req.messages]
    return {"ok": True, **(await run_intake(msgs, user_id))}


class GenerateReportRequest(BaseModel):
    user_wish: str
    source_asset_ids: list[str] | None = None
    selected_summary: list | None = None


# Strong refs to in-flight generation tasks so they survive the SSE client
# disconnecting (closing the reka popup mid-generation). asyncio only weakly
# tracks create_task() results — without a strong ref the task can be GC'd and
# cancelled. The runner persists the report itself (run_report → _persist), so a
# detached task = a durable report that lands in the reports list regardless.
_BG_GEN: set = set()


@router.post("/reports/generate")
async def generate_report(req: GenerateReportRequest, user_id: str = Depends(get_current_user_id)):
    """Run the report pipeline, streaming progress over SSE. Emits:
    `status` (phase ticks) → `report` (full report dict) → `done`, or `error`."""
    # Imported lazily so the heavy agent stack loads at call time, not import.
    from agents.report_pipeline import run_report

    async def stream():
        queue: asyncio.Queue = asyncio.Queue()

        async def on_phase(name: str, msg: str):
            await queue.put(("status", {"phase": name, "message": msg}))

        async def runner():
            try:
                rep = await run_report(
                    req.user_wish, user_id,
                    selected_summary=req.selected_summary,
                    source_asset_ids=req.source_asset_ids,
                    on_phase=on_phase,
                )
                if rep.get("insufficient"):
                    found = rep.get("found", 0)
                    await queue.put(("insufficient", {
                        "found": found,
                        "min": rep.get("min", 3),
                        "message": f"只找到 {found} 条相关记录，数据太少还生成不了像样的报告。"
                                   "先多记几条，或换个时间范围 / 资产类型再试。",
                    }))
                else:
                    await queue.put(("report", rep))
            except Exception as e:  # surface, don't crash the stream
                await queue.put(("error", {"message": str(e)[:300]}))
            finally:
                await queue.put(("__done__", None))

        # DURABLE: detach the runner + hold a strong ref. We do NOT cancel it when
        # this generator exits (client disconnect = popup closed) — it finishes
        # server-side and persists the report itself, so closing the reka popup
        # mid-generation no longer aborts it; the report shows up in the list.
        task = asyncio.create_task(runner())
        _BG_GEN.add(task)
        task.add_done_callback(_BG_GEN.discard)
        while True:
            evt, payload = await queue.get()
            if evt == "__done__":
                break
            yield sse_event(evt, payload)
        yield sse_event("done", {})

    return StreamingResponse(
        with_heartbeats(stream()),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


class RerenderRequest(BaseModel):
    palette: str | None = None
    surface: str | None = None


@router.post("/reports/{report_id}/rerender")
async def rerender_report(
    report_id: str,
    req: RerenderRequest = RerenderRequest(),
    user_id: str = Depends(get_current_user_id),
):
    """换装 (§6.7): re-render the same content_md with a fresh look — bumps the
    seed to the next palette by default, or pins an explicit palette/surface.
    No re-query, no LLM; just substance → new presentation."""
    from agents.report_render import render_report

    try:
        rid = uuid.UUID(report_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid report id")
    async with AsyncSessionLocal() as db:
        r = (await db.execute(
            select(Report).where(Report.id == rid, Report.user_id == user_id)
        )).scalar_one_or_none()
        if r is None:
            raise HTTPException(status_code=404, detail="report not found")
        old_spec = dict(r.spec_json or {})
        # No explicit palette → bump seed so the deterministic palette advances.
        new_seed = None if req.palette else int(old_spec.get("seed") or 0) + 1
        rendered = render_report(
            r.content_md, seed=new_seed, palette=req.palette, surface=req.surface,
            pet_gene=r.pet_gene,  # §6.6.1: re-render keeps the report's snapshotted REKA
        )
        new_html = rendered["html"]
        # §6.6.2: 换装 keeps the AI image (stored once, never re-generated/re-billed) —
        # lift the whole Eureka Moment section out of the old html and re-insert it.
        import re as _re
        _sec = _re.search(r'<section class="r-moment.*?</section>', r.html or "", _re.DOTALL)
        if _sec:
            from agents.report_pipeline import insert_report_image
            new_html = insert_report_image(new_html, _sec.group(0))
        r.html = new_html
        r.spec_json = {
            **old_spec,
            "surface": rendered["surface"],
            "palette": rendered["palette"],
            "seed": rendered["seed"],
        }
        await db.commit()
        await db.refresh(r)
        payload = _full(r)
    return {"ok": True, "report": payload}


# ── §14.6 晨间简报 (handoff Phase 3) ──────────────────────────────────────────
# NOTE: literal path, declared in this router BEFORE /reports/{report_id} could
# shadow it — FastAPI matches in declaration order and this route's path
# (/briefing/today) doesn't collide with the /reports/* tree anyway.
@router.get("/briefing/today")
async def briefing_today(user_id: str = Depends(get_current_user_id)):
    """Today's morning briefing — generated on FIRST call of the (Beijing) day
    (deterministic data + template greeting, zero LLM → milliseconds), then the
    same row on every later call. Also lands in the report container (回看)."""
    from agents.morning_briefing import generate_today
    return {"ok": True, "report": await generate_today(user_id)}


# ── §6.13 / handoff Phase 1: 报告 → 待办 ──────────────────────────────────────
async def _report_of(report_id: str, user_id: str) -> Report:
    try:
        rid = uuid.UUID(report_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid report id")
    async with AsyncSessionLocal() as db:
        r = (await db.execute(
            select(Report).where(Report.id == rid, Report.user_id == user_id)
        )).scalar_one_or_none()
    if r is None:
        raise HTTPException(status_code=404, detail="report not found")
    return r


async def _acted_titles(report_id: uuid.UUID, user_id: str) -> dict[str, str]:
    """Todos already created from this report → {content: asset_id} (dedupe)."""
    from db.models import Asset
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(Asset).where(Asset.user_id == user_id,
                                Asset.source_report_id == report_id)
        )).scalars().all()
    return {str((a.payload or {}).get("content") or ""): str(a.id) for a in rows}


@router.get("/reports/{report_id}/actions")
async def report_actions(report_id: str, user_id: str = Depends(get_current_user_id)):
    """The report's suggested actions + which were already turned into todos.
    The viewer's native「✦ 接下来」bar renders from this."""
    r = await _report_of(report_id, user_id)
    acted = await _acted_titles(r.id, user_id)
    actions = [
        {**a, "created": a.get("title") in acted, "asset_id": acted.get(a.get("title"))}
        for a in (r.suggested_actions or []) if isinstance(a, dict) and a.get("title")
    ]
    return {"ok": True, "actions": actions}


class CreateActionRequest(BaseModel):
    title: str


@router.post("/reports/{report_id}/actions")
async def create_report_action(
    report_id: str,
    req: CreateActionRequest,
    user_id: str = Depends(get_current_user_id),
):
    """One-tap「+ 待办」: create a todo from a suggested action, with provenance
    (§6.13): `assets.source_report_id` + payload source_report_title so the todo
    detail shows「来自报告《X》」. Idempotent — an existing todo for the same
    (report, title) is returned instead of duplicated."""
    title = (req.title or "").strip()
    if not title:
        raise HTTPException(status_code=400, detail="title is required")
    r = await _report_of(report_id, user_id)
    acted = await _acted_titles(r.id, user_id)
    if title in acted:
        return {"ok": True, "asset_id": acted[title], "created": False}

    from mcp_server.tools import create_todo
    res = await create_todo(content=title, user_id=user_id)
    if not res.get("ok"):
        raise HTTPException(status_code=502, detail=res.get("error") or "create failed")
    aid = res.get("asset_id")

    # Provenance — column for dedupe/queries, payload for display (detail sheet).
    from db.models import Asset
    async with AsyncSessionLocal() as db:
        a = (await db.execute(
            select(Asset).where(Asset.id == uuid.UUID(aid), Asset.user_id == user_id)
        )).scalar_one_or_none()
        if a is not None:
            a.source_report_id = r.id
            a.payload = {**(a.payload or {}),
                         "source_report_id": str(r.id),
                         "source_report_title": r.title}
            await db.commit()
    return {"ok": True, "asset_id": aid, "created": True}


@router.delete("/reports/{report_id}")
async def delete_report(report_id: str, user_id: str = Depends(get_current_user_id)):
    try:
        rid = uuid.UUID(report_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid report id")
    async with AsyncSessionLocal() as db:
        r = (await db.execute(
            select(Report).where(Report.id == rid, Report.user_id == user_id)
        )).scalar_one_or_none()
        if r is not None:
            await db.delete(r)
            await db.commit()
    return {"ok": True}
