from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.db.session import get_session
from app.domains.devices import service
from app.domains.devices.schemas import (
    BindRequest,
    BindingInfoRequest,
    BindingInfoResponse,
    BindingListResponse,
    BindResponse,
    UnbindRequest,
    UnbindResponse,
)


router = APIRouter(prefix="/api", tags=["devices"])


def _bad_request(exc: ValueError) -> HTTPException:
    return HTTPException(status_code=400, detail=str(exc))


@router.post("/cards/binding-info", response_model=BindingInfoResponse)
async def binding_info(
    command: BindingInfoRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        return await service.binding_info(session, user_id, command.card_sn)
    except ValueError as exc:
        raise _bad_request(exc) from exc


@router.post("/cards/bindings", response_model=BindResponse)
async def bind_card(
    command: BindRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        result = await service.bind_card(session, user_id, command)
    except ValueError as exc:
        raise _bad_request(exc) from exc
    except service.CardBoundByOther as exc:
        raise HTTPException(
            status_code=409,
            detail="card already bound by another user",
        ) from exc
    except IntegrityError as exc:
        await session.rollback()
        raise HTTPException(
            status_code=409,
            detail="card already bound by another user",
        ) from exc
    return {
        "ok": True,
        "action": result.action,
        "binding": service.public_binding(result.binding, result.card),
    }


@router.get("/cards/bindings", response_model=BindingListResponse)
async def list_bindings(
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    rows = await service.list_bindings(session, user_id)
    return {
        "ok": True,
        "bindings": [
            service.public_binding(binding, card) for binding, card in rows
        ],
    }


@router.post("/cards/{binding_id}/unbind", response_model=UnbindResponse)
async def unbind_card(
    binding_id: str,
    command: UnbindRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        UUID(binding_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="invalid binding id") from exc
    result = await service.unbind_card(session, user_id, binding_id)
    if result is None:
        raise HTTPException(status_code=404, detail="binding not found")
    return {
        "ok": True,
        "delete_data": command.delete_data,
        "binding": service.public_binding(result.binding, result.card),
    }
