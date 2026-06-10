"""
Report pipeline (§6.1) — orchestrates the synthesis/report engine.

    user wish (+ optional manually-selected asset ids)
        │
        ▼  ① report-dispatcher (LLM, no tools) → {genre, time_range, asset_types,
        │     source_asset_ids, brief, title}
        │
        ▼  pipeline fetches REAL data deterministically (query_digest / query_asset
        │     / by-id) — NOT via LLM tool calls, so numbers can't be corrupted by a
        │     flaky tool-call. (Deviates from §6.3's "content skill queries"; chosen
        │     for reliability — DeepSeek tool-calling is documented-flaky here.)
        │
        ▼  ② content skill (LLM, no tools) → annotated Markdown (substance)
        │
        ▼  ③ render (deterministic Python, report_render) → single-file HTML
        │
        ▼  persist Report row (content_md + html + spec) → return it

Mirrors flash_pipeline's structure and reuses its ADK runner (`_run_agent`) +
JSON extractor (`_parse_json`).
"""
from __future__ import annotations

import json
import re
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import select

from agents.flash_pipeline import _parse_json, _run_agent
from core.agent_runner import run_agent  # §6.12 batch 0: returns summed usage_tokens
from agents.report_render import render_report
from agents.skill_factory import (
    REPORT_GENRES,
    make_report_content_agent,
    make_report_dispatcher_agent,
    make_report_intake_agent,
)
from db.database import AsyncSessionLocal
from db.models import Asset, GlobalSkill, Report, UserSkill
from mcp_server.tools import query_asset, query_digest

_BEIJING = timezone(timedelta(hours=8))
_WEEK = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

# Cap injected records per type so the content-skill prompt stays sane.
_MAX_PER_TYPE = 60

# Below this many relevant records, an auto (wish-driven) report is too thin to
# be worth the LLM round-trip — we tell the user to record more first. The manual
# hand-pick path is never gated (an explicit selection is honored as-is).
_MIN_RECORDS = 3


def _today_str() -> str:
    now = datetime.now(_BEIJING)
    return f"{now:%Y-%m-%d} {_WEEK[now.weekday()]}"


def _iso_range(time_range: Optional[dict]) -> tuple[str, str]:
    if not isinstance(time_range, dict):
        return "", ""
    f, t = time_range.get("from"), time_range.get("to")
    return (
        f"{f}T00:00:00+08:00" if f else "",
        f"{t}T23:59:59+08:00" if t else "",
    )


def _cap(by_type: dict) -> dict:
    return {k: v[:_MAX_PER_TYPE] for k, v in by_type.items()}


# ── Data fetch (deterministic, no LLM) ───────────────────────────────────────
async def _fetch_by_ids(asset_ids: list, user_id: str) -> dict:
    ids = []
    for x in asset_ids:
        try:
            ids.append(uuid.UUID(str(x)))
        except (ValueError, AttributeError, TypeError):
            pass
    if not ids:
        return {"counts": {}, "by_type": {}, "events": []}
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(Asset, GlobalSkill.name)
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.user_id == user_id, Asset.id.in_(ids))
            .order_by(Asset.created_at.asc())
        )).all()
    by_type: dict[str, list] = {}
    for a, name in rows:
        by_type.setdefault(name, []).append(a.payload or {})
    return {"counts": {k: len(v) for k, v in by_type.items()}, "by_type": _cap(by_type), "events": []}


_HIDDEN_SKILLS = {"external_ref", "qa", "contact"}


async def _load_user_skills(user_id: str) -> list[dict]:
    """Active, user-facing skills → [{machine_name, display_name}]. The dispatcher
    needs these to emit correct machine_names (it can't guess that 读书笔记 is
    `book_note`), and the fetch uses them to resolve a display name back to a
    machine name. Deduped by machine_name (a user may have stale dup rows)."""
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(GlobalSkill.name, UserSkill.display_name)
            .join(UserSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(UserSkill.user_id == user_id, UserSkill.enabled == 1)
        )).all()
    out: list[dict] = []
    seen: set[str] = set()
    for machine, disp in rows:
        if not machine or machine in _HIDDEN_SKILLS or machine in seen:
            continue
        seen.add(machine)
        out.append({"machine_name": machine, "display_name": disp or machine})
    return out


def _resolve_type(t: str, skill_map: dict[str, str]) -> str:
    """Map a dispatcher-emitted asset type to a real machine_name. Tries exact
    machine_name → exact display_name → substring either way → leaves as-is."""
    if not t or not skill_map:
        return t
    if t in skill_map:
        return t
    low = t.strip().lower()
    for m, d in skill_map.items():
        if (d or "").strip().lower() == low:
            return m
    for m, d in skill_map.items():
        dl = (d or "").lower()
        if low and (low in m.lower() or m.lower() in low or low in dl or (dl and dl in low)):
            return m
    return t


def _kw_hit(obj, keywords: list[str]) -> bool:
    """Does a record's text contain any topical keyword? (case-insensitive
    substring over the JSON-dumped payload)."""
    s = json.dumps(obj, ensure_ascii=False).lower()
    return any(k.lower() in s for k in keywords)


async def _fetch_report_data(scope: dict, user_id: str, skill_map: dict[str, str] | None = None) -> dict:
    src_ids = scope.get("source_asset_ids") or []
    if src_ids:
        return await _fetch_by_ids(src_ids, user_id)

    fr, to = _iso_range(scope.get("time_range"))
    skill_map = skill_map or {}
    from core.domains import normalize_domain
    domain = normalize_domain(scope.get("domain"))  # §8 life-domain scope (or None)
    # Resolve + dedupe each requested type to a real machine_name.
    asset_types: list[str] = []
    for t in (scope.get("asset_types") or []):
        if not t:
            continue
        r = _resolve_type(t, skill_map)
        if r not in asset_types:
            asset_types.append(r)
    # Topical keywords — set by the dispatcher when the wish names a subject it
    # COULDN'T map to a skill type (e.g.「读书」but the user has no 读书笔记 skill).
    keywords = [str(k).strip() for k in (scope.get("keywords") or []) if str(k).strip()]

    # ── gather raw records ────────────────────────────────────────────────────
    # Type-scoped → query each type STRICTLY (no silent widening to all types).
    # An empty scoped result stays empty → the insufficient gate fires
    # ("没找到「读书」相关记录") instead of dumping every record under a topical
    # title (the「读书进展 → 全部」bug). Untyped → all-type digest.
    events: list = []
    if asset_types:
        by_type: dict[str, list] = {}
        for t in asset_types:
            res = await query_asset(user_skill_name=t, from_date=fr, to_date=to,
                                    domain=domain or "", limit=200, user_id=user_id)
            if res.get("ok"):
                vals = [a.get("payload") or {} for a in res.get("assets", [])]
                if vals:
                    by_type[t] = vals
    else:
        res = await query_digest(from_date=fr, to_date=to, domain=domain or "", user_id=user_id)
        by_type = dict(res.get("by_type", {})) if res.get("ok") else {}
        events = (res.get("events") or [])[:40] if res.get("ok") else []

    # ── topical keyword narrowing ─────────────────────────────────────────────
    # Honor a subject the dispatcher couldn't type-scope: keep only records whose
    # text matches a keyword. Too few matches → insufficient (not an all-records
    # digest mislabeled with the subject). No keywords → unchanged.
    if keywords:
        by_type = {t: [p for p in ps if _kw_hit(p, keywords)] for t, ps in by_type.items()}
        by_type = {t: ps for t, ps in by_type.items() if ps}
        events = [e for e in events if _kw_hit(e, keywords)]

    return {"counts": {t: len(ps) for t, ps in by_type.items()}, "by_type": _cap(by_type), "events": events}


# ── md hygiene ───────────────────────────────────────────────────────────────
def _strip_outer_fence(md: str) -> str:
    """Content skills sometimes wrap the whole md in ```markdown … ``` — and
    occasionally forget the closing fence. Peel a leading AND/OR trailing fence
    line **independently**, so a dangling open fence can't survive into the body
    (which then made _ensure_frontmatter prepend a 2nd frontmatter → leaked text)."""
    s = md.strip()
    s = re.sub(r"^```[a-zA-Z0-9_-]*[ \t]*\n", "", s)   # leading fence (closed or not)
    s = re.sub(r"\n```[ \t]*$", "", s)                  # trailing fence
    return s.strip()


_META_RE = re.compile(r"^[（(].*(根据|因此|以下|提供的|数据|说明|输出|note|based on).*[）)]\s*$",
                      re.IGNORECASE)


def _strip_meta(md: str) -> str:
    """Defensive: drop trailing standalone parenthetical meta lines the content
    skill sometimes leaks (e.g. 「（根据提供的数据，…只输出…）」). Belt-and-
    suspenders behind the prompt rule."""
    lines = md.rstrip().split("\n")
    while lines and (not lines[-1].strip() or _META_RE.match(lines[-1].strip())):
        if _META_RE.match(lines[-1].strip()):
            lines.pop()
        elif not lines[-1].strip():
            lines.pop()
        else:
            break
    return "\n".join(lines).rstrip() + "\n"


def _ensure_frontmatter(md: str, genre: str, title: str) -> str:
    """Render keys off frontmatter; if the LLM omitted it, inject a minimal one."""
    if re.match(r"^\s*---\s*\n", md):
        return md
    fm = f"---\ngenre: {genre}\ntitle: {title}\n---\n"
    return fm + md


# ── §6.13 / handoff Phase 1: suggested actions ───────────────────────────────
_MD_INLINE = re.compile(r"\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`")


def _extract_actions(md: str) -> list[dict]:
    """Pull the content skill's `:::actions` items → [{title}] for the native
    「✦ 接下来」action bar (+ 待办). Plain-text titles (inline md stripped);
    tolerates the backtick-wrapped fence the renderer also normalizes."""
    out: list[dict] = []
    body = re.sub(r"(?m)^[ \t]*`+[ \t]*(:::[^`\n]*?)[ \t]*`+[ \t]*$", r"\1", md or "")
    for m in re.finditer(r"(?ms)^:::actions[^\n]*\n(.*?)^:::[ \t]*$", body):
        for line in m.group(1).splitlines():
            line = line.strip()
            im = re.match(r"^(?:\d+\.|[-*])\s+(.+)$", line)
            if not im:
                continue
            title = _MD_INLINE.sub(lambda g: g.group(1) or g.group(2) or g.group(3) or "", im.group(1)).strip()
            if title:
                out.append({"title": title[:200], "kind": "todo"})
    return out[:8]  # a "下一步" longer than this is a plan, not actions


# ── REKA signature band (§6.6.1 / §6.12 batch 3) ─────────────────────────────
async def _fetch_pet_gene(user_id: str) -> Optional[dict]:
    """The user's REKA genome in mascot.js `opts` shape (camelCase) for the footer
    band, or None (no pet → band shows just the wordmark)."""
    from db.models import Pet
    async with AsyncSessionLocal() as db:
        pet = (await db.execute(select(Pet).where(Pet.user_id == user_id))).scalar_one_or_none()
    if not pet or not pet.skin:
        return None
    eq = pet.equipped or {}
    return {
        "skin": pet.skin,
        "emblem": pet.emblem or "star",
        "emblemColor": pet.emblem_color or "white",
        "head": eq.get("head", "none"),
        "leftItem": eq.get("leftItem", "none"),
        "rightItem": eq.get("rightItem", "none"),
        "carrier": eq.get("carrier", "none"),
        "aura": eq.get("aura", "soft"),
    }


# ── Persistence ──────────────────────────────────────────────────────────────
def _meta(r: Report) -> dict:
    return {
        "id": str(r.id), "title": r.title, "genre": r.genre,
        "spec": r.spec_json or {},
        "suggested_actions": r.suggested_actions or [],  # §6.13 native action bar
        "gen_ms": r.gen_ms,            # §6.7: may be shown ("REKA 用了 N 秒")
        "tokens_used": r.tokens_used,  # §6.7: admin/telemetry (cost aggregation)
        "created_at": r.created_at.isoformat() if r.created_at else None,
    }


async def _persist(user_id: str, title: str, genre: str, md: str, html: str, spec: dict,
                   tokens_used: int = 0, gen_ms: int = 0, pet_gene: Optional[dict] = None,
                   suggested_actions: Optional[list] = None) -> dict:
    r = Report(
        user_id=user_id, title=title[:255], genre=genre,
        content_md=md, html=html, spec_json=spec,
        tokens_used=tokens_used or None, gen_ms=gen_ms or None, pet_gene=pet_gene,
        suggested_actions=suggested_actions or None,
    )
    async with AsyncSessionLocal() as db:
        db.add(r)
        await db.commit()
        await db.refresh(r)
        out = {**_meta(r), "content_md": r.content_md, "html": r.html}
    return out


# ── Guided dialogue (§6.8.2) ──────────────────────────────────────────────────
async def run_intake(messages: list[dict], user_id: str, today_str: Optional[str] = None) -> dict:
    """Decide whether the conversation is specific enough to scope a report.
    `messages` = [{"role": "user"|"assistant", "text": ...}]. Returns
    {"ready": bool, "ask"?: str}. Caps interrogation at the wizard layer."""
    today = today_str or _today_str()
    skills = await _load_user_skills(user_id)
    skill_hint = "；".join(f"{s['machine_name']} = {s['display_name']}" for s in skills)
    convo = "\n".join(f"{m.get('role', 'user')}: {m.get('text', '')}" for m in messages)
    agent = make_report_intake_agent()
    msg = (
        f"现在是 {today}\n"
        f"available_asset_types: {skill_hint or '（无）'}\n"
        f"conversation:\n{convo}"
    )
    raw, _ = await _run_agent(agent, msg, user_id)
    parsed = _parse_json(raw) or {}
    if parsed.get("ready") is True:
        return {"ready": True}
    ask = parsed.get("ask")
    if isinstance(ask, str) and ask.strip():
        return {"ready": False, "ask": ask.strip()}
    # Malformed / no question → don't block the user; let them generate.
    return {"ready": True}


# ── AI imagery (§6.6.2) ───────────────────────────────────────────────────────
# Genres that may carry an AI image: idea-synthesis/proposal → concept illustration;
# data-report/digest → a scene poster (§6.6.2). Only fires if the content skill
# actually emits an `image_prompt`, so a thin/empty report just renders image-less.
_IMAGE_GENRES = {"idea-synthesis", "proposal", "data-report", "digest"}


def _image_prompts_of(md: str) -> list[str]:
    """The content skill's scene prompt(s): `image_prompt:` + optional `image_prompt_2:`
    (a report may carry 1–2 images). Returns a list (0–2), grounded scenes only."""
    out: list[str] = []
    for key in ("image_prompt", "image_prompt_2"):
        m = re.search(rf"(?mi)^{key}:\s*(.+?)\s*$", md or "")
        p = (m.group(1).strip() if m else "").strip('"\'' + " ")
        if p and p.lower() not in ("none", "null", "无"):
            out.append(p)
    return out


_MOMENT_TAG = "✦ EUREKA MOMENT"


def _moment_section(figures_html: str, n: int) -> str:
    """Wrap the AI image(s) in a labeled 「✦ EUREKA MOMENT」 band — a real section,
    not a bare figure tacked after the charts. 2 images → side-by-side grid."""
    if not figures_html:
        return ""
    grid = "r-moment-2" if n >= 2 else "r-moment-1"
    return (
        '<section class="r-moment r-block">'
        f'<div class="r-moment-tag">{_MOMENT_TAG}</div>'
        f'<div class="r-moment-imgs {grid}">{figures_html}</div>'
        '</section>'
    )


def insert_report_image(html: str, block: str) -> str:
    """Insert an already-built block (the Eureka Moment section) as a **hero** —
    after the intro/charts, before the first section header. Fallbacks: above the
    signature band, then before the closing script."""
    if not block:
        return html
    i = html.find('<h2 class="r-h2')          # first section → hero spot is just before it
    if i != -1:
        return html[:i] + block + html[i:]
    anchor = '<footer class="r-sign'
    if anchor in html:
        return html.replace(anchor, block + anchor, 1)
    if "</div><script" in html:
        return html.replace("</div><script", block + "</div><script", 1)
    return html + block


async def _build_report_image(user_id: str, prompts: list[str], genre: str) -> tuple[str, str, int]:
    """Generate + store up to 2 AI images (quota-gated per image). Style by genre:
    data-report/digest → comic POSTER_STYLE; else soft-flat HOUSE_STYLE. Returns
    (figures_html, md_provenance, count) or ('','',0). HARD RULE (§6.3): never data."""
    from agents.report_image import (generate_image, quota_ok, store_image_file,
                                      HOUSE_STYLE, POSTER_STYLE)
    style = POSTER_STYLE if genre in ("data-report", "digest") else HOUSE_STYLE
    figures: list[str] = []
    md_bits: list[str] = []
    try:
        for prompt in prompts[:2]:                       # ≤2 images / report
            if not prompt or not await quota_ok(user_id):  # 配额闸:超额停
                break
            data_uri = await generate_image(prompt, house_style=style)
            if not data_uri:
                continue
            fid = await store_image_file(user_id, data_uri)
            figures.append(f'<figure class="r-ai-img"><img src="{data_uri}" alt="配图"/></figure>')
            if fid:
                md_bits.append(f"![配图](asset://{fid})")
    except Exception:
        pass
    if not figures:
        return "", "", 0
    suffix = ("\n\n" + "\n".join(md_bits) + "\n") if md_bits else ""
    return "".join(figures), suffix, len(figures)


# ── §14.9 web-search quota (briefing genre) ──────────────────────────────────
# Quota counting + hard cap ONLY — no billing (§12 pending, handoff "out of
# scope"). Mirrors the AI-image quota: a calendar-month cap per user.
_SEARCH_MONTHLY_QUOTA = 30


async def _search_quota_ok(user_id: str) -> bool:
    from sqlalchemy import func
    now = datetime.now(timezone.utc)
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    async with AsyncSessionLocal() as db:
        n = (await db.execute(
            select(func.count(Report.id)).where(
                Report.user_id == user_id,
                Report.genre == "briefing",
                Report.created_at >= start,
            )
        )).scalar()
    return int(n or 0) < _SEARCH_MONTHLY_QUOTA


# ── Public entrypoint ────────────────────────────────────────────────────────
async def run_report(
    user_wish: str,
    user_id: str,
    selected_summary: Optional[list] = None,
    source_asset_ids: Optional[list] = None,
    today_str: Optional[str] = None,
    on_phase=None,
) -> dict:
    """Run ①→fetch→②→③→persist. Returns the full report dict (incl html).

    `on_phase(name, message)` — optional async callback fired before each stage
    so a streaming endpoint can surface progress.
    """
    async def _phase(name: str, msg: str):
        if on_phase is not None:
            await on_phase(name, msg)

    # §6.12 batch 0 telemetry: wall-clock + summed model tokens across the run.
    _t0 = time.perf_counter()
    tokens_used = 0

    today = today_str or _today_str()

    # Load the user's real skills so the dispatcher emits correct machine_names
    # (it can't guess that 读书笔记 = `book_note`) and the fetch can resolve them.
    skills = await _load_user_skills(user_id)
    skill_map = {s["machine_name"]: s["display_name"] for s in skills}
    skill_hint = "；".join(f"{s['machine_name']} = {s['display_name']}" for s in skills)

    # ① dispatch (genre + scope)
    await _phase("dispatch", "正在分析诉求…")
    disp = make_report_dispatcher_agent()
    sel = selected_summary or []
    dmsg = (
        f"现在是 {today}\n"
        f"user_wish: {user_wish}\n"
        f"selected_assets: {json.dumps(sel, ensure_ascii=False)}\n"
        f"available_asset_types(只能从这里选 machine_name 填 asset_types): {skill_hint or '（无）'}"
    )
    _dr = await run_agent(disp, dmsg, user_id)
    raw = _dr.text
    tokens_used += _dr.usage_tokens
    scope = _parse_json(raw) or {}
    genre = scope.get("genre") if scope.get("genre") in REPORT_GENRES else "digest"
    scope["genre"] = genre
    if source_asset_ids:  # caller's manual selection overrides the dispatcher echo
        scope["source_asset_ids"] = source_asset_ids
    title = (scope.get("title") or "报告").strip()
    brief = (scope.get("brief") or user_wish).strip()

    # fetch real data (deterministic)
    await _phase("fetch", "正在汇集你的记录…")
    data = await _fetch_report_data(scope, user_id, skill_map=skill_map)

    # §14.9 web-search step (briefing only) — the pipeline searches
    # DETERMINISTICALLY before the content skill (content skills stay tool-less);
    # results are injected as 「带出处的资料」 and archived in spec (存证).
    # Degrades gracefully: no key / quota hit / zero hits → user-data-only report.
    web_results: list[dict] = []
    web_status = ""
    web_queries: list[str] = []
    if genre == "briefing":
        from core.web_search import provider as search_provider, search_web
        web_queries = [q.strip() for q in (scope.get("search_queries") or [])
                       if isinstance(q, str) and q.strip()][:3] or [brief or user_wish]
        if search_provider() is None:
            web_status = "off"      # search unconfigured (no key)
        elif not await _search_quota_ok(user_id):
            web_status = "quota"    # monthly hard cap (§14.9 配额)
        else:
            await _phase("search", "正在联网检索…")
            web_results = await search_web(web_queries)
            web_status = "ok" if web_results else "empty"

    # Insufficient-data gate (auto/wish path only — an explicit hand-pick is
    # honored as-is). Skip the expensive content+render+persist on thin data.
    # briefing is exempt: its substance is the wish + web material, and the
    # content skill handles empty data/web honestly (准备清单 + 未检索说明).
    is_manual = bool(scope.get("source_asset_ids"))
    total = sum(int(v) for v in (data.get("counts") or {}).values()) + len(data.get("events") or [])
    if not is_manual and genre != "briefing" and total < _MIN_RECORDS:
        return {
            "insufficient": True,
            "found": total,
            "min": _MIN_RECORDS,
            "title": title,
            "genre": genre,
        }

    # ② content → annotated md
    await _phase("content", "正在撰写报告…")
    content = make_report_content_agent(genre)
    cmsg = (
        f"title: {title}\n"
        f"brief: {brief}\n"
        f"time_range: {json.dumps(scope.get('time_range'), ensure_ascii=False)}\n"
        f"data: {json.dumps(data, ensure_ascii=False, default=str)}"
    )
    if genre == "briefing":  # sourced external material (§14.9 grounding 墙)
        cmsg += f"\nweb: {json.dumps(web_results, ensure_ascii=False)}"
    _cr = await run_agent(content, cmsg, user_id)
    md_raw = _cr.text
    tokens_used += _cr.usage_tokens
    md = _ensure_frontmatter(_strip_meta(_strip_outer_fence(md_raw)), genre, title)

    # ③ render (deterministic) — with the user's REKA gene for the §6.6.1 band
    await _phase("render", "正在排版…")
    pet_gene = await _fetch_pet_gene(user_id)
    rendered = render_report(md, seed_key=f"{title}|{genre}|{user_id}", pet_gene=pet_gene)
    html = rendered["html"]

    # ③.5 AI 配图(§6.6.2)— 同步生成,这样报告一打开就有图(不再异步「事后 pop in」
    # 让用户以为没生成);失败/超额则无图、报告照常完整。Mode A:idea-synthesis/proposal。
    if genre in _IMAGE_GENRES:
        prompts = _image_prompts_of(md)
        if prompts:
            await _phase("image", "正在配图…")
            figures, md_suffix, n = await _build_report_image(user_id, prompts, genre)
            if figures:
                html = insert_report_image(html, _moment_section(figures, n))  # Eureka Moment 段
                md = md.rstrip() + md_suffix                                   # provenance for 换装

    from core.domains import normalize_domain
    spec = {
        "time_range": scope.get("time_range"),
        "asset_types": scope.get("asset_types"),
        "keywords": scope.get("keywords") or [],  # topical narrowing (untyped subject)
        "domain": normalize_domain(scope.get("domain")),  # §8 scope — persist so rerender/audit keeps it (codex r2)
        "source_asset_ids": scope.get("source_asset_ids") or [],
        "surface": rendered["surface"],
        "palette": rendered["palette"],
        "seed": rendered["seed"],
        "brief": brief,
    }
    if genre == "briefing":  # §14.9 存证: queries + sourced results live with the report
        from core.web_search import provider as search_provider
        spec["web"] = {
            "provider": search_provider() or "off",
            "status": web_status,
            "queries": web_queries,
            "sources": web_results,
        }
    gen_ms = int((time.perf_counter() - _t0) * 1000)
    return await _persist(user_id, rendered["title"], genre, md, html, spec,
                          tokens_used=tokens_used, gen_ms=gen_ms, pet_gene=pet_gene,
                          suggested_actions=_extract_actions(md))  # §6.13 Phase 1
