"""
Tool implementations backed by PostgreSQL — Phase B Step 2.

Called by mcp_server/server.py (the FastMCP server agents connect to via stdio).
Can also be imported directly during transitional steps; production callers
should go through MCP.

Changes from previous version (Step 2 design integration):
- create_asset/query_asset use `user_skill_name` (replaces `asset_type`)
- create_asset takes `source_input_turn_id` (replaces `input_id`)
- Removed VALID_ASSET_TYPES hardcoded set; user_skills registry is the source
  of truth — unregistered skill = error
- Asset payload no longer carries asset_type (type derived via FK chain)
- New: query_input_turn, get_input_turn for transcript retrieval
- Renamed _get_user_skill → _resolve_user_skill for clarity
"""
import json
import uuid

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, Text

from db.models import (
    Asset, AssetField, Contact, UserSkill, GlobalSkill, InputTurn,
    Event, EventAttendee, EventFile,                                  # v1.4
)
from db.queries import index_asset_fields
from db.database import AsyncSessionLocal
from core.domains import normalize_domain, prior_for_skill
from core.completion import emit_completion_event   # §9 pet currency (best-effort)
from core.contacts_meta import (
    SUPPORTED_SOCIALS, clean_socials, merge_socials, notes_to_list, append_notes,
)


# ── Helpers ────────────────────────────────────────────────────────────────────

async def _resolve_user_skill(db: AsyncSession, user_id: str, user_skill_name: str):
    """
    Look up the UserSkill row for (user_id, GlobalSkill.name = user_skill_name).
    Returns None if the user has not registered this skill.
    """
    result = await db.execute(
        select(UserSkill)
        .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
        .where(UserSkill.user_id == user_id, GlobalSkill.name == user_skill_name)
    )
    return result.scalar_one_or_none()


def _ok(**kwargs):
    return {"ok": True, **kwargs}


def _err(msg: str):
    return {"ok": False, "error": msg}


# ── Asset tools ────────────────────────────────────────────────────────────────

_PERIODS = {"凌晨", "上午", "中午", "下午", "晚上"}


def _norm_period(p: str) -> "str | None":
    p = (p or "").strip()
    return p if p in _PERIODS else None


def _parse_occurred(s: str):
    from datetime import datetime  # module has no top-level datetime import
    s = (s or "").strip()
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


async def create_asset(
    user_skill_name: str,
    payload: str,
    session_id: str = "",
    source_input_turn_id: str = "",
    domain: str = "",
    user_id: str = "default",
    period: str = "",
    occurred_at: str = "",
    created_at: str = "",
) -> dict:
    """
    Create an asset under a registered skill, and index its queryable fields.

    The skill MUST be registered in user_skills for this user — agent should not
    invent new skill names. Use the add-skill flow (POST /api/skills + design
    agent) to register new skills.

    domain (§8): optional life-domain label (工作/学习/健康/运动/社交/娱乐/生活/灵感).
    Agent passes it by CONTENT when it can tell ("交报告"→工作, "买菜"→生活). When
    omitted/invalid, the service falls back to the skill's prior, else null.

    period / occurred_at (§4.5.0a 落段) — fill ONLY when the user stated a time:
      · 说了钟点("下午3点")→ occurred_at = ISO8601+08:00 精确时刻 (+ period 推出来);
      · 只说了模糊时段("早上")→ period ∈ 凌晨/上午/中午/下午/晚上;
      · 没说时间 → 两个都留空(前端按捕捉时刻 created_at 兜底落段)。不要臆造。
    """
    try:
        payload_dict = json.loads(payload) if isinstance(payload, str) else payload
    except json.JSONDecodeError as e:
        return _err(f"invalid payload JSON: {e}")
    if not isinstance(payload_dict, dict):
        return _err("payload must be a JSON object")

    async with AsyncSessionLocal() as db:
        user_skill = await _resolve_user_skill(db, user_id, user_skill_name)
        if not user_skill:
            return _err(f"skill not registered for user: {user_skill_name}")

        # §8 domain resolution: explicit (by content) → per-skill prior
        # (user_skills.domain) → base prior (machine_name) → 「生活」兜底。
        # 产品决策 2026-06:每条记录都打一个域(永不 null),流/月的领域 tag 才一致;
        # agent 提示已要求必打,这里是最后的安全网(qa/event 不走此路、不受影响)。
        resolved_domain = (
            normalize_domain(domain)
            or normalize_domain(user_skill.domain)
            or prior_for_skill(user_skill_name)
            or "生活"
        )

        asset = Asset(
            user_id=user_id,
            user_skill_id=user_skill.id,
            session_id=uuid.UUID(session_id) if session_id else None,
            source_input_turn_id=uuid.UUID(source_input_turn_id) if source_input_turn_id else None,
            payload=payload_dict,
            domain=resolved_domain,
            period=_norm_period(period),
            occurred_at=_parse_occurred(occurred_at),
        )
        # 「在这天记一笔」: 显式 created_at → 锚到那天(记录类资产 effective_at=created_at,
        # 否则会落到今天)。占位 todo/expense 仍由各自 due_date/date 决定 effective_at。
        _ca = _parse_occurred(created_at)
        if _ca:
            asset.created_at = _ca
        db.add(asset)
        await db.flush()  # populate asset.id before indexing

        await index_asset_fields(db, asset.id, user_id, user_skill.id, payload_dict)

        await db.commit()

    # §9: a logged record is a closed loop → feed the 球球 (best-effort, never blocks).
    await emit_completion_event(user_id, "record", str(asset.id), resolved_domain)

    return _ok(
        asset_id=str(asset.id),
        user_skill_name=user_skill_name,
        payload=payload_dict,
        domain=resolved_domain,
        created_at=asset.created_at.isoformat() if asset.created_at else None,
    )


# ── Dedicated typed create tools for the systemic built-in skills (§1.2) ──────
# todo / 随记 are 常驻 skills with fixed schemas. Typed create tools (vs the
# generic create_asset's double-layer JSON-string payload) cut a whole class of
# LLM call errors. Storage stays UNIFIED in `assets` — these just build the
# payload then delegate to create_asset, so asset_fields indexing / provenance
# are identical. update/delete/query stay generic (by asset_id / query_asset).

async def create_todo(
    content: str,
    due_date: str = "",
    session_id: str = "",
    source_input_turn_id: str = "",
    domain: str = "",
    user_id: str = "default",
    period: str = "",
    occurred_at: str = "",
) -> dict:
    """Create a 待办 (todo) asset.

    due_date: concrete deadline only — ISO8601+08:00 (with time), 'YYYY-MM-DD'
    (date only), or '' (none). Do not turn fuzzy periods like "下午" into a fake
    due_date time.
    period / occurred_at (§4.5.0a): "下午" without a clock → period="下午",
    occurred_at=""; "下午3点" → occurred_at=<ISO8601+08:00> (+ period).
    domain (§8): tag by content ("交报告"→工作, "买菜"→生活); omit if unsure.
    """
    payload: dict = {"title": content, "content": content, "status": "pending"}
    if due_date and due_date.strip():
        payload["due_date"] = due_date.strip()
    return await create_asset(
        user_skill_name="todo",
        payload=payload,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        domain=domain,
        user_id=user_id,
        period=period,
        occurred_at=occurred_at,
    )


async def create_note(
    content: str,
    title: str = "",
    tags: str = "",
    session_id: str = "",
    source_input_turn_id: str = "",
    domain: str = "",
    user_id: str = "default",
) -> dict:
    """Create a 随记 (free-text catch-all) asset. tags: comma-separated open
    topic tags (≤3 kept), e.g. '天气,心情'. domain (§8): defaults to 灵感 when
    omitted; pass another domain only if the content clearly belongs elsewhere."""
    payload: dict = {"content": content}
    if title and title.strip():
        payload["title"] = title.strip()
    tg = [t.strip() for t in tags.split(",") if t.strip()] if tags else []
    if tg:
        payload["tags"] = tg[:3]
    return await create_asset("notes", payload, session_id, source_input_turn_id, domain, user_id)


async def query_asset(
    user_skill_name: str = "",
    contains: str = "",
    from_date: str = "",
    to_date: str = "",
    domain: str = "",
    limit: int = 100,
    user_id: str = "default",
) -> dict:
    """
    Query assets by skill name, keyword, and/or capture-date range. Newest-first.

    Skill name is resolved via UserSkill → GlobalSkill.name join — no reliance
    on payload.asset_type (that field is gone).

    Date range filters on `created_at` (when the asset was recorded), which is
    what a 日报/周报/月报 means — "things I logged in this window". Pass
    ISO8601 + timezone, e.g. from_date="2026-05-31T00:00:00+08:00",
    to_date="2026-05-31T23:59:59+08:00". **For a whole-day/period SUMMARY,
    leave user_skill_name empty so you get every type (待办 + 想法 + 记账 +
    笔记 + 跑步 + …), not just one.**
    """
    from datetime import datetime
    async with AsyncSessionLocal() as db:
        stmt = (
            select(Asset, GlobalSkill.name.label("skill_name"))
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.user_id == user_id)
        )
        if user_skill_name:
            stmt = stmt.where(GlobalSkill.name == user_skill_name)
        if domain:
            stmt = stmt.where(Asset.domain == domain)
        if contains:
            stmt = stmt.where(Asset.payload.cast(Text).ilike(f"%{contains}%"))
        if from_date:
            try:
                stmt = stmt.where(Asset.created_at >= datetime.fromisoformat(from_date.replace("Z", "+00:00")))
            except ValueError:
                return _err(f"invalid from_date: {from_date}")
        if to_date:
            try:
                stmt = stmt.where(Asset.created_at <= datetime.fromisoformat(to_date.replace("Z", "+00:00")))
            except ValueError:
                return _err(f"invalid to_date: {to_date}")
        stmt = stmt.order_by(Asset.created_at.desc()).limit(limit)
        result = await db.execute(stmt)
        rows = result.all()

    return _ok(assets=[
        {
            "asset_id":             str(a.id),
            "user_skill_name":      skill_name,
            "payload":              a.payload,
            "domain":               a.domain,
            "session_id":           str(a.session_id) if a.session_id else None,
            "source_input_turn_id": str(a.source_input_turn_id) if a.source_input_turn_id else None,
            "created_at":           a.created_at.isoformat(),
        }
        for a, skill_name in rows
    ])


async def query_digest(
    from_date: str = "",
    to_date: str = "",
    domain: str = "",
    user_id: str = "default",
) -> dict:
    """
    Compact, pre-grouped snapshot of a time window — the lean data source for a
    日报/周报/月报 overview (used by the report engine's content skills and by
    chat QUERY for a quick cross-type概况). Returns every asset type captured in
    the range PLUS events, but LEAN: just counts + per-type payload lists + a
    thin event list, with NO per-item metadata (no asset_id / session_id /
    created_at). Small result = fast, cheap, easy to summarize.

    Date range filters asset.created_at and event.start_at; pass ISO8601+tz
    (e.g. "2026-05-31T00:00:00+08:00" .. "2026-05-31T23:59:59+08:00").

    Shape:
      { ok, counts: {<type>: n, ...}, by_type: {<type>: [<payload>, ...]},
        events: [{title, start_at, end_at, location, all_day}, ...] }
    """
    from datetime import datetime

    def _parse(s: str):
        return datetime.fromisoformat(s.replace("Z", "+00:00"))

    async with AsyncSessionLocal() as db:
        a_stmt = (
            select(Asset, GlobalSkill.name.label("skill_name"))
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.user_id == user_id)
        )
        if domain:
            a_stmt = a_stmt.where(Asset.domain == domain)
        if from_date:
            try: a_stmt = a_stmt.where(Asset.created_at >= _parse(from_date))
            except ValueError: return _err(f"invalid from_date: {from_date}")
        if to_date:
            try: a_stmt = a_stmt.where(Asset.created_at <= _parse(to_date))
            except ValueError: return _err(f"invalid to_date: {to_date}")
        a_stmt = a_stmt.order_by(Asset.created_at.asc())
        rows = (await db.execute(a_stmt)).all()

        by_type: dict[str, list] = {}
        for a, skill_name in rows:
            by_type.setdefault(skill_name, []).append(a.payload or {})

        # Events carry no domain column in v1 (§8.1) — a domain-scoped digest
        # excludes them rather than dumping all events into a filtered view.
        events = []
        if not domain:
            e_stmt = select(Event).where(Event.user_id == user_id)
            if from_date:
                try: e_stmt = e_stmt.where(Event.start_at >= _parse(from_date))
                except ValueError: return _err(f"invalid from_date: {from_date}")
            if to_date:
                try: e_stmt = e_stmt.where(Event.start_at <= _parse(to_date))
                except ValueError: return _err(f"invalid to_date: {to_date}")
            e_stmt = e_stmt.order_by(Event.start_at.asc())
            events = (await db.execute(e_stmt)).scalars().all()

    return _ok(
        counts={k: len(v) for k, v in by_type.items()},
        by_type=by_type,
        events=[
            {
                "title":    e.title,
                "start_at": e.start_at.isoformat() if e.start_at else None,
                "end_at":   e.end_at.isoformat() if e.end_at else None,
                "location": e.location,
                "all_day":  e.all_day,
            }
            for e in events
        ],
    )


async def update_asset(
    asset_id: str,
    payload_patch: str,
    user_id: str = "default",
) -> dict:
    """
    Merge payload_patch into existing asset; re-indexes queryable fields.

    Returns user_skill_name alongside asset_id + merged payload so the chat
    frontend's tool_result extractor can pick the right render_spec —
    otherwise updated cards render as a generic 「资产」 (issue #1, May
    audit). create_asset already returns it; we mirror that here.
    """
    try:
        patch = json.loads(payload_patch) if isinstance(payload_patch, str) else payload_patch
    except json.JSONDecodeError as e:
        return _err(f"invalid payload_patch JSON: {e}")
    if not isinstance(patch, dict):
        return _err("payload_patch must be a JSON object")

    async with AsyncSessionLocal() as db:
        # Join through UserSkill → GlobalSkill in one shot so we get the
        # machine name without a second round-trip.
        result = await db.execute(
            select(Asset, GlobalSkill.name.label("skill_name"))
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.id == uuid.UUID(asset_id), Asset.user_id == user_id)
        )
        row = result.first()
        if not row:
            return _err(f"asset not found: {asset_id}")
        asset, skill_name = row

        merged = {**asset.payload, **patch}
        asset.payload = merged
        asset_domain = asset.domain

        # Re-index queryable fields
        await db.execute(
            AssetField.__table__.delete().where(AssetField.asset_id == asset.id)
        )
        await index_asset_fields(db, asset.id, user_id, asset.user_skill_id, merged)

        await db.commit()

    # §9: a todo just completed = a task closed loop → feed the 球球.
    if str(patch.get("status", "")).lower() in ("done", "completed", "complete"):
        await emit_completion_event(user_id, "task", asset_id, asset_domain)

    return _ok(asset_id=asset_id, user_skill_name=skill_name, payload=merged)


async def delete_asset(asset_id: str, user_id: str = "default") -> dict:
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Asset).where(Asset.id == uuid.UUID(asset_id), Asset.user_id == user_id)
        )
        asset = result.scalar_one_or_none()
        if not asset:
            return _err(f"asset not found: {asset_id}")
        await db.delete(asset)
        await db.commit()
    return _ok(asset_id=asset_id)


# ── Contact tools (unchanged from v1) ──────────────────────────────────────────

async def create_contact(
    name: str,
    phone: str = "",
    company: str = "",
    title: str = "",
    email: str = "",
    notes: str = "",
    socials: dict = None,
    source_input_turn_id: str = "",
    user_id: str = "default",
) -> dict:
    if not name:
        return _err("name is required")

    async with AsyncSessionLocal() as db:
        contact = Contact(
            user_id=user_id,
            name=name,
            phone=phone or None,
            company=company or None,
            title=title or None,
            email=email or None,
            notes=[notes] if notes else [],
            socials=clean_socials(socials),  # supported platforms only
            source_input_turn_id=uuid.UUID(source_input_turn_id) if source_input_turn_id else None,
        )
        db.add(contact)
        await db.commit()

    # §9: an opportunistic first-class create (contact = definitionally 社交).
    await emit_completion_event(user_id, "opportunistic", str(contact.id), "社交")

    return _ok(
        contact_id=str(contact.id),
        contact_action="created",
        name=name, phone=phone, company=company,
        title=title, email=email, notes=contact.notes,
        socials=contact.socials,
    )


async def query_contact(name_query: str = "", user_id: str = "default") -> dict:
    async with AsyncSessionLocal() as db:
        stmt = select(Contact).where(Contact.user_id == user_id)
        if name_query:
            stmt = stmt.where(Contact.name.ilike(f"%{name_query}%"))
        stmt = stmt.order_by(Contact.created_at.desc()).limit(50)
        result = await db.execute(stmt)
        contacts = result.scalars().all()

    return _ok(contacts=[
        {"contact_id": str(c.id), "name": c.name, "phone": c.phone,
         "company": c.company, "title": c.title, "email": c.email,
         "notes": notes_to_list(c.notes), "socials": clean_socials(c.socials)}
        for c in contacts
    ])


async def update_contact(
    contact_id: str,
    field: str,
    value: str,
    user_id: str = "default",
) -> dict:
    """
    Update a single field on a contact, return the FULL contact row so the
    chat card renders with the actual name + updated values (May audit:
    previously returned just {field, value} and the chat fell back to a
    generic 「名片」 placeholder with no name).

    field dispatch:
      - "notes"                → APPENDS `value` as a new annotation line (never
                                 replaces existing notes — a contact's history of
                                 "where we met / how I know them" accumulates).
      - a social platform key  → sets that platform's handle (x / telegram /
        (x/telegram/linkedin/    linkedin / wechat / xiaohongshu / instagram),
         wechat/xiaohongshu/     merged onto the rest; blank value unsets it.
         instagram)
      - name/phone/company/    → set the scalar field.
        title/email
    """
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Contact).where(Contact.id == uuid.UUID(contact_id), Contact.user_id == user_id)
        )
        contact = result.scalar_one_or_none()
        if not contact:
            return _err(f"contact not found: {contact_id}")

        if field == "notes":
            contact.notes = append_notes(contact.notes, value)   # append-only
        elif field in SUPPORTED_SOCIALS:
            contact.socials = merge_socials(contact.socials, {field: value})
        elif field in ("name", "phone", "company", "title", "email"):
            setattr(contact, field, value)
        else:
            return _err(f"unknown field: {field} (socials use one of {sorted(SUPPORTED_SOCIALS)})")

        await db.commit()
        await db.refresh(contact)

    return _ok(
        contact_id=contact_id, contact_action="updated",
        field=field, value=value,
        name=contact.name, phone=contact.phone, company=contact.company,
        title=contact.title, email=contact.email,
        notes=contact.notes or [], socials=contact.socials or {},
    )


async def delete_contact(contact_id: str, user_id: str = "default") -> dict:
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Contact).where(Contact.id == uuid.UUID(contact_id), Contact.user_id == user_id)
        )
        contact = result.scalar_one_or_none()
        if not contact:
            return _err(f"contact not found: {contact_id}")
        name = contact.name
        await db.delete(contact)
        await db.commit()
    return _ok(contact_id=contact_id, contact_action="deleted", name=name)


# ── InputTurn tools (NEW: design integration §七) ─────────────────────────────

async def query_input_turn(
    contains: str = "",
    source: str = "",
    limit: int = 50,
    user_id: str = "default",
) -> dict:
    """
    Full-text search input_turns by keyword and/or source (modality).
    source: voice | typed | imported (empty = all modalities)

    Returns text snippets (truncated to 200 chars). Use get_input_turn for full text.
    """
    async with AsyncSessionLocal() as db:
        stmt = select(InputTurn).where(InputTurn.user_id == user_id)
        if source:
            stmt = stmt.where(InputTurn.source == source)
        if contains:
            stmt = stmt.where(InputTurn.text.ilike(f"%{contains}%"))
        stmt = stmt.order_by(InputTurn.created_at.desc()).limit(limit)
        result = await db.execute(stmt)
        turns = result.scalars().all()

    return _ok(input_turns=[
        {
            "input_turn_id": str(t.id),
            "session_id":    str(t.session_id),
            "source":        t.source,
            "snippet":       (t.text[:200] + "…") if len(t.text) > 200 else t.text,
            "full_text_len": len(t.text),
            "file_id":       str(t.file_id) if t.file_id else None,
            "created_at":    t.created_at.isoformat(),
        }
        for t in turns
    ])


async def get_input_turn(input_turn_id: str, user_id: str = "default") -> dict:
    """
    Fetch the full text + segments of a single input_turn.
    Use this for long-form content (meeting transcripts) — they should NOT be
    auto-included in chat history per the §3 decision.
    """
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(InputTurn).where(
                InputTurn.id == uuid.UUID(input_turn_id),
                InputTurn.user_id == user_id,
            )
        )
        turn = result.scalar_one_or_none()
        if not turn:
            return _err(f"input_turn not found: {input_turn_id}")

    return _ok(
        input_turn_id=str(turn.id),
        session_id=str(turn.session_id),
        index=turn.index,
        source=turn.source,
        text=turn.text,
        segments=turn.segments,
        file_id=str(turn.file_id) if turn.file_id else None,
        source_file_offset=turn.source_file_offset,
        asr_provider=turn.asr_provider,
        language=turn.language,
        created_at=turn.created_at.isoformat(),
    )


# ── Event tools (v1.4: Event is a first-class entity) ────────────────────────

def _event_to_dict(event: Event, attendees: list = None, files: list = None) -> dict:
    """Serialize an Event row plus optional joined attendees/files."""
    return {
        "event_id":        str(event.id),
        "title":           event.title,
        "start_at":        event.start_at.isoformat() if event.start_at else None,
        "end_at":          event.end_at.isoformat() if event.end_at else None,
        "all_day":         bool(event.all_day),
        "location":        event.location,
        "description":     event.description,
        "recurrence_rule": event.recurrence_rule,
        "status":          event.status,
        "sync_source":     event.sync_source,
        "source_input_turn_id": str(event.source_input_turn_id) if event.source_input_turn_id else None,
        "created_at":      event.created_at.isoformat() if event.created_at else None,
        "attendees":       attendees if attendees is not None else None,
        "files":           files if files is not None else None,
    }


async def create_event(
    title: str,
    start_at: str,
    end_at: str = "",
    location: str = "",
    description: str = "",
    all_day: int = 0,
    recurrence_rule: str = "",
    source_input_turn_id: str = "",
    user_id: str = "default",
) -> dict:
    """
    Create an event. Requires title + start_at (ISO8601 with TZ).

    v1.4.x hard validation: event MUST have a renderable time span — at least
    one of {end_at, all_day=1}. A bare start_at without end / all_day means
    this should have been a todo (per dispatcher's strict rule). Reject loudly
    so we surface dispatcher mis-routes instead of silently creating residual
    events that can't render as calendar blocks.
    """
    from datetime import datetime, timezone, timedelta
    # Canonical user timezone (Asia/Shanghai). Event times are user-intended
    # LOCAL times ("下午4点"); a naive ISO (no offset) means local, not UTC. We
    # attach local tz here so the UTCDateTime column converts it to a correct UTC
    # instant — otherwise a naive 16:00 would be stored as 16:00 UTC (8h skew).
    _LOCAL_TZ = timezone(timedelta(hours=8))
    if not title:
        return _err("title is required")
    try:
        start_dt = datetime.fromisoformat(start_at.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return _err(f"invalid start_at ISO8601: {start_at}")
    if start_dt.tzinfo is None:
        start_dt = start_dt.replace(tzinfo=_LOCAL_TZ)
    end_dt = None
    if end_at:
        try:
            end_dt = datetime.fromisoformat(end_at.replace("Z", "+00:00"))
        except (ValueError, AttributeError):
            return _err(f"invalid end_at ISO8601: {end_at}")
        if end_dt.tzinfo is None:
            end_dt = end_dt.replace(tzinfo=_LOCAL_TZ)

    # ── Hard validation: time span required ──
    if not end_dt and not bool(all_day):
        return _err(
            "event missing time span: needs end_at OR all_day=1. "
            "If only a single time point, this should be a todo (with due_date), "
            "not an event."
        )

    async with AsyncSessionLocal() as db:
        event = Event(
            user_id=user_id,
            title=title,
            start_at=start_dt,
            end_at=end_dt,
            location=location or None,
            description=description or None,
            all_day=int(bool(all_day)),
            recurrence_rule=recurrence_rule or None,
            sync_source="manual",
            source_input_turn_id=uuid.UUID(source_input_turn_id) if source_input_turn_id else None,
        )
        db.add(event)
        await db.commit()
        await db.refresh(event)

    return _ok(**_event_to_dict(event, attendees=[], files=[]))


async def query_event(
    contains: str = "",
    from_date: str = "",
    to_date: str = "",
    status: str = "",
    limit: int = 50,
    user_id: str = "default",
    created_from: str = "",
    created_to: str = "",
) -> dict:
    """
    Query events by date range, status, and/or keyword in title/location/description.
    `from_date`/`to_date` bound start_at (calendar views); `created_from`/`created_to`
    bound created_at (the today-page pool: events *recorded* today, regardless of
    when they're scheduled). Returns newest start_at first; attendees + file refs inline.
    """
    from datetime import datetime
    async with AsyncSessionLocal() as db:
        stmt = select(Event).where(Event.user_id == user_id)
        if status:
            stmt = stmt.where(Event.status == status)
        if from_date:
            try:
                stmt = stmt.where(Event.start_at >= datetime.fromisoformat(from_date.replace("Z", "+00:00")))
            except ValueError:
                return _err(f"invalid from_date: {from_date}")
        if to_date:
            try:
                stmt = stmt.where(Event.start_at <= datetime.fromisoformat(to_date.replace("Z", "+00:00")))
            except ValueError:
                return _err(f"invalid to_date: {to_date}")
        if created_from:
            try:
                stmt = stmt.where(Event.created_at >= datetime.fromisoformat(created_from.replace("Z", "+00:00")))
            except ValueError:
                return _err(f"invalid created_from: {created_from}")
        if created_to:
            try:
                stmt = stmt.where(Event.created_at <= datetime.fromisoformat(created_to.replace("Z", "+00:00")))
            except ValueError:
                return _err(f"invalid created_to: {created_to}")
        if contains:
            kw = f"%{contains}%"
            from sqlalchemy import or_
            stmt = stmt.where(or_(Event.title.ilike(kw), Event.location.ilike(kw), Event.description.ilike(kw)))
        stmt = stmt.order_by(Event.start_at.desc()).limit(limit)
        result = await db.execute(stmt)
        events = result.scalars().all()

        # Fetch attendees + files for each (one batched query each)
        event_ids = [e.id for e in events]
        attendees_by_event = {eid: [] for eid in event_ids}
        files_by_event = {eid: [] for eid in event_ids}
        if event_ids:
            atts = (await db.execute(
                select(EventAttendee).where(EventAttendee.event_id.in_(event_ids))
            )).scalars().all()
            for a in atts:
                attendees_by_event[a.event_id].append({
                    "attendee_id": str(a.id),
                    "contact_id":  str(a.contact_id) if a.contact_id else None,
                    "name":        a.name_raw,
                    "role":        a.role,
                })
            efs = (await db.execute(
                select(EventFile).where(EventFile.event_id.in_(event_ids))
            )).scalars().all()
            for f in efs:
                files_by_event[f.event_id].append({
                    "event_file_id": str(f.id),
                    "file_id":       str(f.file_id),
                    "kind":          f.kind,
                })

    return _ok(events=[
        _event_to_dict(e, attendees=attendees_by_event[e.id], files=files_by_event[e.id])
        for e in events
    ])


async def get_event(event_id: str, user_id: str = "default") -> dict:
    """Fetch a single event by id, with attendees and files inline."""
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Event).where(Event.id == uuid.UUID(event_id), Event.user_id == user_id)
        )
        event = result.scalar_one_or_none()
        if not event:
            return _err(f"event not found: {event_id}")
        atts = (await db.execute(
            select(EventAttendee).where(EventAttendee.event_id == event.id)
        )).scalars().all()
        efs = (await db.execute(
            select(EventFile).where(EventFile.event_id == event.id)
        )).scalars().all()
    return _ok(**_event_to_dict(
        event,
        attendees=[{
            "attendee_id": str(a.id),
            "contact_id":  str(a.contact_id) if a.contact_id else None,
            "name":        a.name_raw,
            "role":        a.role,
        } for a in atts],
        files=[{
            "event_file_id": str(f.id),
            "file_id":       str(f.file_id),
            "kind":          f.kind,
        } for f in efs],
    ))


async def update_event(
    event_id: str,
    patch: str,
    user_id: str = "default",
) -> dict:
    """
    Update an event's fields. `patch` is a JSON string of field→value.
    Allowed fields: title, start_at, end_at, location, description, status,
    all_day, recurrence_rule.
    """
    try:
        patch_dict = json.loads(patch) if isinstance(patch, str) else patch
    except json.JSONDecodeError as e:
        return _err(f"invalid patch JSON: {e}")
    if not isinstance(patch_dict, dict):
        return _err("patch must be a JSON object")

    allowed = {"title", "start_at", "end_at", "location", "description",
               "status", "all_day", "recurrence_rule"}

    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Event).where(Event.id == uuid.UUID(event_id), Event.user_id == user_id)
        )
        event = result.scalar_one_or_none()
        if not event:
            return _err(f"event not found: {event_id}")

        from datetime import datetime
        for k, v in patch_dict.items():
            if k not in allowed:
                continue
            if k in ("start_at", "end_at") and isinstance(v, str):
                try:
                    v = datetime.fromisoformat(v.replace("Z", "+00:00"))
                except ValueError:
                    return _err(f"invalid {k} ISO8601: {v}")
            setattr(event, k, v)
        await db.commit()
        await db.refresh(event)

    return _ok(**_event_to_dict(event))


async def delete_event(event_id: str, user_id: str = "default") -> dict:
    """Delete an event. Cascades to event_attendees and event_files."""
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Event).where(Event.id == uuid.UUID(event_id), Event.user_id == user_id)
        )
        event = result.scalar_one_or_none()
        if not event:
            return _err(f"event not found: {event_id}")
        await db.delete(event)
        await db.commit()
    return _ok(event_id=event_id, status="deleted")


async def add_event_attendee(
    event_id: str,
    name: str = "",
    contact_id: str = "",
    role: str = "attendee",
    user_id: str = "default",
) -> dict:
    """
    Add an attendee to an event. Either contact_id (link to existing contact)
    or name (unresolved string) must be provided.
    """
    if not name and not contact_id:
        return _err("either name or contact_id must be provided")

    async with AsyncSessionLocal() as db:
        # Confirm event exists for this user
        ev = (await db.execute(
            select(Event).where(Event.id == uuid.UUID(event_id), Event.user_id == user_id)
        )).scalar_one_or_none()
        if not ev:
            return _err(f"event not found: {event_id}")

        att = EventAttendee(
            event_id=uuid.UUID(event_id),
            contact_id=uuid.UUID(contact_id) if contact_id else None,
            name_raw=name or None,
            role=role,
        )
        db.add(att)
        await db.commit()
        await db.refresh(att)

    return _ok(
        attendee_id=str(att.id),
        event_id=event_id,
        contact_id=str(att.contact_id) if att.contact_id else None,
        name=att.name_raw,
        role=att.role,
    )


async def link_event_file(
    event_id: str,
    file_id: str,
    kind: str = "attachment",
    user_id: str = "default",
) -> dict:
    """Link a file (audio/doc/note) to an event. kind: prep/recording/notes/attachment."""
    async with AsyncSessionLocal() as db:
        ev = (await db.execute(
            select(Event).where(Event.id == uuid.UUID(event_id), Event.user_id == user_id)
        )).scalar_one_or_none()
        if not ev:
            return _err(f"event not found: {event_id}")

        ef = EventFile(
            event_id=uuid.UUID(event_id),
            file_id=uuid.UUID(file_id),
            kind=kind,
        )
        db.add(ef)
        await db.commit()
        await db.refresh(ef)

    return _ok(event_file_id=str(ef.id), event_id=event_id, file_id=file_id, kind=kind)
