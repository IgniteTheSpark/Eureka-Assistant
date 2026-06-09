"""§9.5 / §10 — milestone config: the single source of truth for achievement → reward.

40 milestones. Each = a tracked metric crossing a threshold → grant ONE specific
cosmetic. **Additive** to the ~55% random drops (core/pet.py): most milestone
rewards are ALSO droppable, so a milestone is a *guaranteed* path to that cosmetic
(luck can get it earlier). Only the 5 legendaries are drop-EXCLUSIVE.

Metrics (evaluated from the pet's `milestones` + `unlocked` JSON — no new tracking):
  capture  — cumulative captures (milestones.capture_count)
  streak   — consecutive-day streak (milestones.streak_days)
  domains  — distinct life-domains lit (len milestones.domains)
  skins/emblems/heads/items/carriers/auras — count of that slot collected (earned, ex-freebies)
  total    — total cosmetics earned (ex-freebies)

Reward = (slot, key) into the cosmetic key-space (core/pet.py SKINS/EMBLEMS/…).
Exposed (+ per-user progress) via GET /api/pet/milestones; granted by
pet.check_unlocks on every completion event.
"""
from core import pet as _pet

# (slot, key, label, metric, threshold) — order = display order (easy → hard).
_M = [
    # ── 累计捕捉(capture) ─────────────────────────────────────────────
    ("cap_10",   "emblem",  "star",     "捕捉 10 条",   "capture", 10),
    ("cap_25",   "item",    "book",     "捕捉 25 条",   "capture", 25),
    ("cap_50",   "head",    "safari",   "捕捉 50 条",   "capture", 50),
    ("cap_100",  "head",    "crown",    "捕捉 100 条",  "capture", 100),     # legendary · exclusive
    ("cap_250",  "skin",    "ember",    "捕捉 250 条",  "capture", 250),
    ("cap_500",  "aura",    "ember",    "捕捉 500 条",  "capture", 500),
    ("cap_1000", "carrier", "board",    "捕捉 1000 条", "capture", 1000),
    # ── 连续记录(streak) ──────────────────────────────────────────────
    ("st_3",     "emblem",  "plus",     "连续 3 天",    "streak", 3),
    ("st_7",     "item",    "coin",     "连续 7 天",    "streak", 7),
    ("st_14",    "skin",    "bubble",   "连续 14 天",   "streak", 14),       # legendary · exclusive
    ("st_30",    "head",    "antenna",  "连续 30 天",   "streak", 30),
    ("st_60",    "aura",    "azure",    "连续 60 天",   "streak", 60),
    ("st_100",   "carrier", "disc",     "连续 100 天",  "streak", 100),
    # ── 点亮领域(domains) ─────────────────────────────────────────────
    ("dom_1",    "emblem",  "leaf",     "点亮 1 个领域", "domains", 1),
    ("dom_2",    "item",    "flower",   "点亮 2 个领域", "domains", 2),
    ("dom_3",    "head",    "sprout",   "点亮 3 个领域", "domains", 3),
    ("dom_4",    "skin",    "lime",     "点亮 4 个领域", "domains", 4),
    ("dom_5",    "carrier", "pad",      "点亮 5 个领域", "domains", 5),
    ("dom_6",    "aura",    "verdant",  "点亮 6 个领域", "domains", 6),
    ("dom_8",    "skin",    "gold",     "点亮全部 8 个领域", "domains", 8),  # legendary · exclusive
    # ── 收集身色(skins) ───────────────────────────────────────────────
    ("sk_3",     "emblem",  "heart",    "集齐 3 种身色", "skins", 3),
    ("sk_5",     "item",    "magnify",  "集齐 5 种身色", "skins", 5),
    ("sk_8",     "aura",    "rainbow",  "集齐 8 种身色", "skins", 8),         # legendary · exclusive
    ("sk_10",    "head",    "horns",    "集齐全部 10 种身色", "skins", 10),
    # ── 收集徽记(emblems) ─────────────────────────────────────────────
    ("em_3",     "item",    "umbrella", "集齐 3 种徽记", "emblems", 3),
    ("em_5",     "skin",    "mint",     "集齐 5 种徽记", "emblems", 5),
    ("em_7",     "aura",    "magenta",  "集齐全部 7 种徽记", "emblems", 7),
    # ── 收集头饰(heads) ───────────────────────────────────────────────
    ("hd_3",     "item",    "dumbbell", "集齐 3 种头饰", "heads", 3),
    ("hd_6",     "skin",    "aurora",   "集齐全部 6 种头饰", "heads", 6),
    # ── 收集手持(items) ───────────────────────────────────────────────
    ("it_3",     "emblem",  "drop",     "集齐 3 种手持", "items", 3),
    ("it_6",     "aura",    "cyan",     "集齐 6 种手持", "items", 6),
    ("it_9",     "carrier", "cloud",    "集齐全部 9 种手持", "items", 9),
    # ── 收集承载(carriers) ────────────────────────────────────────────
    ("cr_3",     "emblem",  "bolt",     "集齐 3 种承载", "carriers", 3),
    ("cr_5",     "aura",    "frost",    "集齐全部 5 种承载", "carriers", 5),
    # ── 收集光环(auras) ───────────────────────────────────────────────
    ("au_3",     "emblem",  "ring",     "集齐 3 种光环", "auras", 3),
    ("au_6",     "item",    "laptop",   "集齐 6 种光环", "auras", 6),
    ("au_8",     "carrier", "ring",     "集齐全部 8 种光环", "auras", 8),    # legendary · exclusive
    # ── 总收藏(total) ─────────────────────────────────────────────────
    ("tot_10",   "item",    "pen",      "收集 10 件装饰", "total", 10),
    ("tot_25",   "skin",    "coral",    "收集 25 件装饰", "total", 25),
    ("tot_40",   "skin",    "ocean",    "收集 40 件装饰", "total", 40),
]

MILESTONES = [
    {"key": k, "reward_slot": s, "reward_key": rk, "label": lbl,
     "metric": m, "threshold": t, "tier": _pet.tier_of(s, rk),
     "exclusive": (s, rk) in _pet.EXCLUSIVE_KEYS}
    for (k, s, rk, lbl, m, t) in _M
]

# Drop-EXCLUSIVE rewards (the 5 endgame keys, owned by core/pet.py) — removed from
# the random drop pool so the ONLY way to earn them is the milestone. Everything
# else is additive (also droppable).
EXCLUSIVE_KEYS = set(_pet.EXCLUSIVE_KEYS)


def metric_value(metric: str, milestones: dict, unlocked: dict) -> int:
    """Current value of a milestone metric, from the pet's stored progress."""
    ms = milestones or {}
    un = unlocked or {}

    def _earned(slot: str) -> int:
        free = set((_pet.FREE.get(slot) or []))
        return len([x for x in set(un.get(slot, [])) if x not in free])

    if metric == "capture":  return int(ms.get("capture_count", 0))
    if metric == "streak":   return int(ms.get("streak_days", 0))
    if metric == "domains":  return len(ms.get("domains") or [])
    if metric in ("skins", "emblems", "heads", "items", "carriers", "auras"):
        return _earned(metric[:-1])          # 'skins' → 'skin'
    if metric == "total":
        return sum(_earned(s) for s in ("skin", "emblem", "head", "item", "carrier", "aura"))
    return 0


def progress(milestones: dict, unlocked: dict) -> list[dict]:
    """Every milestone + this pet's progress — the GET /api/pet/milestones payload."""
    out = []
    for m in MILESTONES:
        cur = metric_value(m["metric"], milestones, unlocked)
        owned = m["reward_key"] in set((unlocked or {}).get(m["reward_slot"], []))
        out.append({
            **m,
            "current": min(cur, m["threshold"]),
            "achieved": cur >= m["threshold"],
            "reward_owned": owned,
        })
    return out
