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
from sqlalchemy import select, delete, Text, func

from core.auth import get_current_user_id
from core.domains import normalize_domain
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
    domain: str = ""              # §8 life-domain; "" → service falls back to skill prior
    # 「在这天记一笔」: 手动在某天创建 → 把 created_at 锚到那天(否则记录类资产
    # effective_at=created_at 会落到今天)。ISO8601+08:00;"" → 用 now。
    created_at: str = ""


class UpdateAssetRequest(BaseModel):
    payload_patch: dict = {}
    domain: Optional[str] = None  # set to change domain; pass to clear (see model_fields_set)
    period: Optional[str] = None  # §4.5.0a 段纠错; present → set/clear (clears occurred_at)


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
        "domain":               a.domain,
        "period":               a.period or "",
        "occurred_at":          a.occurred_at.isoformat() if a.occurred_at else None,
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
    domain: Optional[str]          = Query(None, description="§8 life-domain filter (e.g. 工作)"),
    created_from: Optional[str]    = Query(None, description="ISO8601 lower bound on created_at (今日页气泡池=今天录入)"),
    created_to: Optional[str]      = Query(None, description="ISO8601 upper bound on created_at"),
    limit: int                     = Query(50, le=500),
    user_id: str                   = Depends(get_current_user_id),
):
    """
    Query patterns:
      GET /api/assets?user_skill_name=expense&field=amount&op=eq&value=150
      GET /api/assets?user_skill_name=todo&contains=刘洋
      GET /api/assets?session_id=<uuid>
      GET /api/assets?domain=工作
    """
    # §8: normalize the domain filter (codex r2) so an illegal/aliased value is
    # treated consistently with create/update (→ None = no filter), not compared
    # raw (which would silently return empty for a bad value).
    domain = normalize_domain(domain)
    # Structured filter path (uses asset_fields inverted index)
    if field and value is not None:
        filters = [{"field": field, "op": op or "eq", "value": value}]
        async with AsyncSessionLocal() as db:
            results = await query_assets_structured(db, user_id, user_skill_name, filters, limit)
        if session_id:
            results = [r for r in results if str(r.get("session_id") or "") == session_id]
        if domain:
            results = [r for r in results if (r.get("domain") or "") == domain]
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
        if domain:
            stmt = stmt.where(Asset.domain == domain)
        if created_from:
            stmt = stmt.where(Asset.created_at >= datetime.fromisoformat(created_from.replace("Z", "+00:00")))
        if created_to:
            stmt = stmt.where(Asset.created_at <= datetime.fromisoformat(created_to.replace("Z", "+00:00")))
        stmt = stmt.order_by(Asset.created_at.desc()).limit(limit)
        rows = (await db.execute(stmt)).all()

    return {
        "ok": True,
        "assets": [_serialize_asset(a, sn) for a, sn in rows],
    }


# ── GET /api/assets/counts ────────────────────────────────────────────────────
# MUST be declared before /assets/{asset_id} or FastAPI routes "counts" → asset_id.

@router.get("/assets/counts")
async def asset_counts(user_id: str = Depends(get_current_user_id)):
    """Per-skill **total** asset counts (all-time) for the 资产库 container tiles.
    A cheap GROUP BY, independent of the limited /assets list — so a container's
    number is its true total, not「最近 N 条里碰巧有几条」。"""
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(GlobalSkill.name, func.count(Asset.id))
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.user_id == user_id)
            .group_by(GlobalSkill.name)
        )).all()
    counts = {name: int(n) for name, n in rows}
    return {"ok": True, "counts": counts, "total": sum(counts.values())}


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
async def manual_create_asset(
    req: CreateAssetRequest,
    user_id: str = Depends(get_current_user_id),
):
    """
    Manual asset creation (not via voice flash or chat agent). Used by the
    Asset Detail page's edit / add affordance, or any future bulk-import path.
    """
    return await mcp_create_asset(
        user_skill_name=req.user_skill_name,
        payload=json.dumps(req.payload, ensure_ascii=False),
        session_id=req.session_id,
        source_input_turn_id=req.source_input_turn_id,
        domain=req.domain,
        user_id=user_id,
        created_at=req.created_at,
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

        if req.payload_patch:
            new_payload = {**asset.payload, **req.payload_patch}
            asset.payload = new_payload
            await _resync_asset_fields(db, asset, new_payload)
        # §8: domain editable from the manual selector. Present in body (even as
        # null) → set/clear; absent → leave unchanged.
        if "domain" in req.model_fields_set:
            asset.domain = normalize_domain(req.domain)
        # §4.5.0a 段纠错:手动选时段 → 设 period + 清 occurred_at(改回模糊时段,
        # 不再是精确钟点);不指定 → 两者都清(回到捕捉时刻兜底落段)。
        if "period" in req.model_fields_set:
            p = (req.period or "").strip()
            asset.period = p if p in {"凌晨", "上午", "中午", "下午", "晚上"} else None
            asset.occurred_at = None
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
async def delete_asset(asset_id: str, user_id: str = Depends(get_current_user_id)):
    """Delete an asset; cascades to asset_fields via FK ON DELETE CASCADE."""
    return await mcp_delete_asset(asset_id, user_id=user_id)
