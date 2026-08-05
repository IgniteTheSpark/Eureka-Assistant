from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domains.sessions.models import ChatSession, InputTurn


class ProvenanceNotOwned(Exception):
    pass


@dataclass(frozen=True)
class OwnedProvenance:
    session_id: str | None
    input_turn_id: str | None


async def validate_owned_provenance(
    database: AsyncSession,
    user_id: str,
    *,
    session_id: str | None,
    input_turn_id: str | None,
) -> OwnedProvenance:
    owner_session = None
    if session_id:
        owner_session = await database.scalar(
            select(ChatSession).where(
                ChatSession.id == session_id,
                ChatSession.user_id == user_id,
            )
        )
        if owner_session is None:
            raise ProvenanceNotOwned("session not owned by user")

    owner_turn = None
    if input_turn_id:
        owner_turn = await database.scalar(
            select(InputTurn).where(
                InputTurn.id == input_turn_id,
                InputTurn.user_id == user_id,
            )
        )
        if owner_turn is None:
            raise ProvenanceNotOwned("input_turn not owned by user")
        if owner_session is not None and owner_turn.session_id != owner_session.id:
            raise ProvenanceNotOwned("input_turn does not belong to session")

    return OwnedProvenance(
        session_id=(owner_session.id if owner_session else None)
        or (owner_turn.session_id if owner_turn else None),
        input_turn_id=owner_turn.id if owner_turn else None,
    )
