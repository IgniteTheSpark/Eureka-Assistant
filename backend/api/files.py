"""
GET /api/files — list audio files for the 资产库 文件 entry (design §6.3).

File is the 6th type in the Library grid (5 skill types + files). Files are
NOT rendered via SkillCard — they go through a dedicated FileList component
(per design §6.3, the explicit one-exception rule).

GET /api/files/{id} — single file detail

Demo mode: this list is usually empty since we don't actually upload audio
(browser Web Speech transcribes locally; no file). Future: hardware upload
populates files table, this endpoint surfaces them.
"""
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func
from typing import Optional

from core.auth import get_current_user_id
from db.database import AsyncSessionLocal
from db.models import File, InputTurn, Asset

router = APIRouter()


@router.get("/files")
async def list_files(
    source_tag: Optional[str] = Query(None, description="flash | meeting"),
    limit: int = Query(50, le=200),
    user_id: str = Depends(get_current_user_id),
):
    """
    List files, newest first. For each, include input_turn count and derived
    asset count so the FileList component can show 「· N 资产」right inline.
    """
    async with AsyncSessionLocal() as db:
        stmt = select(File).where(File.user_id == user_id)
        if source_tag:
            stmt = stmt.where(File.source_tag == source_tag)
        stmt = stmt.order_by(File.created_at.desc()).limit(limit)
        files = (await db.execute(stmt)).scalars().all()

        results = []
        for f in files:
            # Count input_turns from this file
            tc = await db.execute(
                select(func.count(InputTurn.id)).where(InputTurn.file_id == f.id)
            )
            turn_count = tc.scalar() or 0

            # Count derived assets (via the file's input_turns)
            ac = await db.execute(
                select(func.count(Asset.id))
                .join(InputTurn, Asset.source_input_turn_id == InputTurn.id)
                .where(InputTurn.file_id == f.id)
            )
            asset_count = ac.scalar() or 0

            results.append({
                "id":            str(f.id),
                "storage_url":   f.storage_url,
                "file_type":     f.file_type,
                "duration_sec":  f.duration_sec,
                "source_tag":    f.source_tag,
                "asr_status":    f.asr_status,
                "turn_count":    turn_count,
                "asset_count":   asset_count,
                "created_at":    f.created_at.isoformat(),
            })

    return {"ok": True, "files": results}


@router.get("/files/{file_id}")
async def get_file(
    file_id: str,
    user_id: str = Depends(get_current_user_id),
):
    try:
        fid = uuid.UUID(file_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid file id")

    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(File).where(File.id == fid, File.user_id == user_id)
        )
        f = result.scalar_one_or_none()

    if not f:
        raise HTTPException(status_code=404, detail="file not found")

    return {
        "ok": True,
        "file": {
            "id":            str(f.id),
            "storage_url":   f.storage_url,
            "file_type":     f.file_type,
            "duration_sec":  f.duration_sec,
            "source_tag":    f.source_tag,
            "asr_status":    f.asr_status,
            "created_at":    f.created_at.isoformat(),
        }
    }
