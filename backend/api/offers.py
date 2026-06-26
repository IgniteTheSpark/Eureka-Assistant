"""
/api/offers — §14.5a PULL = 现算 comprehensive offer set (on-demand).

  GET /api/offers/today — the COMPREHENSIVE current-state offer set, computed NOW
                          and NOT subject to the push ≤2/day throttle (§14.8 is
                          PUSH-only). Backs the Reka Offer screen (mobile/lib/
                          today/reka_offer.dart).

PULL vs PUSH (the load-bearing reconciliation):
- PUSH (core/companion.scan_once → /api/nudges/pending) is the heartbeat feed:
  throttled to ≤2/day, quiet-hours-gated, today-only, capped at 10.
- PULL (here) recomputes EVERYTHING valid right now — accumulation offers PLUS
  逾期待办 + 无时间习惯 — UPSERTs each into a Nudge (find-or-create by
  user_id + natural_key, idempotent) so every card has a stable id, then EXCLUDES
  anything the user已 acted / dismissed TODAY (Beijing). 执行(右滑→acted)/跳过
  (左滑→dismissed) go through the SAME POST /api/nudges/{id}/outcome by id.

Returned JSON is the SAME shape as GET /api/nudges/pending (it reuses nudges._ser),
so the existing RekaNudge.fromJson parses it unchanged.
"""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select

from api.nudges import _ser
from core.auth import get_current_user_id
from core.companion import OfferCandidate, compute_offer_candidates, _nudges_enabled
from db.database import AsyncSessionLocal
from db.models import Nudge, User

router = APIRouter()

_BEIJING = timezone(timedelta(hours=8))


def _bj_date(dt: datetime | None):
    """Beijing calendar date of an (aware/naive-UTC) timestamp, or None."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(_BEIJING).date()


@router.get("/offers/today")
async def offers_today(user_id: str = Depends(get_current_user_id)):
    """§14.5a — recompute the comprehensive offer set NOW and return it (NO
    §14.8 throttle; that's push-only). Idempotent: re-PULL upserts by natural_key
    so it never duplicates, and excludes offers acted/dismissed today."""
    now = datetime.now(timezone.utc)
    today_bj = now.astimezone(_BEIJING).date()

    async with AsyncSessionLocal() as db:
        user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
        # §14.8 master switch governs ALL proactive surfaces (not a throttle) — if
        # the user turned REKA off, the PULL view is empty too.
        if not _nudges_enabled(user):
            return {"ok": True, "nudges": []}

        cands: list[OfferCandidate] = await compute_offer_candidates(db, user_id, now)

        out: list[Nudge] = []
        seen_keys: set[tuple[str, str]] = set()
        for c in cands:
            key = (c.kind, c.ref)
            if key in seen_keys:
                continue  # defensive: never emit the same natural_key twice
            seen_keys.add(key)

            # find-or-create by user_id + natural_key ((kind, ref)) — idempotent so
            # re-PULL reuses the row (and its id) instead of duplicating.
            n = (await db.execute(
                select(Nudge).where(
                    Nudge.user_id == user_id, Nudge.kind == c.kind, Nudge.ref == c.ref)
                .order_by(Nudge.created_at.desc()).limit(1)
            )).scalar_one_or_none()

            if n is None:
                n = Nudge(
                    user_id=user_id, type=c.type, kind=c.kind,
                    text=c.text, body=c.body, ref=c.ref, cta=c.cta,
                    status="pending", source="pull",
                    delivered_at=now,
                    expires_at=(now + timedelta(hours=c.ttl_hours)) if c.ttl_hours else None,
                )
                db.add(n)
            else:
                # already acted on → respect it; don't re-offer something done.
                if n.status == "acted":
                    continue
                # dismissed/ignored/expired from a PRIOR Beijing day, but the
                # candidate recomputed as valid today → revive to pending + refresh
                # the (template) copy. A SAME-DAY dismissal is handled by the filter
                # below (stays dismissed, excluded from this response).
                if _bj_date(n.dismissed_at) == today_bj:
                    continue  # 左滑跳过 today → keep skipped for the day
                if n.status in ("dismissed", "ignored", "expired"):
                    n.status = "pending"
                    n.dismissed_at = None
                # keep copy fresh (counts/over-days drift day to day)
                n.text, n.body, n.cta, n.type = c.text, c.body, c.cta, c.type
                if c.ttl_hours:
                    n.expires_at = now + timedelta(hours=c.ttl_hours)

            out.append(n)

        await db.commit()
        for n in out:
            await db.refresh(n)
        # exclude anything dismissed today (covers rows just revived above being
        # re-dismissed within the same request is impossible, but a row dismissed
        # earlier today via the ball peek must not reappear here).
        payload = [_ser(n) for n in out
                   if _bj_date(n.dismissed_at) != today_bj and n.status != "acted"]

    return {"ok": True, "nudges": payload}
