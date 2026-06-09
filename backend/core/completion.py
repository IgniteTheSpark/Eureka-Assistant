"""
completion_event currency (§7/§9.1).

`emit_completion_event` is the ONE call every closed loop makes: a record logged,
a todo completed, an opportunistic first-class create. It:
  1. appends a `completion_events` row (the future weekly island aggregates these
     per `domain`), and
  2. lets the user's 球球 react — bump cumulative milestones + roll a cosmetic drop
     (only when the pet is already spawned/hatched).

Best-effort and self-contained: opens its own session and never raises, so a pet
hiccup can never break the create flow that called it. The pet is fully decoupled
from island/tasks/domain — it just needs "a loop closed".
"""
import random
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import select

from core import pet as petlib
from core.domains import normalize_domain
from db.database import AsyncSessionLocal
from db.models import Pet, CompletionEvent

_TZ = timezone(timedelta(hours=8))   # day boundaries follow the app's +08:00
_MAX_UNLOCKS_PER_EVENT = 4            # trickle milestone grants, never a toast-burst


async def get_or_create_pet(db, user_id: str) -> Pet:
    """Lazily provision an UN-spawned pet (egg) for this user. The skin is seeded
    deterministically so the egg shell + hatched body match ('这只是我的')."""
    pet = (await db.execute(select(Pet).where(Pet.user_id == user_id))).scalar_one_or_none()
    if pet:
        return pet
    skin = petlib.seeded_skin(user_id)
    pet = Pet(
        user_id=user_id, seed=user_id, name=None,
        skin=skin, emblem="star", emblem_color=petlib.default_emblem_color(skin),
        equipped={"head": "none", "leftItem": "none", "rightItem": "none",
                  "carrier": "none", "aura": "soft"},
        unlocked={**petlib.empty_unlocked(), "skin": [skin], "emblem": ["star"]},
        milestones=petlib.empty_milestones(),
        spawned=0,
    )
    db.add(pet)
    await db.flush()
    return pet


async def emit_completion_event(
    user_id: str, source: str, ref: Optional[str] = None, domain: Optional[str] = None,
) -> dict:
    """Append a completion_event and let the pet react. Returns
    {event_id, drop?} (drop = {slot, key} if one was rolled). Never raises."""
    try:
        async with AsyncSessionLocal() as db:
            ev = CompletionEvent(
                user_id=user_id, source=source,
                ref=str(ref) if ref else None, domain=normalize_domain(domain),
            )
            db.add(ev)
            await db.flush()

            drop = None
            unlocks = []
            pet = await get_or_create_pet(db, user_id)
            # Only a hatched pet collects — pre-spawn events are still logged (for
            # the island) but the egg doesn't grow until the user hatches it.
            if pet.spawned:
                today = datetime.now(_TZ).date().isoformat()
                pet.milestones = petlib.bump_milestones(pet.milestones, today, ev.domain)
                # back-fill the v2 pools (carrier/aura) on pre-v2 pets.
                unlocked = {**petlib.empty_unlocked(), **(pet.unlocked or {})}
                rng = random.Random(f"{user_id}:{pet.milestones['capture_count']}:{ref}")
                drop = petlib.roll_drop(unlocked, rng)
                if drop:
                    unlocked[drop["slot"]] = list(unlocked.get(drop["slot"], [])) + [drop["key"]]
                # §9.5 milestone unlocks (40-ladder, core/milestones.py) — granted the
                # moment a counter condition is met. Cap per event so a user who
                # newly-qualifies for many at once (e.g. existing players on the 40-
                # milestone rollout) gets them as a pleasant trickle, not a 20-toast
                # burst; the rest land on subsequent events (config order = easy→hard).
                unlocks = petlib.check_unlocks(unlocked, pet.milestones)[:_MAX_UNLOCKS_PER_EVENT]
                for u in unlocks:
                    unlocked[u["slot"]] = list(unlocked.get(u["slot"], [])) + [u["key"]]
                pet.unlocked = unlocked
            await db.commit()
            return {"event_id": str(ev.id), "drop": drop, "unlocks": unlocks}
    except Exception as e:  # noqa — best-effort; pet must never break a create
        print(f"[completion] emit failed (non-fatal): {str(e)[:120]}", flush=True)
        return {}
