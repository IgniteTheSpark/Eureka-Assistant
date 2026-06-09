"""
GET    /api/contacts        — list contacts
GET    /api/contacts/{id}   — single contact
POST   /api/contacts        — manual create (used by frontend SkillCreateForm)
PUT    /api/contacts/{id}   — partial update
DELETE /api/contacts/{id}   — remove

The contacts table is the "真身" for contact data (per Phase B v1.4 §三). The
asset-form contact (user_skill_name="contact") is only the timeline-reference
shape — its payload carries a contact_id pointing back here.

Manual creation via the frontend SkillCreateForm posts here, not /api/assets,
so tool_query_contact and other agent queries find the data in the right
table.
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import select
from typing import List, Optional

from core.auth import get_current_user_id
from core.contacts_meta import clean_socials, notes_to_list, append_notes
from db.models import Contact
from db.database import AsyncSessionLocal
from typing import Dict
import uuid

router = APIRouter()


class ContactCreateRequest(BaseModel):
    name:    str
    phone:   Optional[str] = None
    company: Optional[str] = None
    title:   Optional[str] = None
    email:   Optional[str] = None
    notes:   Optional[List[str]] = None      # md annotation lines
    socials: Optional[Dict[str, str]] = None  # {platform_key: handle}, fixed set


class ContactUpdateRequest(BaseModel):
    name:    Optional[str] = None
    phone:   Optional[str] = None
    company: Optional[str] = None
    title:   Optional[str] = None
    email:   Optional[str] = None
    notes:   Optional[List[str]] = None        # full replace (form manages the set)
    notes_append: Optional[List[str]] = None   # append-only (never wipes existing)
    socials: Optional[Dict[str, str]] = None   # full replace, supported-only


@router.get("/contacts")
async def list_contacts(
    q: Optional[str] = Query(None, description="Name search"),
    limit: int = Query(50, le=200),
    user_id: str = Depends(get_current_user_id),
):
    async with AsyncSessionLocal() as db:
        stmt = select(Contact).where(Contact.user_id == user_id)
        if q:
            stmt = stmt.where(Contact.name.ilike(f"%{q}%"))
        stmt = stmt.order_by(Contact.created_at.desc()).limit(limit)
        result = await db.execute(stmt)
        contacts = result.scalars().all()

    return {
        "ok": True,
        "contacts": [
            {
                "id": str(c.id),
                "name": c.name,
                "phone": c.phone,
                "company": c.company,
                "title": c.title,
                "email": c.email,
                "notes": notes_to_list(c.notes),
                "socials": clean_socials(c.socials),
                "created_at": c.created_at.isoformat(),
            }
            for c in contacts
        ],
    }


@router.get("/contacts/{contact_id}")
async def get_contact(contact_id: str, user_id: str = Depends(get_current_user_id)):
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Contact).where(
                Contact.id == uuid.UUID(contact_id),
                Contact.user_id == user_id,
            )
        )
        c = result.scalar_one_or_none()
    if not c:
        return {"ok": False, "error": "Not found"}
    return {
        "ok": True,
        "contact": _serialize(c),
    }


@router.post("/contacts")
async def create_contact(req: ContactCreateRequest, user_id: str = Depends(get_current_user_id)):
    """Manual create — used by frontend SkillCreateForm (skill=contact route)."""
    if not req.name or not req.name.strip():
        raise HTTPException(status_code=400, detail="name required")
    async with AsyncSessionLocal() as db:
        c = Contact(
            user_id=user_id,
            name=req.name.strip(),
            phone=req.phone,
            company=req.company,
            title=req.title,
            email=req.email,
            notes=notes_to_list(req.notes),
            socials=clean_socials(req.socials),
        )
        db.add(c)
        await db.commit()
        await db.refresh(c)
    return {"ok": True, "contact": _serialize(c), "contact_id": str(c.id)}


@router.put("/contacts/{contact_id}")
async def update_contact(contact_id: str, req: ContactUpdateRequest, user_id: str = Depends(get_current_user_id)):
    try:
        cid = uuid.UUID(contact_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid contact id")
    async with AsyncSessionLocal() as db:
        c = (await db.execute(
            select(Contact).where(Contact.id == cid, Contact.user_id == user_id)
        )).scalar_one_or_none()
        if not c:
            raise HTTPException(status_code=404, detail="contact not found")
        # Only apply fields that were sent (None = leave as-is)
        for field in ("name", "phone", "company", "title", "email"):
            v = getattr(req, field)
            if v is not None:
                setattr(c, field, v)
        if req.notes is not None:                 # full replace (form-managed set)
            c.notes = notes_to_list(req.notes)
        if req.notes_append:                      # append-only, never wipes
            c.notes = append_notes(c.notes, req.notes_append)
        if req.socials is not None:               # full replace, supported-only
            c.socials = clean_socials(req.socials)
        await db.commit()
        await db.refresh(c)
    return {"ok": True, "contact": _serialize(c)}


@router.delete("/contacts/{contact_id}")
async def delete_contact(contact_id: str, user_id: str = Depends(get_current_user_id)):
    try:
        cid = uuid.UUID(contact_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid contact id")
    async with AsyncSessionLocal() as db:
        c = (await db.execute(
            select(Contact).where(Contact.id == cid, Contact.user_id == user_id)
        )).scalar_one_or_none()
        if not c:
            raise HTTPException(status_code=404, detail="contact not found")
        await db.delete(c)
        await db.commit()
    return {"ok": True, "deleted_contact_id": contact_id}


def _serialize(c: Contact) -> dict:
    return {
        "id": str(c.id),
        "name": c.name,
        "phone": c.phone,
        "company": c.company,
        "title": c.title,
        "email": c.email,
        "notes": notes_to_list(c.notes),
        "socials": clean_socials(c.socials),
        "created_at": c.created_at.isoformat(),
    }
