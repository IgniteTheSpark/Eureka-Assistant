from fastapi import FastAPI, HTTPException
from sqlalchemy import text

from app.auth.api import router as auth_router
from app.db.session import AsyncSessionFactory
from app.domains.assets.api import router as assets_router


app = FastAPI(title="Eureka Theme V2 API", version="2.0.0")
app.include_router(auth_router)
app.include_router(assets_router)


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
