from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy import create_engine
from contextlib import asynccontextmanager
from pathlib import Path
import os
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

# MySQL is the relational store (matches the company stack). The vector store
# (Postgres + pgvector) is a separate service added only when embeddings exist.
DATABASE_URL = os.environ.get(
    "DATABASE_URL", "mysql://eureka:eureka@localhost:3306/eureka"
)


def _with_driver(url: str, driver: str) -> str:
    """Normalize mysql[+anydriver]://… → mysql+<driver>://… so the same
    DATABASE_URL drives both the async app engine (aiomysql) and the sync
    engine used by Alembic / seed (pymysql)."""
    if "://" not in url:
        return url
    scheme, rest = url.split("://", 1)
    base = scheme.split("+", 1)[0]  # 'mysql'
    return f"{base}+{driver}://{rest}"


_ASYNC_URL = _with_driver(DATABASE_URL, "aiomysql")
_SYNC_URL = _with_driver(DATABASE_URL, "pymysql")

async_engine = create_async_engine(
    _ASYNC_URL,
    echo=False,
    pool_pre_ping=True,   # drop dead conns (MySQL wait_timeout) instead of erroring
    pool_recycle=1800,    # recycle before MySQL's default 8h idle close
    pool_size=20,
    max_overflow=20,
)
AsyncSessionLocal = async_sessionmaker(async_engine, expire_on_commit=False)

# Sync engine for Alembic migrations and seed scripts.
sync_engine = create_engine(_SYNC_URL, echo=False, pool_pre_ping=True)


@asynccontextmanager
async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
