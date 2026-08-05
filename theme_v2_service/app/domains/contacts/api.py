from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.db.session import get_session
from app.domains.contacts import service
from app.domains.contacts.schemas import ContactCreate, ContactRead, ContactUpdate


router = APIRouter(prefix="/api/contacts", tags=["contacts"])


@router.post("", response_model=ContactRead)
async def create_contact(
    command: ContactCreate,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    return await service.create_contact(session, user_id, command)


@router.get("")
async def list_contacts(
    name_query: str = "",
    limit: int = Query(default=50, ge=1, le=100),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    contacts = await service.list_contacts(
        session,
        user_id,
        name_query=name_query,
        limit=limit,
    )
    return {"contacts": [ContactRead.model_validate(item).model_dump(mode="json") for item in contacts]}


@router.get("/{contact_id}", response_model=ContactRead)
async def get_contact(
    contact_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    contact = await service.get_contact(session, user_id, contact_id)
    if contact is None:
        raise HTTPException(status_code=404, detail="not found")
    return contact


@router.patch("/{contact_id}", response_model=ContactRead)
async def update_contact(
    contact_id: str,
    command: ContactUpdate,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    contact = await service.update_contact(session, user_id, contact_id, command)
    if contact is None:
        raise HTTPException(status_code=404, detail="not found")
    return contact


@router.delete("/{contact_id}")
async def delete_contact(
    contact_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    if await service.delete_contact(session, user_id, contact_id) is None:
        raise HTTPException(status_code=404, detail="not found")
    return {"ok": True}
