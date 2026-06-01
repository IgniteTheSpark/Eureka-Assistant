"""
Asset CRUD — Phase B Step 5 rewrite.

GET    /api/assets          — list assets (filter by skill name / contains / session)
GET    /api/assets/{id}     — single asset detail (with skill name)
POST   /api/assets          — manually create asset (manual session)
PUT    /api/assets/{id}     — update asset (merges payload + resyncs asset_fields)
DELETE /api/assets/{id}     — delete asset (cascades to asset_fields)

Key changes vs previous version:
- Filter param renamed: `type` → `user_skill_name` (matches new model)
- Skill name resolved via UserSkill→GlobalSkill.name join
  (no more payload.asset_type — that field is gone in Phase B v1.3 schema)
- POST /assets routes through MCP create_asset with the new signature
- New DELETE endpoint
- All responses include user_skill_name + source_input_turn_id
"""
import json
import uuid
from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Optional, Any

from fastapi import APIRouter, Depends, Query, HTTPException
from pydantic import BaseModel
from sqlalchemy import select, delete, Text

from core.auth import get_current_user_id
from db.database import AsyncSessionLocal
from db.models import Asset, AssetField, UserSkill, GlobalSkill
from db.queries import query_assets_structured
from mcp_server.tools import create_asset as mcp_create_asset
from mcp_server.tools import delete_asset as mcp_delete_asset

router = APIRouter()


# ── Request bodies ─────────────────────────────────────────────────────────────

class CreateAssetRequest(BaseModel):
    user_skill_name: str
    payload: dict
    session_id: str = ""
    source_input_turn_id: str = ""


class UpdateAssetRequest(BaseModel):
    payload_patch: dict


# ── asset_fields resync helper ────────────────────────────────────────────────

def _cast_field(value: Any, index_type: str):
    """Cast a value into (text, number, date) based on declared index type."""
    vt = vn = vd = None
    if index_type in ("number", "numeric"):
        try:
            vn = Decimal(str(value))
        except (InvalidOperation, TypeError):
            pass
    elif index_type in ("date", "datetime"):
        try:
            if isinstance(value, str):
                raw = value.strip().replace("Z", "+00:00")
                if len(raw) == 10:
                    raw += "T00:00:00+00:00"
                vd = datetime.fromisoformat(raw)
            elif isinstance(value, datetime):
                vd = value
        except (ValueError, TypeError):
            pass
    else:
        vt = str(value) if value is not None else None
    return vt, vn, vd


async def _resync_asset_fields(db, asset: Asset, new_payload: dict) -> None:
    """Drop + re-insert asset_fields rows for this asset based on its UserSkill.queryable_fields."""
    await db.execute(delete(AssetField).where(AssetField.asset_id == asset.id))

    skill_result = await db.execute(
        select(UserSkill).where(UserSkill.id == asset.user_skill_id)
    )
    skill = skill_result.scalar_one_or_none()
    if not skill or not skill.queryable_fields:
        return

    for qf in skill.queryable_fields:
        field_name = qf.get("field")
        index_type = qf.get("index_type", "text")
        val = new_payload.get(field_name)
        if val is None:
            continue
        vt, vn, vd = _cast_field(val, index_type)
        db.add(AssetField(
            asset_id=asset.id,
            user_id=asset.user_id,
            field_name=field_name,
            value_text=vt,
            value_number=vn,
            value_date=vd,
        ))


# ── Common serializer ─────────────────────────────────────────────────────────

def _serialize_asset(a: Asset, skill_name: str) -> dict:
    return {
        "id":                   str(a.id),
        "user_skill_name":      skill_name,
        "payload":              a.payload,
        "session_id":           str(a.session_id) if a.session_id else None,
        "source_input_turn_id": str(a.source_input_turn_id) if a.source_input_turn_id else None,
        "created_at":           a.created_at.isoformat(),
    }


# ── GET /api/assets ────────────────────────────────────────────────────────────

@router.get("/assets")
async def list_assets(
    user_skill_name: Optional[str] = Query(None, description="Skill name filter (e.g. todo, event)"),
    session_id: Optional[str]      = Query(None, description="Filter by session UUID"),
    field: Optional[str]           = Query(None, description="Field name for structured filter"),
    op: Optional[str]              = Query("eq", description="eq|gt|gte|lt|lte"),
    value: Optional[str]           = Query(None, description="Filter value"),
    contains: Optional[str]        = Query(None, description="Keyword search in payload"),
    limit: int                     = Query(50, le=500),
    user_id: str                   = Depends(get_current_user_id),
):
    """
    Query patterns:
      GET /api/assets?user_skill_name=expense&field=amount&op=eq&value=150
      GET /api/assets?user_skill_name=todo&contains=刘洋
      GET /api/assets?session_id=<uuid>
    """
    # Structured filter path (uses asset_fields inverted index)
    if field and value is not None:
        filters = [{"field": field, "op": op or "eq", "value": value}]
        async with AsyncSessionLocal() as db:
            results = await query_assets_structured(db, user_id, user_skill_name, filters, limit)
        if session_id:
            results = [r for r in results if str(r.get("session_id") or "") == session_id]
        return {"ok": True, "assets": results}

    # Direct query path
    async with AsyncSessionLocal() as db:
        stmt = (
            select(Asset, GlobalSkill.name.label("skill_name"))
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.user_id == user_id)
        )
        if user_skill_name:
            stmt = stmt.where(GlobalSkill.name == user_skill_name)
        if session_id:
            stmt = stmt.where(Asset.session_id == uuid.UUID(session_id))
        if contains:
            stmt = stmt.where(Asset.payload.cast(Text).ilike(f"%{contains}%"))
        stmt = stmt.order_by(Asset.created_at.desc()).limit(limit)
        rows = (await db.execute(stmt)).all()

    return {
        "ok": True,
        "assets": [_serialize_asset(a, sn) for a, sn in rows],
    }


# ── GET /api/assets/{id} ──────────────────────────────────────────────────────

@router.get("/assets/{asset_id}")
async def get_asset(
    asset_id: str,
    user_id: str = Depends(get_current_user_id),
):
    try:
        aid = uuid.UUID(asset_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid asset id")

    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Asset, GlobalSkill.name.label("skill_name"))
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.id == aid, Asset.user_id == user_id)
        )
        row = result.first()

    if not row:
        raise HTTPException(status_code=404, detail="asset not found")

    a, sn = row
    return {"ok": True, "asset": _serialize_asset(a, sn)}


# ── POST /api/assets (manual create) ──────────────────────────────────────────

@router.post("/assets")
async def manual_create_asset(req: CreateAssetRequest):
    """
    Manual asset creation (not via voice flash or chat agent). Used by the
    Asset Detail page's edit / add affordance, or any future bulk-import path.
    """
    return await mcp_create_asset(
        user_skill_name=req.user_skill_name,
        payload=json.dumps(req.payload, ensure_ascii=False),
        session_id=req.session_id,
        source_input_turn_id=req.source_input_turn_id,
    )


# ── PUT /api/assets/{id} ──────────────────────────────────────────────────────

@router.put("/assets/{asset_id}")
async def update_asset(
    asset_id: str,
    req: UpdateAssetRequest,
    user_id: str = Depends(get_current_user_id),
):
    try:
        aid = uuid.UUID(asset_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid asset id")

    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Asset).where(Asset.id == aid, Asset.user_id == user_id)
        )
        asset = result.scalar_one_or_none()
        if not asset:
            raise HTTPException(status_code=404, detail="asset not found")

        new_payload = {**asset.payload, **req.payload_patch}
        asset.payload = new_payload
        await _resync_asset_fields(db, asset, new_payload)
        await db.commit()
        await db.refresh(asset)

        skill_result = await db.execute(
            select(GlobalSkill.name)
            .join(UserSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(UserSkill.id == asset.user_skill_id)
        )
        skill_name = skill_result.scalar_one_or_none() or ""

    return {"ok": True, "asset": _serialize_asset(asset, skill_name)}


# ── DELETE /api/assets/{id} ───────────────────────────────────────────────────

@router.delete("/assets/{asset_id}")
async def delete_asset(asset_id: str):
    """Delete an asset; cascades to asset_fields via FK ON DELETE CASCADE."""
    return await mcp_delete_asset(asset_id)
