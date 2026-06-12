"""BLE card binding APIs.

The app owns BLE scan/connect/unbind. The server owns account-card binding
truth: lookup before connect, record after connect, and mark unbound after the
hardware unbind succeeds.
"""
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from core.auth import get_current_user_id
from db.database import AsyncSessionLocal
from db.models import Card, CardBinding

router = APIRouter()


class BindingInfoRequest(BaseModel):
    card_sn: str


class BindRequest(BaseModel):
    card_sn: str
    card_device_uuid: str
    card_mac: Optional[str] = None
    card_mac_from: Optional[str] = None
    card_name: Optional[str] = None
    card_nick: Optional[str] = None
    card_app_uuid: str


class UnbindRequest(BaseModel):
    delete_data: bool = False


def _now():
    return datetime.now(timezone.utc)


def _clean_required(value: str | None, field: str) -> str:
    cleaned = (value or "").strip()
    if not cleaned:
        raise HTTPException(status_code=400, detail=f"{field} required")
    return cleaned


def _clean_optional(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    return cleaned or None


def _public_card(card: Card | None) -> dict | None:
    if card is None:
        return None
    return {
        "card_id": str(card.id),
        "card_sn": card.card_sn,
        "card_device_uuid": card.card_device_uuid,
        "card_mac": card.card_mac,
        "card_mac_from": card.card_mac_from,
        "card_name": card.card_name,
    }


def _public_binding(binding: CardBinding | None, card: Card | None = None) -> dict | None:
    if binding is None:
        return None
    out = {
        "binding_id": str(binding.id),
        "card_id": str(binding.card_id),
        "card_nick": binding.card_nick,
        "card_app_uuid": binding.card_app_uuid,
        "bind_status": binding.bind_status,
        "bind_time": binding.bind_time.isoformat() if binding.bind_time else None,
        "unbind_time": binding.unbind_time.isoformat() if binding.unbind_time else None,
        "created_at": binding.created_at.isoformat() if binding.created_at else None,
        "updated_at": binding.updated_at.isoformat() if binding.updated_at else None,
    }
    if card is not None:
        out.update(_public_card(card) or {})
    return out


def _connect_hint(binding: CardBinding | None, card: Card | None) -> dict | None:
    if binding is None or card is None:
        return None
    return {
        "card_app_uuid": binding.card_app_uuid,
        "card_device_uuid": card.card_device_uuid,
        "card_name": card.card_name,
        "card_mac": card.card_mac,
    }


async def _active_binding(db, card: Card) -> CardBinding | None:
    return (await db.execute(
        select(CardBinding).where(
            CardBinding.active_card_id == card.id,
            CardBinding.bind_status == "bound",
        )
    )).scalar_one_or_none()


async def _latest_user_binding(db, user_id: str, card: Card) -> CardBinding | None:
    return (await db.execute(
        select(CardBinding)
        .where(CardBinding.user_id == user_id, CardBinding.card_id == card.id)
        .order_by(CardBinding.bind_time.desc(), CardBinding.created_at.desc())
        .limit(1)
    )).scalar_one_or_none()


@router.post("/cards/binding-info")
async def binding_info(
    req: BindingInfoRequest,
    user_id: str = Depends(get_current_user_id),
):
    card_sn = _clean_required(req.card_sn, "card_sn")
    async with AsyncSessionLocal() as db:
        card = (await db.execute(
            select(Card).where(Card.card_sn == card_sn)
        )).scalar_one_or_none()
        if card is None:
            return {
                "ok": True,
                "card_sn": card_sn,
                "bindable": True,
                "state": "never_bound_by_me",
                "current_binding": None,
                "latest_user_binding": None,
                "connect_hint": None,
            }

        active = await _active_binding(db, card)
        latest = await _latest_user_binding(db, user_id, card)

    if active is not None and active.user_id != user_id:
        return {
            "ok": True,
            "card_sn": card_sn,
            "bindable": False,
            "state": "bound_by_other",
            "current_binding": None,
            "latest_user_binding": _public_binding(latest, card),
            "connect_hint": None,
        }

    if active is not None:
        return {
            "ok": True,
            "card_sn": card_sn,
            "bindable": True,
            "state": "bound_by_me",
            "current_binding": _public_binding(active, card),
            "latest_user_binding": _public_binding(latest, card),
            "connect_hint": _connect_hint(active, card),
        }

    if latest is not None:
        return {
            "ok": True,
            "card_sn": card_sn,
            "bindable": True,
            "state": "previously_bound_by_me",
            "current_binding": None,
            "latest_user_binding": _public_binding(latest, card),
            "connect_hint": _connect_hint(latest, card),
        }

    return {
        "ok": True,
        "card_sn": card_sn,
        "bindable": True,
        "state": "never_bound_by_me",
        "current_binding": None,
        "latest_user_binding": None,
        "connect_hint": None,
    }


@router.post("/cards/bindings")
async def bind_card(req: BindRequest, user_id: str = Depends(get_current_user_id)):
    card_sn = _clean_required(req.card_sn, "card_sn")
    card_device_uuid = _clean_required(req.card_device_uuid, "card_device_uuid")
    card_app_uuid = _clean_required(req.card_app_uuid, "card_app_uuid")

    async with AsyncSessionLocal() as db:
        try:
            card = (await db.execute(
                select(Card).where(Card.card_sn == card_sn).with_for_update()
            )).scalar_one_or_none()
            if card is None:
                card = Card(
                    card_sn=card_sn,
                    card_device_uuid=card_device_uuid,
                )
                db.add(card)
                await db.flush()

            card.card_device_uuid = card_device_uuid
            card.card_mac = _clean_optional(req.card_mac)
            card.card_mac_from = _clean_optional(req.card_mac_from.lower() if req.card_mac_from else None)
            card.card_name = _clean_optional(req.card_name)
            card.updated_at = _now()

            active = await _active_binding(db, card)
            if active is not None and active.user_id != user_id:
                raise HTTPException(status_code=409, detail="card already bound by another user")

            if active is not None:
                active.card_app_uuid = card_app_uuid
                active.card_nick = _clean_optional(req.card_nick)
                active.updated_at = _now()
                binding = active
                action = "updated"
            else:
                binding = CardBinding(
                    user_id=user_id,
                    card_id=card.id,
                    card_nick=_clean_optional(req.card_nick),
                    card_app_uuid=card_app_uuid,
                    bind_status="bound",
                    bind_time=_now(),
                    active_card_id=card.id,
                    created_at=_now(),
                    updated_at=_now(),
                )
                db.add(binding)
                action = "created"

            await db.commit()
            await db.refresh(card)
            await db.refresh(binding)
        except HTTPException:
            await db.rollback()
            raise
        except IntegrityError as exc:
            await db.rollback()
            raise HTTPException(
                status_code=409,
                detail="card already bound by another user",
            ) from exc

    return {
        "ok": True,
        "action": action,
        "binding": _public_binding(binding, card),
    }


@router.get("/cards/bindings")
async def list_bindings(user_id: str = Depends(get_current_user_id)):
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(CardBinding, Card)
            .join(Card, CardBinding.card_id == Card.id)
            .where(
                CardBinding.user_id == user_id,
                CardBinding.bind_status == "bound",
                CardBinding.active_card_id.is_not(None),
            )
            .order_by(CardBinding.bind_time.desc(), CardBinding.created_at.desc())
        )).all()
    return {
        "ok": True,
        "bindings": [_public_binding(binding, card) for binding, card in rows],
    }


@router.post("/cards/{binding_id}/unbind")
async def unbind_card(
    binding_id: str,
    req: UnbindRequest,
    user_id: str = Depends(get_current_user_id),
):
    try:
        bid = uuid.UUID(binding_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid binding id")

    async with AsyncSessionLocal() as db:
        row = (await db.execute(
            select(CardBinding, Card)
            .join(Card, CardBinding.card_id == Card.id)
            .where(
                CardBinding.id == bid,
                CardBinding.user_id == user_id,
                CardBinding.bind_status == "bound",
                CardBinding.active_card_id.is_not(None),
            )
        )).first()
        if row is None:
            raise HTTPException(status_code=404, detail="binding not found")

        binding, card = row
        binding.bind_status = "unbound"
        binding.unbind_time = _now()
        binding.active_card_id = None
        binding.updated_at = _now()
        await db.commit()
        await db.refresh(binding)

    return {
        "ok": True,
        "delete_data": bool(req.delete_data),
        "binding": _public_binding(binding, card),
    }
