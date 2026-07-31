import asyncio
import hashlib
from pathlib import Path
from typing import Protocol

from pydantic import BaseModel, ConfigDict
from sqlalchemy.ext.asyncio import AsyncSession

from app.domains.reports.models import File


class StorageKeyRejected(ValueError):
    pass


class StoredObject(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str
    size_bytes: int
    mime_type: str
    sha256: str


class Storage(Protocol):
    async def put(self, key: str, content: bytes, mime_type: str) -> StoredObject:
        ...

    async def get(self, key: str) -> bytes:
        ...


class LocalStorage:
    def __init__(self, root: Path) -> None:
        self.root = Path(root).resolve()

    def _resolve(self, key: str) -> Path:
        raw = Path(key)
        if not key or raw.is_absolute() or ".." in raw.parts:
            raise StorageKeyRejected("storage key must be relative and contained")
        candidate = (self.root / raw).resolve()
        if not candidate.is_relative_to(self.root):
            raise StorageKeyRejected("storage key escapes media root")
        return candidate

    async def put(self, key: str, content: bytes, mime_type: str) -> StoredObject:
        candidate = self._resolve(key)

        def write() -> None:
            candidate.parent.mkdir(parents=True, exist_ok=True)
            candidate.write_bytes(content)

        await asyncio.to_thread(write)
        return StoredObject(
            key=key,
            size_bytes=len(content),
            mime_type=mime_type,
            sha256=hashlib.sha256(content).hexdigest(),
        )

    async def get(self, key: str) -> bytes:
        candidate = self._resolve(key)
        return await asyncio.to_thread(candidate.read_bytes)


async def persist_owned_file(
    session: AsyncSession,
    *,
    storage: Storage,
    user_id: str,
    purpose: str,
    key: str,
    content: bytes,
    mime_type: str,
) -> File:
    stored = await storage.put(key, content, mime_type)
    file = File(
        user_id=user_id,
        purpose=purpose,
        mime_type=stored.mime_type,
        size_bytes=stored.size_bytes,
        sha256=stored.sha256,
        storage_key=stored.key,
    )
    session.add(file)
    await session.flush()
    return file
