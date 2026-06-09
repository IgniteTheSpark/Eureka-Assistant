"""
GET /api/export?format=md|csv — export the user's data (assets + events + contacts)
as ONE Markdown document or ONE flat CSV. Powers the 资产库 container's 「导出」.

- **Markdown**: grouped + human-readable (资产 by skill type, 事件, 名片), each
  record with its readable fields. For archiving / sharing / reading.
- **CSV**: one flat row per record (`kind,type,title,domain,created_at,detail_json`);
  the heterogeneous payload lands in the JSON `detail_json` column. For spreadsheets.

Read-only; user-scoped (every query filters by user_id).
"""
import csv
import io
import json
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from fastapi.responses import PlainTextResponse
from sqlalchemy import select

from core.auth import get_current_user_id
from core.contacts_meta import SUPPORTED_SOCIALS, clean_socials, notes_to_list
from db.database import AsyncSessionLocal
from db.models import Asset, Contact, Event, GlobalSkill, UserSkill

router = APIRouter()

_BEIJING = timezone(timedelta(hours=8))
# payload plumbing keys never worth exporting.
_SKIP_KEYS = {
    "contact_id", "asset_id", "event_id", "id", "user_id", "user_skill_name",
    "session_id", "source_input_turn_id", "status", "ok", "card_type",
}


def _fmt_dt(v) -> str:
    if not v:
        return ""
    if isinstance(v, datetime):
        return v.astimezone(_BEIJING).strftime("%Y-%m-%d %H:%M")
    try:
        return (datetime.fromisoformat(str(v).replace("Z", "+00:00"))
                .astimezone(_BEIJING).strftime("%Y-%m-%d %H:%M"))
    except (ValueError, TypeError):
        return str(v)


def _first_line(v, n: int = 80) -> str:
    parts = str(v or "").splitlines()
    return parts[0][:n] if parts else ""


async def _gather(user_id: str):
    async with AsyncSessionLocal() as db:
        skill_rows = (await db.execute(
            select(GlobalSkill.name, UserSkill.display_name, UserSkill.payload_schema)
            .join(UserSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(UserSkill.user_id == user_id)
        )).all()
        disp: dict[str, str] = {}
        labels: dict[str, dict] = {}
        for name, dn, sch in skill_rows:
            disp.setdefault(name, dn or name)
            lab: dict[str, str] = {}
            if isinstance(sch, dict):
                for k, meta in sch.items():
                    if isinstance(meta, dict) and meta.get("label"):
                        lab[k] = meta["label"]
            labels.setdefault(name, lab)

        assets = (await db.execute(
            select(Asset, GlobalSkill.name)
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.user_id == user_id)
            .order_by(Asset.created_at.desc())
        )).all()
        events = (await db.execute(
            select(Event).where(Event.user_id == user_id).order_by(Event.start_at.desc())
        )).scalars().all()
        contacts = (await db.execute(
            select(Contact).where(Contact.user_id == user_id).order_by(Contact.created_at.desc())
        )).scalars().all()
    return disp, labels, assets, events, contacts


def _payload_lines(payload: dict, labels: dict) -> list[str]:
    out = []
    for k, v in (payload or {}).items():
        if k in _SKIP_KEYS or v in (None, "", [], {}):
            continue
        label = labels.get(k, k)
        if isinstance(v, list):
            v = ", ".join(str(x) for x in v)
        elif isinstance(v, dict):
            v = json.dumps(v, ensure_ascii=False)
        out.append(f"  - {label}: {v}")
    return out


def _build_md(disp, labels, assets, events, contacts) -> str:
    now = datetime.now(_BEIJING).strftime("%Y-%m-%d %H:%M")
    out = [f"# Eureka 导出 · {now}", "",
           f"> 资产 {len(assets)} · 事件 {len(events)} · 名片 {len(contacts)}", ""]

    if assets:
        out += ["## 资产", ""]
        by_skill: dict[str, list] = {}
        for a, name in assets:
            by_skill.setdefault(name, []).append(a)
        for name, items in by_skill.items():
            out += [f"### {disp.get(name, name)} ({len(items)})", ""]
            for a in items:
                p = a.payload or {}
                title = _first_line(p.get("title") or p.get("name") or p.get("content") or "(无标题)")
                meta = [a.domain] if a.domain else []
                meta.append(_fmt_dt(a.created_at))
                out.append(f"- **{title}** · {' · '.join(meta)}")
                out += _payload_lines({k: v for k, v in p.items() if k not in ("title", "name")},
                                      labels.get(name, {}))
            out.append("")

    if events:
        out += ["## 事件", ""]
        for e in events:
            span = _fmt_dt(e.start_at)
            if e.all_day:
                span += " (全天)"
            elif e.end_at:
                span += f" ~ {_fmt_dt(e.end_at)}"
            line = f"- **{e.title}** · {span}"
            if e.location:
                line += f" · 📍{e.location}"
            out.append(line)
            if e.description:
                out.append(f"  - {e.description}")
        out.append("")

    if contacts:
        out += ["## 名片", ""]
        for c in contacts:
            sub = []
            if c.title or c.company:
                sep = "@" if (c.title and c.company) else ""
                sub.append(f"{c.title or ''}{sep}{c.company or ''}")
            if c.phone:
                sub.append(f"📞{c.phone}")
            if c.email:
                sub.append(f"✉{c.email}")
            out.append(f"- **{c.name}**" + (" · " + " · ".join(sub) if sub else ""))
            socials = clean_socials(c.socials)
            if socials:
                out.append("  - 社媒: " + ", ".join(
                    f"{SUPPORTED_SOCIALS.get(k, k)}={v}" for k, v in socials.items()))
            for n in notes_to_list(c.notes):
                out.append(f"  - 备注: {n}")
        out.append("")

    return "\n".join(out).rstrip() + "\n"


def _build_csv(disp, labels, assets, events, contacts) -> str:
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["kind", "type", "title", "domain", "created_at", "detail_json"])
    for a, name in assets:
        p = a.payload or {}
        title = _first_line(p.get("title") or p.get("name") or p.get("content") or "", 200)
        w.writerow(["asset", disp.get(name, name), title, a.domain or "",
                    a.created_at.isoformat() if a.created_at else "",
                    json.dumps(p, ensure_ascii=False)])
    for e in events:
        detail = {
            "start_at": e.start_at.isoformat() if e.start_at else None,
            "end_at": e.end_at.isoformat() if e.end_at else None,
            "all_day": bool(e.all_day), "location": e.location, "description": e.description,
        }
        w.writerow(["event", "事件", e.title or "", "",
                    e.start_at.isoformat() if e.start_at else "",
                    json.dumps(detail, ensure_ascii=False)])
    for c in contacts:
        detail = {
            "company": c.company, "title": c.title, "phone": c.phone, "email": c.email,
            "socials": clean_socials(c.socials), "notes": notes_to_list(c.notes),
        }
        w.writerow(["contact", "名片", c.name or "", "",
                    c.created_at.isoformat() if c.created_at else "",
                    json.dumps(detail, ensure_ascii=False)])
    return buf.getvalue()


@router.get("/export")
async def export_data(
    format: str = Query("md", description="md | csv"),
    types: str = Query("", description="comma-separated type keys to include "
                                       "(asset skill machine_names + 'event' / 'contact'); "
                                       "empty = everything"),
    user_id: str = Depends(get_current_user_id),
):
    fmt = format if format in ("md", "csv") else "md"
    want = {t.strip() for t in types.split(",") if t.strip()} or None
    disp, labels, assets, events, contacts = await _gather(user_id)
    if want is not None:  # selective export — keep only the chosen types
        assets = [(a, name) for (a, name) in assets if name in want]
        if "event" not in want:
            events = []
        if "contact" not in want:
            contacts = []
    if fmt == "csv":
        return PlainTextResponse(_build_csv(disp, labels, assets, events, contacts),
                                 media_type="text/csv; charset=utf-8")
    return PlainTextResponse(_build_md(disp, labels, assets, events, contacts),
                             media_type="text/markdown; charset=utf-8")
