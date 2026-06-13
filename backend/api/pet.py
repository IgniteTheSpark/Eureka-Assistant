"""
§9 球球 Pet API.

GET   /api/pet         — the user's pet (lazily creates an un-spawned egg)
POST  /api/pet/spawn   — hatch: name it + assign a random emblem (skin already
                         seeded on the egg); idempotent once spawned
PATCH /api/pet         — rename and/or equip collected cosmetics

The pet grows passively via completion_events (see core/completion.py); these
endpoints are just read + spawn + wardrobe. No levels.
"""
import random
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select

from core import pet as petlib
from core.auth import get_current_user_id
from core.completion import get_or_create_pet
from db.database import AsyncSessionLocal
from db.models import FlashRecording, Message, Pet, Session as DBSession

router = APIRouter()


class SpawnRequest(BaseModel):
    name: str = ""


class PetPatch(BaseModel):
    name: str | None = None
    equip: dict | None = None   # {slot: value} — slot ∈ skin/emblem/emblem_color/head/leftItem/rightItem/carrier/aura


class OnboardingCompleteRequest(BaseModel):
    session_id: str = ""
    recording_id: str = ""


# default equipped state — carrier grounded, aura = the soft skin-derived glow.
_EQUIP_DEFAULT = {"head": "none", "leftItem": "none", "rightItem": "none",
                  "carrier": "none", "aura": "soft"}


def _serialize(pet: Pet) -> dict:
    # back-fill the two newer slots on pets created before v2 (JSON columns, no
    # migration): a missing carrier/aura defaults to grounded / soft glow.
    equipped = {**_EQUIP_DEFAULT, **(pet.equipped or {})}
    unlocked = {**petlib.empty_unlocked(), **(pet.unlocked or {})}
    return {
        "spawned":      bool(pet.spawned),
        "onboarding_completed": pet.onboarding_completed_at is not None,
        "onboarding_completed_at": pet.onboarding_completed_at.isoformat() if pet.onboarding_completed_at else None,
        "name":         pet.name or "Reka",
        "seed":         pet.seed,
        "skin":         pet.skin,
        "emblem":       pet.emblem,
        "emblem_color": pet.emblem_color,
        "equipped":     equipped,
        "unlocked":     unlocked,
        "milestones":   pet.milestones or petlib.empty_milestones(),
    }


def _has_success_card(cards) -> bool:
    if not isinstance(cards, list):
        return False
    for c in cards:
        if not isinstance(c, dict):
            continue
        if c.get("card_type") == "error":
            continue
        if c.get("asset_id") or c.get("event_id") or c.get("contact_id"):
            return True
    return False


async def _session_has_success_cards(db, user_id: str, session_id: uuid.UUID) -> bool:
    rows = (await db.execute(
        select(Message.cards).where(
            Message.user_id == user_id,
            Message.session_id == session_id,
        )
    )).scalars().all()
    return any(_has_success_card(cards) for cards in rows)


@router.get("/pet")
async def get_pet(user_id: str = Depends(get_current_user_id)):
    """Return the pet. Lazily provisions an un-spawned egg (skin seeded from the
    user) so the client can show the egg/spawn takeover."""
    async with AsyncSessionLocal() as db:
        pet = await get_or_create_pet(db, user_id)
        await db.commit()
        return {"ok": True, "pet": _serialize(pet)}


@router.get("/pet/milestones")
async def get_milestones(user_id: str = Depends(get_current_user_id)):
    """§9.5 — the full 40-milestone ladder + this user's progress (the tracking
    surface). Each row: condition (`label`/`metric`/`threshold`), reward
    (`reward_slot`/`reward_key`/`tier`/`exclusive`), and `achieved`/`current`/
    `reward_owned`. Config = `core/milestones.py` (single source of truth)."""
    from core.milestones import progress
    async with AsyncSessionLocal() as db:
        pet = await get_or_create_pet(db, user_id)
        await db.commit()
        items = progress(pet.milestones or petlib.empty_milestones(),
                         {**petlib.empty_unlocked(), **(pet.unlocked or {})})
    return {
        "ok": True,
        "milestones": items,
        "summary": {"achieved": sum(1 for m in items if m["achieved"]), "total": len(items)},
    }


@router.post("/pet/spawn")
async def spawn_pet(req: SpawnRequest, user_id: str = Depends(get_current_user_id)):
    """Hatch the egg: keep the seeded skin, roll a random starter emblem, set the
    name, mark spawned. Idempotent — re-spawning just returns the current pet."""
    async with AsyncSessionLocal() as db:
        pet = await get_or_create_pet(db, user_id)
        if not pet.spawned:
            rng = random.Random(f"{user_id}:spawn")
            pet.emblem = rng.choice(petlib.EMBLEMS)
            pet.emblem_color = petlib.default_emblem_color(pet.skin or "aurora")
            # starter wardrobe = the body + emblem it hatched with + the freebies
            # (none carrier / none+soft aura) so the 7-slot wardrobe is never empty.
            unlocked = petlib.empty_unlocked()
            unlocked["skin"] = [pet.skin]
            unlocked["emblem"] = [pet.emblem]
            # §9.3 hatch grant — one guaranteed accessory so Reka hatches dressed.
            starter = petlib.starter_drop(rng)
            unlocked[starter["slot"]] = list(unlocked.get(starter["slot"], [])) + [starter["key"]]
            pet.unlocked = unlocked
            # equip the starter accessory (head → head slot; item → left hand).
            equipped = dict(_EQUIP_DEFAULT)
            if starter["slot"] == "head":
                equipped["head"] = starter["key"]
            else:
                equipped["leftItem"] = starter["key"]
            pet.equipped = equipped
            pet.milestones = petlib.empty_milestones()
            pet.spawned = 1
        name = (req.name or "").strip()
        if name:
            pet.name = name[:50]
        await db.commit()
        return {"ok": True, "pet": _serialize(pet)}


@router.patch("/pet")
async def patch_pet(req: PetPatch, user_id: str = Depends(get_current_user_id)):
    """Rename and/or equip cosmetics. Equipping only accepts values the user has
    unlocked (or 'none'); cosmetics never lock function."""
    async with AsyncSessionLocal() as db:
        pet = (await db.execute(select(Pet).where(Pet.user_id == user_id))).scalar_one_or_none()
        if pet is None:
            pet = await get_or_create_pet(db, user_id)
        if req.name is not None and req.name.strip():
            pet.name = req.name.strip()[:50]

        if req.equip:
            unlocked = {**petlib.empty_unlocked(), **(pet.unlocked or {})}
            equipped = {**_EQUIP_DEFAULT, **(pet.equipped or {})}
            for slot, val in req.equip.items():
                if slot == "skin" and val in (unlocked.get("skin") or []):
                    pet.skin = val
                elif slot == "emblem" and (val == "none" or val in (unlocked.get("emblem") or [])):
                    pet.emblem = val
                elif slot == "emblem_color" and val in petlib.EMBLEM_COLORS:
                    pet.emblem_color = val
                elif slot == "head" and (val == "none" or val in (unlocked.get("head") or [])):
                    equipped["head"] = val
                elif slot in ("leftItem", "rightItem") and (val == "none" or val in (unlocked.get("item") or [])):
                    equipped[slot] = val
                elif slot == "carrier" and (val == "none" or val in (unlocked.get("carrier") or [])):
                    equipped["carrier"] = val
                elif slot == "aura" and (val in ("none", "soft") or val in (unlocked.get("aura") or [])):
                    equipped["aura"] = val
            pet.equipped = equipped

        await db.commit()
        return {"ok": True, "pet": _serialize(pet)}


@router.post("/pet/onboarding-complete")
async def complete_onboarding(
    req: OnboardingCompleteRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Mark onboarding complete only after the first capture produced a real card."""
    session_id: uuid.UUID | None = None
    recording_has_success_cards = False

    async with AsyncSessionLocal() as db:
        if req.recording_id:
            try:
                rid = uuid.UUID(req.recording_id)
            except ValueError:
                raise HTTPException(status_code=400, detail="invalid recording id")
            recording = (await db.execute(
                select(FlashRecording).where(
                    FlashRecording.id == rid,
                    FlashRecording.user_id == user_id,
                )
            )).scalar_one_or_none()
            if recording is None:
                raise HTTPException(status_code=404, detail="recording not found")
            if recording.process_status != "done" or not _has_success_card(recording.result_cards or []):
                raise HTTPException(status_code=409, detail="recording has no completed asset card")
            recording_has_success_cards = True
            session_id = recording.session_id

        if req.session_id:
            try:
                requested_sid = uuid.UUID(req.session_id)
            except ValueError:
                raise HTTPException(status_code=400, detail="invalid session id")
            if session_id is not None and requested_sid != session_id:
                raise HTTPException(status_code=400, detail="recording/session mismatch")
            session_id = requested_sid

        if session_id is None:
            raise HTTPException(status_code=400, detail="session_id or recording_id required")

        sess = (await db.execute(
            select(DBSession).where(
                DBSession.id == session_id,
                DBSession.user_id == user_id,
            )
        )).scalar_one_or_none()
        if sess is None:
            raise HTTPException(status_code=404, detail="session not found")

        if not recording_has_success_cards and not await _session_has_success_cards(db, user_id, session_id):
            raise HTTPException(status_code=409, detail="session has no asset card")

        pet = await get_or_create_pet(db, user_id)
        if pet.onboarding_completed_at is None:
            pet.onboarding_completed_at = datetime.now(timezone.utc)
        await db.commit()
        await db.refresh(pet)
        return {"ok": True, "pet": _serialize(pet)}
