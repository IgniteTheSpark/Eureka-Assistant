"""
Eureka FastAPI app — Phase B Step 5 + 7 (v1.3).

Wires up 8 routers + lifecycle hooks:
- core.llm.configure_llm_env() at startup (sets OPENROUTER_API_KEY env)
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

# Configure LLM env BEFORE importing routers (which import agents → instantiate models)
from core.llm import configure_llm_env
configure_llm_env()

from agents.mcp_toolset import close_mcp_toolset
from api.chat import router as chat_router
from api.flash import router as flash_router
from api.skills import router as skills_router
from api.input_turns import router as input_turns_router
from api.files import router as files_router
from api.assets import router as assets_router
from api.sessions import router as sessions_router
from api.contacts import router as contacts_router
from api.events import router as events_router       # v1.4
from api.timeline import router as timeline_router    # v1.4.x
from api.tasks import router as tasks_router          # v1.4.x — async MCP tasks
from api.notifications import router as notifications_router  # Phase D M6


@asynccontextmanager
async def lifespan(app: FastAPI):
    """App lifecycle: start the M7 reminder scheduler; shutdown cancels it and
    closes the MCP subprocess."""
    import asyncio
    from core.reminder_scheduler import reminder_loop
    reminder_task = asyncio.create_task(reminder_loop())
    try:
        yield
    finally:
        reminder_task.cancel()
        try:
            await reminder_task
        except asyncio.CancelledError:
            pass
        await close_mcp_toolset()


app = FastAPI(title="Eureka API", version="1.4.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(chat_router,        prefix="/api", tags=["chat"])
app.include_router(flash_router,       prefix="/api", tags=["flash"])
app.include_router(skills_router,      prefix="/api", tags=["skills"])
app.include_router(input_turns_router, prefix="/api", tags=["input-turns"])
app.include_router(files_router,       prefix="/api", tags=["files"])
app.include_router(assets_router,      prefix="/api", tags=["assets"])
app.include_router(sessions_router,    prefix="/api", tags=["sessions"])
app.include_router(contacts_router,    prefix="/api", tags=["contacts"])
app.include_router(events_router,      prefix="/api", tags=["events"])       # v1.4
app.include_router(timeline_router,    prefix="/api", tags=["timeline"])     # v1.4.x
app.include_router(tasks_router,       prefix="/api", tags=["tasks"])        # v1.4.x
app.include_router(notifications_router, prefix="/api", tags=["notifications"])  # Phase D M6


@app.get("/health")
async def health():
    return {"status": "ok", "version": "phase-b-v1.4"}
