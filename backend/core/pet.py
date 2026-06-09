"""
§9 球球 Pet — server-side genome + growth logic.

Mirrors the cosmetic key-space of the design engine (`gamemode/mascot.js`) so the
backend assigns/stores valid genome values and the WebView render (which IS
mascot.js) draws them. The pet has NO levels; growth = horizontally collecting
cosmetics. It reacts ONLY to completion_events (§9.1) — never reads island /
tasks / domain.

Slots (7 swappable; eyes & mouth are state-driven, not stored):
  skin · emblem (+ emblem_color) · head · leftItem · rightItem · carrier · aura

Collection economy (§9.5):
  - random drops  → roll_drop, ~55% of events, from the un-owned droppable set
  - milestone unlocks → check_unlocks, granted when a LOCK condition is met
  - rarity tiers  → RARITY, presentation + (future) drop weighting
  none / soft are always-owned freebies; they are never dropped or locked.
"""
import hashlib
import random
from datetime import date, timedelta
from typing import Optional

# ── cosmetic key-space (must match gamemode/mascot.js) ───────────────────────
SKINS = ["aurora", "grape", "coral", "lime", "ocean", "bubble", "ember", "mint", "sky", "gold"]
EMBLEMS = ["star", "plus", "heart", "drop", "ring", "bolt", "leaf"]          # 'none' excluded from drops
EMBLEM_COLORS = ["gold", "white", "cyan", "magenta", "sky", "lime", "coral"]
HEADS = ["safari", "beanie", "horns", "antenna", "sprout", "crown"]          # 'none' = bare
ITEMS = ["laptop", "book", "coin", "pen", "umbrella", "magnify", "flower", "dumbbell", "leaf"]  # 'none' = empty hand
CARRIERS = ["cloud", "disc", "pad", "board", "ring"]                          # 'none' = grounded
AURAS = ["gold", "cyan", "magenta", "azure", "ember", "verdant", "frost", "rainbow"]  # 'none'/'soft' = freebies
WARM_SKINS = {"coral", "ember", "gold", "bubble"}

# ── rarity (§9.5) — one tier per cosmetic; drives card bg/tag in the wardrobe ─
TIERS = ["normal", "rare", "epic", "legendary"]
RARITY = {
    "skin": {"aurora": "rare", "grape": "normal", "coral": "normal", "lime": "normal",
             "ocean": "normal", "bubble": "epic", "ember": "rare", "mint": "rare",
             "sky": "normal", "gold": "legendary"},
    "emblem": {"star": "normal", "plus": "normal", "heart": "rare", "drop": "rare",
               "ring": "epic", "bolt": "epic", "leaf": "rare", "none": "normal"},
    "emblem_color": {"gold": "rare", "white": "normal", "cyan": "rare", "magenta": "epic",
                     "sky": "normal", "lime": "rare", "coral": "rare"},
    "head": {"none": "normal", "safari": "rare", "beanie": "normal", "horns": "rare",
             "antenna": "epic", "sprout": "rare", "crown": "legendary"},
    "item": {"none": "normal", "laptop": "rare", "book": "normal", "coin": "rare",
             "pen": "normal", "umbrella": "epic", "magnify": "rare", "flower": "rare",
             "dumbbell": "epic", "leaf": "normal"},
    "carrier": {"none": "normal", "cloud": "rare", "disc": "epic", "pad": "rare",
                "board": "epic", "ring": "legendary"},
    "aura": {"none": "normal", "soft": "normal", "gold": "rare", "cyan": "rare",
             "magenta": "epic", "azure": "rare", "ember": "epic", "verdant": "rare",
             "frost": "rare", "rainbow": "legendary"},
}

# ── always-owned freebies — never dropped, never locked ──────────────────────
FREE = {"carrier": ["none"], "aura": ["none", "soft"]}

# ── milestone-EXCLUSIVE rewards — the ONLY cosmetics removed from the random drop
# pool, so the single way to earn them is hitting the milestone (the endgame
# legendaries + the 14-day-streak bubble). The full 40-milestone ladder + every
# unlock condition lives in core/milestones.py; everything else a milestone grants
# is ALSO droppable (additive, §9.5). Kept here (not derived) so DROP_POOL builds
# at import without importing milestones (avoids a cycle).
EXCLUSIVE_KEYS = {
    ("skin", "gold"), ("skin", "bubble"), ("head", "crown"),
    ("carrier", "ring"), ("aura", "rainbow"),
}

# ── drop pool keyed by genome slot ('item' covers both hands). Excludes the
# always-owned freebies and the milestone-EXCLUSIVE keys so random drops never
# collide with the exclusive endgame rewards. ────────────────────────────────
_RAW_POOL = {"skin": SKINS, "emblem": EMBLEMS, "head": HEADS, "item": ITEMS,
             "carrier": CARRIERS, "aura": AURAS}
_EXCL_BY_SLOT = {}
for _s, _k in EXCLUSIVE_KEYS:
    _EXCL_BY_SLOT.setdefault(_s, set()).add(_k)
DROP_POOL = {
    slot: [k for k in pool if k not in _EXCL_BY_SLOT.get(slot, set())]
    for slot, pool in _RAW_POOL.items()
}
_DROP_CHANCE = 0.55   # ~55% of events yield a cosmetic (keeps drops feeling special; only-increase, no FOMO)


def seeded_skin(seed: str) -> str:
    """Deterministic body color per user (the egg shell uses this too)."""
    h = int(hashlib.sha256((seed or "default").encode()).hexdigest(), 16)
    return SKINS[h % len(SKINS)]


def default_emblem_color(skin: str) -> str:
    """Warm body → cool mark, so the emblem reads on any color (mirrors mascot.js)."""
    return "sky" if skin in WARM_SKINS else "gold"


def empty_unlocked() -> dict:
    """All collectible pools + the always-owned freebies (none/soft)."""
    return {"skin": [], "emblem": [], "head": [], "item": [],
            "carrier": list(FREE["carrier"]), "aura": list(FREE["aura"])}


def empty_milestones() -> dict:
    return {"capture_count": 0, "streak_days": 0, "last_event_date": None, "domains": []}


def tier_of(slot: str, key: str) -> str:
    """Rarity tier for a (slot,key). leftItem/rightItem share the 'item' table."""
    t = "item" if slot in ("leftItem", "rightItem") else slot
    return (RARITY.get(t) or {}).get(key, "normal")


def roll_drop(unlocked: dict, rng: random.Random) -> Optional[dict]:
    """Roll one cosmetic drop from the still-locked droppable set, or None.

    Only-increase: once everything droppable is owned, no more drops. ~55%
    chance per event so drops stay a small surprise, never a chore.
    """
    locked = []
    for slot, pool in DROP_POOL.items():
        have = set((unlocked or {}).get(slot, []))
        for k in pool:
            if k not in have:
                locked.append((slot, k))
    if not locked or rng.random() > _DROP_CHANCE:
        return None
    slot, key = rng.choice(locked)
    return {"slot": slot, "key": key}


def check_unlocks(unlocked: dict, milestones: dict) -> list[dict]:
    """Grant any milestone reward whose condition is now met and not yet owned.
    Reads the 40-milestone config (core/milestones.py). Returns newly-granted
    {slot,key} so callers can toast. Lazy import avoids a module cycle."""
    from core.milestones import MILESTONES, metric_value
    granted = []
    un = unlocked or empty_unlocked()
    ms = milestones or empty_milestones()
    for m in MILESTONES:
        slot, key = m["reward_slot"], m["reward_key"]
        if key in set((un or {}).get(slot, [])):
            continue
        try:
            if metric_value(m["metric"], ms, un) >= m["threshold"]:
                granted.append({"slot": slot, "key": key})
        except Exception:
            continue
    return granted


def starter_drop(rng: random.Random) -> dict:
    """A guaranteed accessory granted at hatch (§9.3) — a random head or hand
    item from the common/rare tiers, so the freshly-hatched Reka isn't bare."""
    pool = [("head", k) for k in DROP_POOL["head"] if tier_of("head", k) in ("normal", "rare")]
    pool += [("item", k) for k in DROP_POOL["item"] if tier_of("item", k) in ("normal", "rare")]
    slot, key = rng.choice(pool)
    return {"slot": slot, "key": key}


def bump_milestones(ms: dict, today: str, domain: Optional[str]) -> dict:
    """Cumulative only — never punish a missed day (§9). Streak increments on a
    consecutive day, resets on a gap, holds on same-day repeats."""
    ms = dict(ms or empty_milestones())
    ms["capture_count"] = int(ms.get("capture_count", 0)) + 1
    last = ms.get("last_event_date")
    if last == today:
        pass
    elif last == _yesterday(today):
        ms["streak_days"] = int(ms.get("streak_days", 0)) + 1
    else:
        ms["streak_days"] = 1
    ms["last_event_date"] = today
    if domain:
        doms = list(ms.get("domains", []))
        if domain not in doms:
            doms.append(domain)
        ms["domains"] = doms
    return ms


def _yesterday(today: str) -> Optional[str]:
    try:
        return (date.fromisoformat(today) - timedelta(days=1)).isoformat()
    except (ValueError, TypeError):
        return None
