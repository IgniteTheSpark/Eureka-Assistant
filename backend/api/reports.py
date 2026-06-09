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

_GENRES = {"data-report", "idea-synthesis", "proposal", "digest"}


def _meta(r: Report) -> dict:
    """List-row shape — no heavy html/content_md."""
    return {
        "id":          str(r.id),
        "title":       r.title,
        "genre":       r.genre,
        "spec":        r.spec_json or {},
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
    r = Report(
        user_id=user_id,
        title=(req.title or "报告").strip()[:255],
        genre=genre,
        content_md=req.content_md,
        html=req.html,
        spec_json=req.spec or {},
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

        task = asyncio.create_task(runner())
        try:
            while True:
                evt, payload = await queue.get()
                if evt == "__done__":
                    break
                yield sse_event(evt, payload)
            yield sse_event("done", {})
        finally:
            if not task.done():
                task.cancel()

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
