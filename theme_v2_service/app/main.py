import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from app.auth.api import router as auth_router
from app.config import get_settings
from app.db.session import AsyncSessionFactory
from app.domains.assets.api import router as assets_router
from app.domains.notifications.api import router as notification_router
from app.domains.notifications.outbox import run_outbox_dispatcher
from app.domains.notifications.subscribers import SubscriberRegistry
from app.domains.reports.api_runs import router as report_runs_router
from app.domains.reports.api_reports import router as reports_router
from app.domains.reports.templates import get_template_registry
from app.domains.triggers.api import router as trigger_router


@asynccontextmanager
async def lifespan(application: FastAPI):
    application.state.report_template_registry = get_template_registry()
    registry = SubscriberRegistry()
    dispatcher_task = asyncio.create_task(
        run_outbox_dispatcher(AsyncSessionFactory, registry)
    )
    application.state.notification_subscribers = registry
    application.state.notification_dispatcher_task = dispatcher_task
    try:
        yield
    finally:
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
app.include_router(notification_router)
app.include_router(trigger_router)
app.include_router(report_runs_router)
app.include_router(reports_router)
app.mount("/static", StaticFiles(directory="app/static"), name="static")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "theme-v2"}


@app.get("/ready")
async def ready() -> dict[str, str]:
    readiness_errors = get_settings().runtime_readiness_errors()
    if readiness_errors:
        raise HTTPException(status_code=503, detail=readiness_errors)
    try:
        async with AsyncSessionFactory() as session:
            await session.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(status_code=503, detail="database unavailable") from exc
    return {"status": "ready"}
