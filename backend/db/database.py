from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy import create_engine
from contextlib import asynccontextmanager
from pathlib import Path
from urllib.parse import urlparse, parse_qs, urlencode, urlunparse
import ssl, os
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://eureka:eureka@localhost:5432/eureka")

def _strip_query_params(url: str, remove_keys: set) -> str:
    """Remove specific query params from a DB URL (e.g. sslmode, channel_binding)."""
    parsed = urlparse(url)
    params = {k: v for k, v in parse_qs(parsed.query).items() if k not in remove_keys}
    new_query = urlencode({k: v[0] for k, v in params.items()})
    return urlunparse(parsed._replace(query=new_query))

# asyncpg doesn't understand sslmode/channel_binding — strip them and pass ssl via connect_args
_ASYNCPG_URL = _strip_query_params(
    DATABASE_URL.replace("postgresql://", "postgresql+asyncpg://").replace("postgres://", "postgresql+asyncpg://"),
    {"sslmode", "channel_binding"},
)

# Enable SSL only for non-local hosts (cloud Postgres). The local docker
# pgvector image rejects SSL upgrade, so passing an ssl context locally
# breaks all queries with "rejected SSL upgrade".
_parsed = urlparse(_ASYNCPG_URL)
_is_local = (_parsed.hostname or "") in {"localhost", "127.0.0.1", "db"}
if _is_local:
    _connect_args: dict = {}
else:
    _ssl_ctx = ssl.create_default_context()
    _ssl_ctx.check_hostname = False
    _ssl_ctx.verify_mode = ssl.CERT_NONE
    _connect_args = {"ssl": _ssl_ctx}

async_engine = create_async_engine(
    _ASYNCPG_URL,
    echo=False,
    pool_pre_ping=True,
    pool_size=20,
    max_overflow=20,
    connect_args=_connect_args,
)
AsyncSessionLocal = async_sessionmaker(async_engine, expire_on_commit=False)

# Sync engine for Alembic migrations and seed scripts (psycopg2 handles sslmode natively)
sync_engine = create_engine(DATABASE_URL, echo=False)


@asynccontextmanager
async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
