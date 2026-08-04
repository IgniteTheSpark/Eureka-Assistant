from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import utc_now
from app.domains.devices.models import Card, CardBinding
from app.domains.devices.schemas import BindRequest


class CardBoundByOther(Exception):
    pass


@dataclass(frozen=True)
class BindResult:
    action: str
    binding: CardBinding
    card: Card


@dataclass(frozen=True)
class UnbindResult:
    binding: CardBinding
    card: Card


def clean_required(value: str | None, field: str) -> str:
    cleaned = (value or "").strip()
    if not cleaned:
        raise ValueError(f"{field} required")
    return cleaned


def _clean_optional(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    return cleaned or None


def public_binding(binding: CardBinding, card: Card) -> dict:
    return {
        "binding_id": binding.id,
        "card_id": binding.card_id,
        "card_nick": binding.card_nick,
        "card_app_uuid": binding.card_app_uuid,
        "bind_status": binding.bind_status,
        "bind_time": binding.bind_time,
        "unbind_time": binding.unbind_time,
        "created_at": binding.created_at,
        "updated_at": binding.updated_at,
        "card_sn": card.card_sn,
        "card_device_uuid": card.card_device_uuid,
        "card_mac": card.card_mac,
        "card_mac_from": card.card_mac_from,
        "card_name": card.card_name,
    }


def _connect_hint(binding: CardBinding, card: Card) -> dict:
    return {
        "card_app_uuid": binding.card_app_uuid,
        "card_device_uuid": card.card_device_uuid,
        "card_name": card.card_name,
        "card_mac": card.card_mac,
    }


async def _active_binding(
    session: AsyncSession,
    card: Card,
) -> CardBinding | None:
    return await session.scalar(
        select(CardBinding).where(
            CardBinding.active_card_id == card.id,
            CardBinding.bind_status == "bound",
        )
    )


async def _latest_user_binding(
    session: AsyncSession,
    user_id: str,
    card: Card,
) -> CardBinding | None:
    return await session.scalar(
        select(CardBinding)
        .where(
            CardBinding.user_id == user_id,
            CardBinding.card_id == card.id,
        )
        .order_by(CardBinding.bind_time.desc(), CardBinding.created_at.desc())
        .limit(1)
    )


async def binding_info(
    session: AsyncSession,
    user_id: str,
    card_sn: str,
) -> dict:
    normalized_sn = clean_required(card_sn, "card_sn")
    card = await session.scalar(select(Card).where(Card.card_sn == normalized_sn))
    if card is None:
        return {
            "ok": True,
            "card_sn": normalized_sn,
            "bindable": True,
            "state": "never_bound_by_me",
            "current_binding": None,
            "latest_user_binding": None,
            "connect_hint": None,
        }

    active = await _active_binding(session, card)
    latest = await _latest_user_binding(session, user_id, card)
    latest_public = public_binding(latest, card) if latest is not None else None
    if active is not None and active.user_id != user_id:
        return {
            "ok": True,
            "card_sn": normalized_sn,
            "bindable": False,
            "state": "bound_by_other",
            "current_binding": None,
            "latest_user_binding": latest_public,
            "connect_hint": None,
        }
    if active is not None:
        return {
            "ok": True,
            "card_sn": normalized_sn,
            "bindable": True,
            "state": "bound_by_me",
            "current_binding": public_binding(active, card),
            "latest_user_binding": latest_public,
            "connect_hint": _connect_hint(active, card),
        }
    if latest is not None:
        return {
            "ok": True,
            "card_sn": normalized_sn,
            "bindable": True,
            "state": "previously_bound_by_me",
            "current_binding": None,
            "latest_user_binding": latest_public,
            "connect_hint": _connect_hint(latest, card),
        }
    return {
        "ok": True,
        "card_sn": normalized_sn,
        "bindable": True,
        "state": "never_bound_by_me",
        "current_binding": None,
        "latest_user_binding": None,
        "connect_hint": None,
    }


async def bind_card(
    session: AsyncSession,
    user_id: str,
    command: BindRequest,
) -> BindResult:
    card_sn = clean_required(command.card_sn, "card_sn")
    card_device_uuid = clean_required(command.card_device_uuid, "card_device_uuid")
    card_app_uuid = clean_required(command.card_app_uuid, "card_app_uuid")

    card = await session.scalar(
        select(Card).where(Card.card_sn == card_sn).with_for_update()
    )
    if card is None:
        card = Card(card_sn=card_sn, card_device_uuid=card_device_uuid)
        session.add(card)
        await session.flush()

    now = utc_now()
    card.card_device_uuid = card_device_uuid
    card.card_mac = _clean_optional(command.card_mac)
    card.card_mac_from = _clean_optional(
        command.card_mac_from.lower() if command.card_mac_from else None
    )
    card.card_name = _clean_optional(command.card_name)
    card.updated_at = now

    active = await _active_binding(session, card)
    if active is not None and active.user_id != user_id:
        raise CardBoundByOther()

    if active is not None:
        active.card_app_uuid = card_app_uuid
        active.card_nick = _clean_optional(command.card_nick)
        active.updated_at = now
        binding = active
        action = "updated"
    else:
        binding = CardBinding(
            user_id=user_id,
            card_id=card.id,
            active_card_id=card.id,
            card_nick=_clean_optional(command.card_nick),
            card_app_uuid=card_app_uuid,
            bind_status="bound",
            bind_time=now,
            created_at=now,
            updated_at=now,
        )
        session.add(binding)
        action = "created"

    await session.flush()
    return BindResult(action=action, binding=binding, card=card)


async def list_bindings(
    session: AsyncSession,
    user_id: str,
) -> list[tuple[CardBinding, Card]]:
    rows = await session.execute(
        select(CardBinding, Card)
        .join(Card, CardBinding.card_id == Card.id)
        .where(
            CardBinding.user_id == user_id,
            CardBinding.bind_status == "bound",
            CardBinding.active_card_id.is_not(None),
        )
        .order_by(CardBinding.bind_time.desc(), CardBinding.created_at.desc())
    )
    return list(rows.tuples())


async def unbind_card(
    session: AsyncSession,
    user_id: str,
    binding_id: str,
) -> UnbindResult | None:
    row = (
        await session.execute(
            select(CardBinding, Card)
            .join(Card, CardBinding.card_id == Card.id)
            .where(
                CardBinding.id == binding_id,
                CardBinding.user_id == user_id,
            )
            .with_for_update()
        )
    ).first()
    if row is None:
        return None

    binding, card = row
    if binding.bind_status == "bound":
        now = utc_now()
        binding.bind_status = "unbound"
        binding.unbind_time = now
        binding.active_card_id = None
        binding.updated_at = now
        await session.flush()
    return UnbindResult(binding=binding, card=card)
