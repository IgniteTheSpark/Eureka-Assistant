import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from sqlalchemy import text

from app.auth.api import router as auth_router
from app.db.session import AsyncSessionFactory
from app.domains.assets.api import router as assets_router
from app.domains.notifications.api import router as notification_router
from app.domains.notifications.outbox import run_outbox_dispatcher
from app.domains.notifications.subscribers import SubscriberRegistry


@asynccontextmanager
async def lifespan(application: FastAPI):
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


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "theme-v2"}


@app.get("/ready")
async def ready() -> dict[str, str]:
    try:
        async with AsyncSessionFactory() as session:
            await session.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(status_code=503, detail="database unavailable") from exc
    return {"status": "ready"}
