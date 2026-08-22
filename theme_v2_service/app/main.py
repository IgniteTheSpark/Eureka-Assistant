import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Response
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from app.auth.api import router as auth_router
from app.config import get_settings
from app.db.session import AsyncSessionFactory
from app.domains.assets.api import router as assets_router
from app.domains.asr.api import router as asr_router
from app.domains.capture.api import router as capture_router
from app.domains.contacts.api import router as contacts_router
from app.domains.devices.api import router as devices_router
from app.domains.notifications.api import router as notification_router
from app.domains.notifications.outbox import run_outbox_dispatcher
from app.domains.notifications.subscribers import SubscriberRegistry
from app.domains.reka.api import router as reka_router
from app.domains.reports.api_runs import router as report_runs_router
from app.domains.reports.api_reports import router as reports_router
from app.domains.reports.templates import get_template_registry
from app.domains.sessions.api import router as sessions_router
from app.domains.sessions.api_chat import router as session_chat_router
from app.domains.sessions.api_pending_actions import router as pending_actions_router
from app.domains.triggers.api import router as trigger_router
from app.domains.timeline.api import router as timeline_router
from app.internal_mcp.runtime import get_internal_mcp_runtime
from app.observability import metrics


@asynccontextmanager
async def lifespan(application: FastAPI):
    application.state.report_template_registry = get_template_registry()
    settings = get_settings()
    internal_mcp_runtime = get_internal_mcp_runtime()
    if settings.chat_agent_enabled or settings.capture_agent_enabled:
        await internal_mcp_runtime.start()
    registry = SubscriberRegistry()
    dispatcher_task = asyncio.create_task(
        run_outbox_dispatcher(AsyncSessionFactory, registry)
    )
    application.state.notification_subscribers = registry
    application.state.notification_dispatcher_task = dispatcher_task
    try:
        yield
    finally:
        await internal_mcp_runtime.close()
        dispatcher_task.cancel()
        try:
            await dispatcher_task
        except asyncio.CancelledError:
            pass


app = FastAPI(
    title="Eureka Theme V2 API",
    version="2.0.0",
    lifespan=lifespan,
)
app.include_router(auth_router)
app.include_router(assets_router)
app.include_router(asr_router)
app.include_router(capture_router)
app.include_router(contacts_router)
app.include_router(devices_router)
app.include_router(notification_router)
app.include_router(reka_router)
app.include_router(trigger_router)
app.include_router(report_runs_router)
app.include_router(reports_router)
app.include_router(timeline_router)
app.include_router(sessions_router)
app.include_router(session_chat_router)
app.include_router(pending_actions_router)
app.mount("/static", StaticFiles(directory="app/static"), name="static")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "theme-v2"}


@app.get("/ready")
async def ready() -> dict[str, str]:
    settings = get_settings()
    readiness_errors = settings.runtime_readiness_errors()
    if readiness_errors:
        raise HTTPException(status_code=503, detail=readiness_errors)
    if settings.chat_agent_enabled or settings.capture_agent_enabled:
        contract_errors = get_internal_mcp_runtime().contract_errors
        if contract_errors:
            raise HTTPException(status_code=503, detail=list(contract_errors))
    try:
        async with AsyncSessionFactory() as session:
            await session.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(status_code=503, detail="database unavailable") from exc
    return {"status": "ready"}


@app.get("/metrics", include_in_schema=False)
async def prometheus_metrics() -> Response:
    return Response(
        metrics.render_prometheus(),
        media_type="text/plain; version=0.0.4",
    )
