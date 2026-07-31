from pathlib import Path

import pytest

from app.domains.reports.models import File
from app.domains.reports.storage import (
    LocalStorage,
    StorageKeyRejected,
    persist_owned_file,
)


async def test_local_storage_round_trip_and_digest(tmp_path):
    storage = LocalStorage(tmp_path / "media")

    stored = await storage.put("reports/user-1/image.png", b"image", "image/png")

    assert stored.key == "reports/user-1/image.png"
    assert stored.size_bytes == 5
    assert len(stored.sha256) == 64
    assert await storage.get(stored.key) == b"image"


@pytest.mark.parametrize("key", ["../secret", "/absolute/path", "safe/../../escape"])
async def test_local_storage_rejects_path_traversal(tmp_path, key):
    storage = LocalStorage(tmp_path / "media")

    with pytest.raises(StorageKeyRejected):
        await storage.put(key, b"bad", "application/octet-stream")
    with pytest.raises(StorageKeyRejected):
        await storage.get(key)


async def test_owned_file_metadata_is_persisted_with_storage_object(session, tmp_path):
    storage = LocalStorage(tmp_path / "media")

    file = await persist_owned_file(
        session,
        storage=storage,
        user_id="user-1",
        purpose="report_illustration",
        key="reports/user-1/illustration.png",
        content=b"png-bytes",
        mime_type="image/png",
    )
    await session.commit()

    persisted = await session.get(File, file.id)
    assert persisted.user_id == "user-1"
    assert persisted.storage_key == "reports/user-1/illustration.png"
    assert persisted.size_bytes == len(b"png-bytes")
    assert await storage.get(persisted.storage_key) == b"png-bytes"
