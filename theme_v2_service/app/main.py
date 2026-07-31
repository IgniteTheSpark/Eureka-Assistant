from fastapi import FastAPI, HTTPException
from sqlalchemy import text

from app.db.session import AsyncSessionFactory


app = FastAPI(title="Eureka Theme V2 API", version="2.0.0")


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
