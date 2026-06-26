"""
Eureka FastAPI app — Phase B Step 5 + 7 (v1.3).

Wires up 15 routers + lifecycle hooks:
- core.llm.configure_llm_env() at startup (sets DEEPSEEK_API_KEY / OPENROUTER_API_KEY env)
- agents.mcp_toolset.close_mcp_toolset() at shutdown (closes stdio subprocess)

nest_asyncio removed (Phase B Step 7):
Old code called nest_asyncio.apply() at module top to allow nested asyncio
loops — needed because some flows did `asyncio.run()` inside an already-running
loop. The new architecture is async-native end-to-end:
- All API handlers are `async def`
- ADK Runner.run_async is used (the proper streaming async path)
- DB access uses asyncpg AsyncSession everywhere
- MCP toolset runs as a stdio subprocess (no in-process sync→async boundary)
There is no remaining call site that requires loop re-entry.

Dropped from previous version:
- api/query.py     → merged into api/chat.py (unified Assistant via SSE)
- api/flash_audio  → audio upload path deferred per Phase A
- StaticFiles mount for uploads/  → no audio files in demo
- nest_asyncio.apply()  → no longer needed (see above)
"""
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Refuse to boot a prod-like env with dev secrets (codex P1.2), then configure
# LLM env BEFORE importing routers (which import agents → instantiate models).
from config import validate_prod_secrets
validate_prod_secrets()

from core.llm import configure_llm_env
configure_llm_env()

import logging


def _configure_flash_file_logging() -> None:
    flash_logger = logging.getLogger("flash_file")
    flash_logger.setLevel(logging.INFO)
    uvicorn_logger = logging.getLogger("uvicorn.error")
    for handler in uvicorn_logger.handlers:
        if handler not in flash_logger.handlers:
            flash_logger.addHandler(handler)
    flash_logger.propagate = False


_configure_flash_file_logging()

from agents.mcp_toolset import close_mcp_toolset
from api.auth import router as auth_router
from api.auth_baizhi import router as auth_baizhi_router    # §13.1 / B1 百智 OAuth login
from api.chat import router as chat_router
from api.flash import router as flash_router
from api.skills import router as skills_router
from api.input_turns import router as input_turns_router
from api.files import router as files_router
from api.assets import router as assets_router
from api.sessions import router as sessions_router
from api.contacts import router as contacts_router
from api.cards import router as cards_router
from api.nudges import router as nudges_router
from api.offers import router as offers_router       # §14.5a PULL comprehensive offer set
from api.events import router as events_router       # v1.4
from api.timeline import router as timeline_router    # v1.4.x
from api.tasks import router as tasks_router          # v1.4.x — async MCP tasks
from api.notifications import router as notifications_router  # Phase D M6
from api.reports import router as reports_router              # §6 synthesis/report engine
from api.export import router as export_router                # 资产库导出 (md/csv)
from api.connected_apps import router as connected_apps_router  # §1.7.1 Connected Apps
from api.pet import router as pet_router                          # §9 球球 Pet


@asynccontextmanager
async def lifespan(app: FastAPI):
    """App lifecycle: start the M7 reminder scheduler; shutdown cancels it and
    closes the MCP subprocess."""
    import asyncio
    _configure_flash_file_logging()
    from core.reminder_scheduler import reminder_loop
    reminder_task = asyncio.create_task(reminder_loop())
    # §14 主动 REKA heartbeat (Phase 2): rhythm profiles (daily) + 缺口→Type A
    # nudges (~30min ticks, deterministic, zero per-tick LLM).
    from core.companion import companion_loop
    companion_task = asyncio.create_task(companion_loop())
    from core.flash_file_queue import start_flash_file_workers, stop_flash_file_workers
    start_flash_file_workers(concurrency=2)

    # Warm the internal MCP toolset at boot so the FIRST user chat turn doesn't
    # pay the stdio-subprocess spawn (re-imports the backend + connects MySQL,
    # ~9s observed: first turn 13.9s vs ~4.8s warm). Best-effort + backgrounded:
    # a warmup failure or a changed ADK API must never block/slow startup.
    async def _warm_mcp():
        try:
            from agents.mcp_toolset import get_mcp_toolset
            ts = get_mcp_toolset()
            get_tools = getattr(ts, "get_tools", None)
            if get_tools is not None:
                res = get_tools()  # connecting spawns the subprocess + lists tools
                if hasattr(res, "__await__"):
                    await res
        except Exception:
            pass  # no-op on any failure — the lazy path still works per-request

    warm_task = asyncio.create_task(_warm_mcp())
    try:
        yield
    finally:
        reminder_task.cancel()
        companion_task.cancel()
        warm_task.cancel()
        for t in (reminder_task, companion_task, warm_task):
            try:
                await t
            except (asyncio.CancelledError, Exception):
                pass
        await stop_flash_file_workers()
        await close_mcp_toolset()


app = FastAPI(title="Eureka API", version="1.4.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router,        prefix="/api", tags=["auth"])
app.include_router(auth_baizhi_router, prefix="/api", tags=["auth"])    # §13.1 / B1 百智 OAuth
app.include_router(chat_router,        prefix="/api", tags=["chat"])
app.include_router(flash_router,       prefix="/api", tags=["flash"])
app.include_router(skills_router,      prefix="/api", tags=["skills"])
app.include_router(input_turns_router, prefix="/api", tags=["input-turns"])
app.include_router(files_router,       prefix="/api", tags=["files"])
app.include_router(assets_router,      prefix="/api", tags=["assets"])
app.include_router(sessions_router,    prefix="/api", tags=["sessions"])
app.include_router(contacts_router,    prefix="/api", tags=["contacts"])
app.include_router(cards_router,       prefix="/api", tags=["cards"])
app.include_router(events_router,      prefix="/api", tags=["events"])       # v1.4
app.include_router(timeline_router,    prefix="/api", tags=["timeline"])     # v1.4.x
app.include_router(tasks_router,       prefix="/api", tags=["tasks"])        # v1.4.x
app.include_router(notifications_router, prefix="/api", tags=["notifications"])  # Phase D M6
app.include_router(reports_router,      prefix="/api", tags=["reports"])        # §6 synthesis/report engine
app.include_router(export_router,       prefix="/api", tags=["export"])         # 资产库导出 (md/csv)
app.include_router(connected_apps_router, prefix="/api", tags=["connected-apps"])  # §1.7.1 Connected Apps
app.include_router(pet_router,            prefix="/api", tags=["pet"])             # §9 球球 Pet
app.include_router(nudges_router,         prefix="/api", tags=["nudges"])          # §14 主动 REKA (Phase 2)
app.include_router(offers_router,         prefix="/api", tags=["offers"])          # §14.5a PULL comprehensive offer set


@app.get("/health")
async def health():
    return {"status": "ok", "version": "phase-b-v1.4"}
