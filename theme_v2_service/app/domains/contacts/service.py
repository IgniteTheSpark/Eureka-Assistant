from __future__ import annotations

import unicodedata

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import utc_now
from app.db.models import Contact, Event, EventAttendee
from app.domains.contacts.schemas import ContactCreate, ContactUpdate
from app.domains.sessions.provenance import validate_owned_provenance


SUPPORTED_SOCIALS = {
    "x",
    "telegram",
    "linkedin",
    "wechat",
    "xiaohongshu",
    "instagram",
}


def normalize_contact_name(value: str) -> str:
    return unicodedata.normalize("NFKC", value or "").strip().casefold()


def clean_socials(values: dict | None) -> dict[str, str]:
    cleaned: dict[str, str] = {}
    for key, value in (values or {}).items():
        normalized_key = str(key).strip().casefold()
        normalized_value = str(value).strip()
        if normalized_key in SUPPORTED_SOCIALS and normalized_value:
            cleaned[normalized_key] = normalized_value
    return cleaned


def clean_notes(values: list | None) -> list[str]:
    return list(
        dict.fromkeys(str(value).strip() for value in (values or []) if str(value).strip())
    )


async def create_contact(
    session: AsyncSession,
    user_id: str,
    command: ContactCreate,
) -> Contact:
    provenance = await validate_owned_provenance(
        session,
        user_id,
        session_id=command.session_id,
        input_turn_id=command.source_input_turn_id,
    )
    contact = Contact(
        user_id=user_id,
        name=command.name.strip(),
        phone=(command.phone or "").strip() or None,
        company=(command.company or "").strip() or None,
        title=(command.title or "").strip() or None,
        email=(command.email or "").strip() or None,
        notes_json=clean_notes(command.notes),
        socials_json=clean_socials(command.socials),
        session_id=provenance.session_id,
        source_input_turn_id=provenance.input_turn_id,
    )
    session.add(contact)
    await session.flush()
    return contact


async def get_contact(
    session: AsyncSession,
    user_id: str,
    contact_id: str,
) -> Contact | None:
    return await session.scalar(
        select(Contact).where(Contact.id == contact_id, Contact.user_id == user_id)
    )


async def list_contacts(
    session: AsyncSession,
    user_id: str,
    *,
    name_query: str = "",
    exact_name: str = "",
    limit: int = 50,
) -> list[Contact]:
    query = select(Contact).where(Contact.user_id == user_id)
    if name_query.strip():
        query = query.where(Contact.name.contains(name_query.strip()))
    contacts = list(
        await session.scalars(
            query.order_by(Contact.created_at.desc(), Contact.id.desc()).limit(limit)
        )
    )
    if exact_name.strip():
        normalized = normalize_contact_name(exact_name)
        contacts = [
            contact
            for contact in contacts
            if normalize_contact_name(contact.name) == normalized
        ]
    return contacts


async def update_contact(
    session: AsyncSession,
    user_id: str,
    contact_id: str,
    command: ContactUpdate,
) -> Contact | None:
    contact = await get_contact(session, user_id, contact_id)
    if contact is None:
        return None
    for field in ("name", "phone", "company", "title", "email"):
        if field in command.model_fields_set:
            value = getattr(command, field)
            setattr(contact, field, (value or "").strip() or None)
    if "notes" in command.model_fields_set and command.notes is not None:
        contact.notes_json = clean_notes(command.notes)
    if "socials" in command.model_fields_set and command.socials is not None:
        contact.socials_json = clean_socials(command.socials)
    contact.updated_at = utc_now()
    await session.flush()
    return contact


async def update_contact_field(
    session: AsyncSession,
    user_id: str,
    contact_id: str,
    *,
    field: str,
    value: str,
) -> Contact | None:
    contact = await get_contact(session, user_id, contact_id)
    if contact is None:
        return None
    normalized_field = field.strip().casefold()
    if normalized_field == "notes":
        contact.notes_json = clean_notes([*(contact.notes_json or []), value])
    elif normalized_field in SUPPORTED_SOCIALS:
        socials = dict(contact.socials_json or {})
        normalized_value = value.strip()
        if normalized_value:
            socials[normalized_field] = normalized_value
        else:
            socials.pop(normalized_field, None)
        contact.socials_json = clean_socials(socials)
    elif normalized_field in {"name", "phone", "company", "title", "email"}:
        setattr(contact, normalized_field, value.strip() or None)
    else:
        raise ValueError(f"unknown contact field: {field}")
    contact.updated_at = utc_now()
    await session.flush()
    return contact


async def delete_contact(
    session: AsyncSession,
    user_id: str,
    contact_id: str,
) -> Contact | None:
    contact = await get_contact(session, user_id, contact_id)
    if contact is None:
        return None
    attendees = list(
        await session.scalars(
            select(EventAttendee)
            .join(Event, Event.id == EventAttendee.event_id)
            .where(
                Event.user_id == user_id,
                EventAttendee.contact_id == contact.id,
            )
        )
    )
    for attendee in attendees:
        attendee.name_raw = attendee.name_raw.strip() or contact.name
        attendee.contact_id = None
    await session.flush()
    await session.delete(contact)
    await session.flush()
    return contact
