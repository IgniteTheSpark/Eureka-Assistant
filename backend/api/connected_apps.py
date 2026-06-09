"""
/api/connectors + /api/connected-apps — Connected Apps (§1.7.1 / §3.14).

  GET    /api/connectors            — catalog (no secrets; just field decls)
  GET    /api/connected-apps        — this user's connections (NEVER creds)
  POST   /api/connected-apps        — connect: validate → probe → encrypt → upsert
  PATCH  /api/connected-apps/{id}   — rename / update creds (write-only)
  POST   /api/connected-apps/{id}/test — re-probe → status
  DELETE /api/connected-apps/{id}   — disconnect (delete row + drop creds)

**Credentials are write-only**: they enter via POST/PATCH only and NEVER appear
in any GET response, error, or log. Stored Fernet-encrypted (core.crypto).
"""
import asyncio
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select

from agents.connectors import (
    AUTH_TYPES,
    CONNECTOR_CATALOG,
    build_connection_params,
    get_connector,
    public_catalog,
    validate_credentials,
)
from core.auth import get_current_user_id
from core.crypto import decrypt_credentials, encrypt_credentials
from db.database import AsyncSessionLocal
from db.models import ConnectedApp

router = APIRouter()


def _public(ca: ConnectedApp) -> dict:
    """Connection row for the client — **never** includes credentials."""
    return {
        "id": str(ca.id),
        "connector_id": ca.connector_id,
        "display_name": ca.display_name,
        "auth_type": ca.auth_type,
        "status": ca.status,
        "last_used_at": ca.last_used_at.isoformat() if ca.last_used_at else None,
    }


async def _probe(connector_id: str, creds: dict) -> str:
    """Best-effort live connection check → 'connected' | 'error'. Guarded by a
    timeout so a bad/unreachable URL can't hang the request. If the toolset
    can't be live-probed (ADK API mismatch), assume connected — the real
    failure (if any) surfaces at task-run time via the external_ref status loop."""
    from google.adk.tools.mcp_tool.mcp_toolset import MCPToolset
    try:
        conn = build_connection_params(connector_id, creds)
    except ValueError:
        return "error"
    ts = MCPToolset(connection_params=conn)
    try:
        await asyncio.wait_for(ts.get_tools(), timeout=8)
        return "connected"
    except TypeError:
        return "connected"  # get_tools needs a context we don't have → can't live-probe
    except Exception:
        return "error"
    finally:
        try:
            await ts.close()
        except Exception:
            pass


# ── Catalog (no auth needed — pure static catalog, no secrets) ───────────────
@router.get("/connectors")
async def list_connectors():
    return {"ok": True, "connectors": public_catalog()}


# ── Per-user connections ─────────────────────────────────────────────────────
@router.get("/connected-apps")
async def list_connected_apps(user_id: str = Depends(get_current_user_id)):
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(ConnectedApp)
            .where(ConnectedApp.user_id == user_id)
            .order_by(ConnectedApp.created_at.desc())
        )).scalars().all()
    return {"ok": True, "connected": [_public(r) for r in rows]}


class ConnectRequest(BaseModel):
    connector_id: str
    credentials: dict
    display_name: str | None = None


@router.post("/connected-apps")
async def connect_app(req: ConnectRequest, user_id: str = Depends(get_current_user_id)):
    spec = get_connector(req.connector_id)
    if not spec:
        raise HTTPException(status_code=400, detail=f"unknown connector: {req.connector_id}")
    err = validate_credentials(req.connector_id, req.credentials)
    if err:
        raise HTTPException(status_code=400, detail=err)

    status = await _probe(req.connector_id, req.credentials)
    enc = encrypt_credentials(req.credentials)
    name = (req.display_name or spec["name"]).strip()[:100]

    async with AsyncSessionLocal() as db:
        existing = (await db.execute(
            select(ConnectedApp).where(
                ConnectedApp.user_id == user_id,
                ConnectedApp.connector_id == req.connector_id,
            )
        )).scalar_one_or_none()
        if existing is not None:
            existing.credentials_enc = enc
            existing.display_name = name
            existing.auth_type = spec["auth_type"]
            existing.status = status
            ca = existing
        else:
            ca = ConnectedApp(
                user_id=user_id,
                connector_id=req.connector_id,
                display_name=name,
                auth_type=spec["auth_type"],
                credentials_enc=enc,
                status=status,
            )
            db.add(ca)
        await db.commit()
        await db.refresh(ca)
        out = _public(ca)
    return {"ok": True, "connected": out}


class PatchRequest(BaseModel):
    display_name: str | None = None
    credentials: dict | None = None


@router.patch("/connected-apps/{app_id}")
async def patch_app(app_id: str, req: PatchRequest, user_id: str = Depends(get_current_user_id)):
    try:
        aid = uuid.UUID(app_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid id")
    async with AsyncSessionLocal() as db:
        ca = (await db.execute(
            select(ConnectedApp).where(ConnectedApp.id == aid, ConnectedApp.user_id == user_id)
        )).scalar_one_or_none()
        if ca is None:
            raise HTTPException(status_code=404, detail="not found")
        if req.display_name is not None:
            ca.display_name = req.display_name.strip()[:100]
        if req.credentials is not None:
            err = validate_credentials(ca.connector_id, req.credentials)
            if err:
                raise HTTPException(status_code=400, detail=err)
            ca.status = await _probe(ca.connector_id, req.credentials)
            ca.credentials_enc = encrypt_credentials(req.credentials)
        await db.commit()
        await db.refresh(ca)
        out = _public(ca)
    return {"ok": True, "connected": out}


@router.post("/connected-apps/{app_id}/test")
async def test_app(app_id: str, user_id: str = Depends(get_current_user_id)):
    try:
        aid = uuid.UUID(app_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid id")
    async with AsyncSessionLocal() as db:
        ca = (await db.execute(
            select(ConnectedApp).where(ConnectedApp.id == aid, ConnectedApp.user_id == user_id)
        )).scalar_one_or_none()
        if ca is None:
            raise HTTPException(status_code=404, detail="not found")
        creds = decrypt_credentials(ca.credentials_enc)
        ca.status = await _probe(ca.connector_id, creds) if creds else "error"
        ca.last_used_at = datetime.now(timezone.utc)
        await db.commit()
        status = ca.status
    return {"ok": True, "status": status}


@router.delete("/connected-apps/{app_id}")
async def disconnect_app(app_id: str, user_id: str = Depends(get_current_user_id)):
    try:
        aid = uuid.UUID(app_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid id")
    async with AsyncSessionLocal() as db:
        ca = (await db.execute(
            select(ConnectedApp).where(ConnectedApp.id == aid, ConnectedApp.user_id == user_id)
        )).scalar_one_or_none()
        if ca is not None:
            await db.delete(ca)
            await db.commit()
    return {"ok": True}
