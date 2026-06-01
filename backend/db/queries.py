"""
Asset field index helpers.

- index_asset_fields: called after every asset creation to populate the
  inverted index used by structured queries.
- query_assets_structured: SQL-direct filter by queryable fields (no LLM).
  Filters by skill name via user_skill_id join — no more reliance on
  payload.asset_type (that field is gone in the Phase B model).
"""
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from .models import Asset, AssetField, UserSkill, GlobalSkill
from datetime import datetime
from decimal import Decimal
from typing import Optional
import uuid


# ── Field type detection ───────────────────────────────────────────────────────

def _classify_value(v):
    """Return (value_text, value_number, value_date) tuple for a raw value."""
    if v is None:
        return None, None, None
    if isinstance(v, bool):
        return str(v).lower(), None, None
    if isinstance(v, (int, float, Decimal)):
        return None, Decimal(str(v)), None
    if isinstance(v, datetime):
        return None, None, v
    s = str(v)
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            return None, None, datetime.strptime(s, fmt)
        except ValueError:
            continue
    try:
        return None, Decimal(s), None
    except Exception:
        return s, None, None


# ── Write path ─────────────────────────────────────────────────────────────────

async def index_asset_fields(
    db: AsyncSession,
    asset_id: uuid.UUID,
    user_id: str,
    user_skill_id: uuid.UUID,
    payload: dict,
):
    """
    After creating an asset, extract queryable fields (defined in user_skills)
    and write them to asset_fields for fast structured queries.
    """
    result = await db.execute(
        select(UserSkill).where(UserSkill.id == user_skill_id)
    )
    user_skill = result.scalar_one_or_none()
    if not user_skill or not user_skill.queryable_fields:
        return

    queryable = {f["field"] for f in user_skill.queryable_fields}

    rows = []
    for field, raw_val in payload.items():
        if field not in queryable:
            continue
        vt, vn, vd = _classify_value(raw_val)
        rows.append(AssetField(
            asset_id=asset_id,
            user_id=user_id,
            field_name=field,
            value_text=vt,
            value_number=vn,
            value_date=vd,
        ))

    if rows:
        db.add_all(rows)


# ── Read path ──────────────────────────────────────────────────────────────────

async def query_assets_structured(
    db: AsyncSession,
    user_id: str,
    user_skill_name: Optional[str] = None,
    filters: Optional[list] = None,
    limit: int = 50,
) -> list:
    """
    Filter assets by indexed fields. Returns newest-first.

    filters: [
      {"field": "amount",   "op": "eq" | "gt" | "lt" | "gte" | "lte", "value": 150},
      {"field": "merchant", "op": "eq",  "value": "麦当劳"},
      {"field": "due_date", "op": "lte", "value": "2026-05-31"},
    ]

    No LLM — pure SQL. Skill is filtered via user_skill_id → global_skills.name
    join (replaces the old payload.asset_type filter).
    """
    filters = filters or []

    stmt = (
        select(Asset, GlobalSkill.name.label("skill_name"))
        .join(UserSkill, Asset.user_skill_id == UserSkill.id)
        .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
        .where(Asset.user_id == user_id)
    )

    if user_skill_name:
        stmt = stmt.where(GlobalSkill.name == user_skill_name)

    for f in filters:
        field = f["field"]
        op    = f["op"]
        val   = f["value"]
        vt, vn, vd = _classify_value(val)

        if vn is not None:
            col, cval = AssetField.value_number, vn
        elif vd is not None:
            col, cval = AssetField.value_date, vd
        else:
            col, cval = AssetField.value_text, vt

        op_map = {
            "eq":  col == cval,
            "gt":  col >  cval,
            "gte": col >= cval,
            "lt":  col <  cval,
            "lte": col <= cval,
        }
        cond = op_map.get(op, col == cval)

        sub = select(AssetField.asset_id).where(
            and_(
                AssetField.user_id    == user_id,
                AssetField.field_name == field,
                cond,
            )
        )
        stmt = stmt.where(Asset.id.in_(sub))

    stmt = stmt.order_by(Asset.created_at.desc()).limit(limit)
    result = await db.execute(stmt)
    rows = result.all()

    return [
        {
            "id":                   str(a.id),
            "skill_name":           skill_name,
            "payload":              a.payload,
            "session_id":           str(a.session_id) if a.session_id else None,
            "source_transcript_id": str(a.source_transcript_id) if a.source_transcript_id else None,
            "created_at":           a.created_at.isoformat(),
        }
        for a, skill_name in rows
    ]
