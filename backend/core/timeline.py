"""
Timeline assembly — Phase B v1.4.x.

Note on rendering: this module is the source of the `title` / `subtitle`
strings shown in calendar bullets + the "/api/timeline" feed. Field values
are passed through `_format_value` so an ISO datetime in the primary slot
reads as "5月30日 08:00" instead of "2026-05-30T08:00:00+08:00". Mirrors
the auto-format in frontend/src/lib/format.ts applyFormat().

Powers the「全部」filter tab in CalendarPage's Schedule view (per design
DESIGN.md §5.2 + Phase B §八). NOT a standalone page — just the data source
for that one tab.

Two concepts kept distinct:
- `created_at`     —— when the row was written to DB (audit / debug)
- `effective_at`   —— when the entity is meaningful on a user-facing timeline
                      (driven by content semantics, not row-write time)

Per-kind effective_at rule (table also lives in phase-b doc §三):

  event             →  start_at
  todo asset        →  payload.due_date  | else created_at
  expense asset     →  payload.date       | else created_at
  idea/notes/misc   →  created_at
  contact asset     →  created_at
  input_turn        →  created_at  (flash: capture moment; async ASR: completion)
  file              →  created_at  (upload moment)

The 「全部」 tab shows every kind interleaved by effective_at. Concrete-kind
tabs (event / todo / expense / ...) typically use their own endpoints with
richer per-type data (event tab needs end_at + attendees; todo tab needs
status groupings; etc.) — assemble_timeline is the unified-merge code path.
"""
from datetime import datetime, timedelta, timezone

# The app's canonical user timezone (Asia/Shanghai). Naive datetime strings on the
# timeline (LLM-emitted due_date / expense date, or manual entries) are Beijing
# WALL-CLOCK times — assuming UTC would shift them −8h onto the wrong day (e.g.
# a todo due "今天 17:00" → 17:00 UTC → 01:00 次日 Beijing).
_BEIJING = timezone(timedelta(hours=8))
from typing import Optional, Any

# Tz-aware sentinel for sort fallback (datetime.min is naive — incompatible
# with offset-aware values parsed from ISO8601)
_EPOCH_MIN = datetime(1, 1, 1, tzinfo=timezone.utc)

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from db.models import (
    Asset, UserSkill, GlobalSkill, Event, InputTurn, File, Contact,
)


# ── effective_at per kind ─────────────────────────────────────────────────────

def _parse_iso(s: Any) -> Optional[datetime]:
    """
    Parse an ISO8601 string into a tz-aware datetime; return None on failure.
    If the string lacks a timezone offset, assume **Beijing (+08:00)** — naive
    times in this app are Beijing wall-clock (LLM-emitted due_date / expense date,
    or manual entry). Assuming UTC mis-dates them by 8h onto the wrong day.
    (A real `datetime` object reaching here is an ORM column = already UTC-aware.)
    """
    if isinstance(s, datetime):
        # Already a datetime (ORM column) — coerce to aware-UTC if somehow naive.
        return s if s.tzinfo else s.replace(tzinfo=timezone.utc)
    if not s or not isinstance(s, str):
        return None
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=_BEIJING)   # naive string = Beijing wall-clock
    return dt


def effective_at_for_asset(asset: Asset, skill_name: str,
                           render_spec: Optional[dict] = None) -> datetime:
    """Compute effective_at for an asset based on its skill type + payload.

    Per-skill time anchor (发生型 skill): a skill may declare
    `render_spec.timeline_anchor = "<payload field>"` — the field that holds
    when the thing *happened* (a 球赛 played on 6/5, a workout done yesterday).
    When present and parseable it wins, so a match recorded today lands on its
    play date in 流 instead of today. Pure record skills (notes/灵感) declare no
    anchor → created_at, unchanged. todo/expense keep their built-in anchors.
    """
    payload = asset.payload or {}
    # §4.5.0a: user stated a clock time → occurred_at is the precise moment and
    # wins over every payload-derived anchor (it's exactly "when it happened").
    if getattr(asset, "occurred_at", None):
        return asset.occurred_at
    rs = render_spec if isinstance(render_spec, dict) else {}
    anchor = rs.get("timeline_anchor")
    if anchor:
        dt = _parse_iso(payload.get(anchor))
        if dt:
            return dt
    if skill_name == "todo":
        return _parse_iso(payload.get("due_date")) or asset.created_at
    if skill_name == "expense":
        # Legacy compatibility: older expense prompts wrote payload.at, including
        # fuzzy period canonical clocks. New writes use Asset.occurred_at/period
        # instead; keep reading `at` only so historical rows keep their order.
        return (_parse_iso(payload.get("at"))
                or _parse_iso(payload.get("date"))
                or asset.created_at)
    # idea / notes / misc / contact / (no-anchor custom) — created_at by default
    return asset.created_at


def effective_at_for_event(event: Event) -> datetime:
    return event.start_at


def _todo_due_has_clock(payload: dict) -> bool:
    """Whether a todo deadline contains a user-facing clock component.

    ``effective_at`` may fall back to ``created_at`` for sorting, so its hour is
    not evidence that the user scheduled the todo. A date-only deadline remains
    unscheduled; any ISO datetime (including midnight) is an explicit time.
    """
    due = payload.get("due_date")
    return isinstance(due, str) and "T" in due


def effective_at_for_input_turn(turn: InputTurn) -> datetime:
    """
    For flash: capture moment (= created_at when ASR is sync/inline).
    For async ASR (meeting): row created when ASR completed (= created_at also).
    Same field in both cases.
    """
    return turn.created_at


def effective_at_for_file(file: File) -> datetime:
    return file.created_at


# ── TimelineItem shape ────────────────────────────────────────────────────────
# Plain dicts (not a class) for direct JSON serialization. Frontend renders
# based on `kind`. Fields not relevant to a kind are simply omitted.
#
# Common keys:
#   kind:          "asset" | "event" | "input_turn" | "file"
#   id:            uuid
#   effective_at:  ISO8601 + TZ
#   created_at:    ISO8601 + TZ (for stable tie-break ordering)
#   title:         display title
#   subtitle:      optional secondary text
#   session_id:    if applicable
#
# Kind-specific:
#   asset:        skill_name, payload, source_input_turn_id
#   event:        event_id, end_at, location, attendees_count, files_count
#   input_turn:   source (voice/typed/imported), text_snippet, derived_count
#   file:         source_tag, file_type, asr_status


def _iso(dt: Optional[datetime]) -> Optional[str]:
    return dt.isoformat() if dt else None


import re

_ISO_DT_RE   = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$")
_ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

def _format_value(raw) -> str:
    """
    Stringify a payload value for display in calendar bullets.

    Auto-formats anything that looks like an ISO timestamp into 「月日 HH:MM」
    so the user doesn't see "2026-05-30T08:00:00+08:00" on the timeline.
    Other types pass through unchanged.
    """
    if raw is None:
        return ""
    s = str(raw)
    if _ISO_DT_RE.match(s):
        dt = _parse_iso(s)
        if dt:
            return f"{dt.month}月{dt.day}日 {dt.hour:02d}:{dt.minute:02d}"
    if _ISO_DATE_RE.match(s):
        try:
            y, m, d = s.split("-")
            return f"{int(m)}月{int(d)}日"
        except ValueError:
            return s
    return s


# Units were dropped per May audit (Option B). The title / subtitle are
# just the formatted value — users embed units in the value themselves
# when relevant ("150 毫升", "5 km"). Keeps multi-modal skills sane.


def _asset_item(asset: Asset, skill_name: str, render_spec: Optional[dict] = None, display_name: Optional[str] = None) -> dict:
    p = asset.payload or {}
    # Title: prefer the skill's render_spec.primary_field (matches how the card
    # renders), then common title-ish fields, then the skill's display_name.
    # Never fall back to "[skill_name]" — AI-created skills with custom payloads
    # (e.g. 跑步记录 {distance, pace}) used to surface an ugly "[running]".
    #
    # Measurement skills (跑步 distance=5, 喝水 ml=200) used to surface as
    # the bare number "5". Bundle C added primary_label / primary_unit to
    # render_spec for cards; apply the same decoration here so the calendar
    # bullet reads "距离 5 km" instead of "5". Single source of rendering
    # rule for the timeline: <label?> <value> <unit?>.
    rs = render_spec if isinstance(render_spec, dict) else {}
    pf = rs.get("primary_field")
    pf_val = p.get(pf) if pf else None
    primary_str: Optional[str] = _format_value(pf_val) if pf_val not in (None, "") else None
    title = (
        primary_str or
        p.get("content") or p.get("title") or p.get("name") or
        (f"¥{p.get('amount')}" if p.get("amount") else None) or
        display_name or skill_name
    )
    sf = rs.get("secondary_field")
    sf_val = p.get(sf) if sf else None
    if sf_val not in (None, ""):
        subtitle = _format_value(sf_val)
    else:
        subtitle = p.get("description") or p.get("merchant") or ""
    return {
        "kind":                 "asset",
        "id":                   str(asset.id),
        "effective_at":         _iso(effective_at_for_asset(asset, skill_name, render_spec)),
        "created_at":           _iso(asset.created_at),
        # §4.5.0a 落段信号:period = user 只说了模糊时段; has_clock_time = user 说了
        # 钟点(occurred_at 已 set,effective_at 即该精确时刻)。两者皆无 = 捕捉兜底。
        "period":               getattr(asset, "period", None) or "",
        "has_clock_time":       getattr(asset, "occurred_at", None) is not None,
        # Distinct from effective_at: a no-deadline todo sorts by created_at but
        # must still render in 待安排, never at its capture clock time.
        "has_scheduled_time":   (
            getattr(asset, "occurred_at", None) is not None
            or (skill_name == "todo" and _todo_due_has_clock(p))
        ),
        # §8 生活领域(工作/学习/健康/运动/社交/娱乐/生活/灵感)— drives the 流/月 卡片领域 tag.
        "domain":               getattr(asset, "domain", None) or "",
        "title":                str(title)[:120],
        "subtitle":             str(subtitle)[:120],
        "skill_name":           skill_name,
        "session_id":           str(asset.session_id) if asset.session_id else None,
        "source_input_turn_id": str(asset.source_input_turn_id) if asset.source_input_turn_id else None,
        "payload":              p,
    }


def _event_item(event: Event) -> dict:
    return {
        "kind":                 "event",
        "id":                   str(event.id),
        "effective_at":         _iso(effective_at_for_event(event)),
        "created_at":           _iso(event.created_at),
        "title":                event.title,
        "subtitle":             event.location or "",
        "event_id":             str(event.id),
        "end_at":               _iso(event.end_at),
        "location":             event.location,
        "all_day":              bool(event.all_day),
        "source_input_turn_id": str(event.source_input_turn_id) if event.source_input_turn_id else None,
    }


def _input_turn_item(turn: InputTurn, derived: Optional[dict] = None) -> dict:
    text = turn.text or ""
    derived = derived or {}
    return {
        "kind":          "input_turn",
        "id":            str(turn.id),
        "effective_at":  _iso(effective_at_for_input_turn(turn)),
        "created_at":    _iso(turn.created_at),
        "title":         text[:80] + ("…" if len(text) > 80 else ""),
        "subtitle":      "",
        "source":        turn.source,
        "session_id":    str(turn.session_id) if turn.session_id else None,
        "file_id":       str(turn.file_id) if turn.file_id else None,
        # What this capture produced, keyed by skill_name | "event" | "contact".
        # Powers the timeline ⚡ summary ("待办 ×2 · 联系人 ×1").
        "derived":       derived,
        "derived_total": sum(derived.values()),
    }


def _contact_item(contact: Contact) -> dict:
    """Timeline item for a contact (名片). Contacts are a first-class entity in
    their own table — they were missing from the timeline entirely, so a newly
    added 名片 never showed in 流 / 月 views. effective_at = created_at (a
    contact isn't scheduled; it's "when I added this person")."""
    role    = (contact.title or "").strip()      # job title
    company = (contact.company or "").strip()
    subtitle = " · ".join(x for x in (role, company) if x)
    return {
        "kind":         "contact",
        "id":           str(contact.id),
        "contact_id":   str(contact.id),
        "effective_at": _iso(contact.created_at),
        "created_at":   _iso(contact.created_at),
        "title":        (contact.name or "联系人")[:120],
        "subtitle":     subtitle[:120],
        # skill_name lets the frontend's subKindOf / DayDetailSheet grouping
        # bucket it as 名片 (they switch on skill_name === "contact").
        "skill_name":   "contact",
        "payload": {
            "name":    contact.name,
            "phone":   contact.phone,
            "company": company,
            "title":   role,
            "email":   contact.email,
            "notes":   contact.notes or [],
        },
    }


def _file_item(file: File) -> dict:
    kind_label = "🎙 闪念录音" if file.source_tag == "flash" else (
                 "📁 会议录音" if file.source_tag == "meeting" else "📎 文件")
    return {
        "kind":         "file",
        "id":           str(file.id),
        "effective_at": _iso(effective_at_for_file(file)),
        "created_at":   _iso(file.created_at),
        "title":        kind_label,
        "subtitle":     f"{file.file_type or ''} · {file.duration_sec or 0}s",
        "file_id":      str(file.id),
        "source_tag":   file.source_tag,
        "asr_status":   file.asr_status,
    }


# ── derived breakdown (flash capture → what it produced) ──────────────────────

async def _derived_breakdown(db: AsyncSession, user_id: str, turn_ids: list) -> dict:
    """Count what each flash input_turn produced — assets (by skill name),
    events, contacts — keyed by source_input_turn_id.

    Returns {turn_id: {<key>: count}} where key ∈ skill_name | "event" |
    "contact". Three grouped queries; empty input → {}.
    """
    if not turn_ids:
        return {}
    out: dict = {}

    def _bump(tid, key, cnt):
        if tid is None:
            return
        k = str(tid)
        out.setdefault(k, {})
        out[k][key] = out[k].get(key, 0) + int(cnt)

    # assets grouped by (turn, skill_name)
    rows = (await db.execute(
        select(Asset.source_input_turn_id, GlobalSkill.name, func.count())
        .join(UserSkill, Asset.user_skill_id == UserSkill.id)
        .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
        .where(Asset.user_id == user_id, Asset.source_input_turn_id.in_(turn_ids))
        .group_by(Asset.source_input_turn_id, GlobalSkill.name)
    )).all()
    for tid, skill, cnt in rows:
        _bump(tid, skill, cnt)

    # events grouped by turn
    rows = (await db.execute(
        select(Event.source_input_turn_id, func.count())
        .where(Event.user_id == user_id, Event.source_input_turn_id.in_(turn_ids))
        .group_by(Event.source_input_turn_id)
    )).all()
    for tid, cnt in rows:
        _bump(tid, "event", cnt)

    # contacts grouped by turn (provenance column added in migration 0003)
    rows = (await db.execute(
        select(Contact.source_input_turn_id, func.count())
        .where(Contact.user_id == user_id, Contact.source_input_turn_id.in_(turn_ids))
        .group_by(Contact.source_input_turn_id)
    )).all()
    for tid, cnt in rows:
        _bump(tid, "contact", cnt)

    return out


# ── Public: assemble_timeline ─────────────────────────────────────────────────

async def assemble_timeline(
    db: AsyncSession,
    user_id: str,
    from_dt: Optional[datetime] = None,
    to_dt:   Optional[datetime] = None,
    kinds:   Optional[set] = None,        # subset of {"asset", "event", "contact", "input_turn", "file"}
    skill_names: Optional[set] = None,    # restrict asset kind to specific skills
    limit: int = 500,
) -> list:
    """
    Assemble a unified, time-sorted list of TimelineItems for the 「全部」 tab.

    Strategy: brute-query each table within (or near) the window, compute
    effective_at in app code, filter strictly, then merge-sort. For demo
    scale this is fine; for large data, push effective_at into SQL via
    GENERATED columns or CTE.
    """
    kinds = kinds or {"asset", "event", "contact", "input_turn", "file"}
    items: list = []

    # ── assets (joined to skill name) ──
    if "asset" in kinds:
        stmt = (
            select(Asset, GlobalSkill.name.label("skill_name"), UserSkill.render_spec, UserSkill.display_name)
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.user_id == user_id)
        )
        if skill_names:
            stmt = stmt.where(GlobalSkill.name.in_(skill_names))
        rows = (await db.execute(stmt)).all()
        for asset, skill_name, render_spec, display_name in rows:
            items.append(_asset_item(asset, skill_name, render_spec, display_name))

    # ── events ──
    if "event" in kinds:
        stmt = select(Event).where(Event.user_id == user_id)
        events = (await db.execute(stmt)).scalars().all()
        for ev in events:
            items.append(_event_item(ev))

    # ── contacts (first-class entity in its own table) ──
    if "contact" in kinds:
        contacts = (await db.execute(
            select(Contact).where(Contact.user_id == user_id)
        )).scalars().all()
        for c in contacts:
            items.append(_contact_item(c))

    # ── input_turns ──
    # Filter rule: typed inputs are "AI conversation history", not "life
    # events" → exclude from timeline. The DERIVED assets (todo / event /
    # ...) still appear, they're the real records. Voice and (future)
    # imported turns stay on timeline because they represent captured
    # moments in the user's life.
    if "input_turn" in kinds:
        stmt = select(InputTurn).where(
            InputTurn.user_id == user_id,
            InputTurn.source != "typed",
        )
        turns = (await db.execute(stmt)).scalars().all()
        breakdown = await _derived_breakdown(db, user_id, [str(t.id) for t in turns])
        for t in turns:
            items.append(_input_turn_item(t, breakdown.get(str(t.id))))

    # ── files ──
    if "file" in kinds:
        stmt = select(File).where(File.user_id == user_id)
        files = (await db.execute(stmt)).scalars().all()
        for f in files:
            items.append(_file_item(f))

    # ── window filter ──
    if from_dt or to_dt:
        def in_window(it):
            ea = _parse_iso(it.get("effective_at"))
            if ea is None:
                return False
            if from_dt and ea < from_dt:
                return False
            if to_dt and ea > to_dt:
                return False
            return True
        items = [it for it in items if in_window(it)]

    # ── sort: effective_at desc(newest first); tie-break by created_at desc ──
    def sort_key(it):
        ea = _parse_iso(it.get("effective_at")) or _EPOCH_MIN
        ca = _parse_iso(it.get("created_at"))   or _EPOCH_MIN
        return (ea, ca)
    items.sort(key=sort_key, reverse=True)

    return items[:limit]
