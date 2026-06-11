"""
Morning briefing (§14.6 晨间简报) — 工程产内容,design 主理皮 (handoff Phase 3).

One report per Beijing day, built from DETERMINISTIC queries only (今日日程 /
今日待办+逾期 / 昨日回顾 / 本周进度) + template greetings — ZERO LLM, so the
first open of the day generates in milliseconds (§14.6 「首次打开现生成、秒出」).

Two immersive skins ported verbatim from the design handoff
(morning-brief-a/b.html), alternating by day:
- DAY A: sunrise warm — hero + motto + schedule cards + todos + yesterday recap
- DAY B: pre-dawn cool — centered hero + 今日聚焦 card + week ring + compact list

The product has two faces (§14.6 一个产物、两个面): ① the immersive first-open
page (mobile renders this html full-bleed); ② a normal `reports` row
(genre=morning-briefing) so past mornings read back like a diary.

温柔铁律 (§7.0/§9.0): overdue items say 「拖了 N 天」 as a fact with no guilt;
empty days celebrate the lightness instead of nagging.
"""
from __future__ import annotations

import re
import time
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import select

from agents.report_render_designed import _ARM_JS, _FONTS_LINK, _MOTION_JS
from agents.report_styles import MORNING_CSS
from db.database import AsyncSessionLocal
from db.models import Asset, Event, GlobalSkill, Report, UserSkill

_BEIJING = timezone(timedelta(hours=8))
_WEEK = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

# render_spec accent names → hex (mirrors the app's 7-色板; default = variant accent)
_ACCENT_HEX = {
    "blue": "#5bb6e0", "amber": "#f0b35a", "purple": "#9b8cff", "green": "#35c98c",
    "red": "#ff6b73", "cyan": "#2bb6c4", "neutral": "#9aa3b2", "gray": "#9aa3b2",
}

# Greeting subtitles + mottos — rotated deterministically by day-of-year (模板,
# 非 LLM;§14.6 only the串场 would ever need a model, and templates suffice).
_SUBTITLES_A = [
    "Reka 帮你把今天理好了 ☀️", "新的一天,从容开始 ☀️", "今天也一步一步来 ☀️",
    "把重要的事放在前面 ☀️", "Reka 在,放心出发 ☀️",
]
_SUBTITLES_B = [
    "慢慢来,不着急 ☁️", "安静的早晨,适合理思路 ☁️", "先深呼吸,再看今天 ☁️",
    "今天只聚焦一件事 ☁️", "节奏是自己的 ☁️",
]
_MOTTOS = [
    "种一棵树最好的时间是十年前,其次是现在。",
    "把每一件简单的事做好,就是不简单。",
    "你不需要很厉害才能开始,你需要开始才会很厉害。",
    "慢慢来,比较快。",
    "记录本身,就是对生活的一次温柔注视。",
    "小步前进,也是前进。",
    "今天的事,今天轻轻放下。",
]


def _esc(s) -> str:
    import html
    return html.escape(str(s or ""), quote=True)


def _parse_due(v) -> Optional[datetime]:
    if not isinstance(v, str) or not v:
        return None
    try:
        s = v.strip()
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
            return datetime.fromisoformat(s + "T23:59:59+08:00")
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
        return dt if dt.tzinfo else dt.replace(tzinfo=_BEIJING)  # naive = Beijing wall-clock
    except ValueError:
        return None


def _title_of(payload: dict, display: str) -> str:
    for k in ("title", "content", "name", "item"):
        v = payload.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    amt = payload.get("amount")
    if amt is not None:
        cat = payload.get("category") or payload.get("note") or display
        return f"{cat} ¥{amt}"
    return display


# ── data (deterministic queries only) ─────────────────────────────────────────
async def _fetch(user_id: str) -> dict:
    now = datetime.now(timezone.utc)
    bj = now.astimezone(_BEIJING)
    day0 = bj.replace(hour=0, minute=0, second=0, microsecond=0)
    day0_utc, day1_utc = day0.astimezone(timezone.utc), (day0 + timedelta(days=1)).astimezone(timezone.utc)
    yest0_utc = (day0 - timedelta(days=1)).astimezone(timezone.utc)
    week0_utc = (day0 - timedelta(days=bj.weekday())).astimezone(timezone.utc)

    async with AsyncSessionLocal() as db:
        # 今日日程
        events = (await db.execute(
            select(Event).where(
                Event.user_id == user_id, Event.status == "scheduled",
                Event.start_at >= day0_utc, Event.start_at < day1_utc,
            ).order_by(Event.start_at.asc()).limit(8)
        )).scalars().all()
        evs = [{
            "time": "全天" if e.all_day else e.start_at.astimezone(_BEIJING).strftime("%H:%M"),
            "title": e.title, "desc": e.location or "",
        } for e in events]

        # todos: 逾期未完成 + 今天到期(含已完成 → 打勾的成就感)
        todo_rows = (await db.execute(
            select(Asset)
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.user_id == user_id, GlobalSkill.name == "todo")
            .order_by(Asset.created_at.desc()).limit(200)
        )).scalars().all()
        todos, week_total, week_done = [], 0, 0
        for a in todo_rows:
            p = a.payload or {}
            done = p.get("status") == "done" or p.get("done") is True
            due = _parse_due(p.get("due_date"))
            label = str(p.get("content") or p.get("title") or "待办")[:60]
            if due is not None:
                due_bj = due.astimezone(_BEIJING)
                if due >= week0_utc.astimezone(timezone.utc) and due_bj < day0 + timedelta(days=7 - bj.weekday()):
                    week_total += 1
                    week_done += 1 if done else 0
                over_days = (day0.date() - due_bj.date()).days
                if not done and over_days > 0 and over_days <= 30:
                    todos.append({"t": label, "done": False, "over": over_days})
                elif due_bj.date() == bj.date():
                    todos.append({"t": label, "done": done, "over": 0})
        todos.sort(key=lambda x: (x["done"], -x["over"]))
        todos = todos[:6]

        # 昨日回顾 — across ALL skills (built-in + custom, with render_spec colors)
        yest = (await db.execute(
            select(Asset, UserSkill.display_name, UserSkill.render_spec, GlobalSkill.name)
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.user_id == user_id,
                   Asset.created_at >= yest0_utc, Asset.created_at < day0_utc)
            .order_by(Asset.created_at.desc()).limit(50)
        )).all()
        builtin = {"todo", "notes", "event", "expense", "contact", "qa", "external_ref"}
        feed, domains, y_done = [], set(), 0
        for a, disp, spec, machine in yest:
            p = a.payload or {}
            if a.domain:
                domains.add(a.domain)
            if machine == "todo" and (p.get("status") == "done" or p.get("done") is True):
                y_done += 1
            if len(feed) < 4 and machine not in ("external_ref", "qa"):
                spec = spec or {}
                accent = _ACCENT_HEX.get(str(spec.get("accent_color") or spec.get("accentColor") or ""), "")
                feed.append({
                    "icon": (spec.get("icon") or "📝")[:2],
                    "title": _title_of(p, disp or machine)[:40],
                    "sub": str(p.get("note") or p.get("location") or p.get("category") or "")[:30],
                    "skill": (disp or machine)[:8],
                    "color": accent,
                    "custom": machine not in builtin,
                })
        recap = {"n": len(yest), "done": y_done, "domains": len(domains), "feed": feed}

        # 第 N 个早晨
        from sqlalchemy import func
        n_prev = (await db.execute(
            select(func.count(Report.id)).where(
                Report.user_id == user_id, Report.genre == "morning-briefing")
        )).scalar() or 0

    overdue_n = sum(1 for t in todos if t["over"])
    return {
        "bj": bj, "date_str": f"{bj.month} 月 {bj.day} 日 · {_WEEK[bj.weekday()]}",
        "clock": bj.strftime("%H:%M"),
        "events": evs, "todos": todos, "overdue_n": overdue_n,
        "recap": recap, "week": {"done": week_done, "total": week_total},
        "morning_no": n_prev + 1,
    }


# ── focus heuristic (B 的「今日聚焦」, deterministic) ──────────────────────────
def _focus_of(d: dict) -> Optional[dict]:
    overdue = [t for t in d["todos"] if t["over"]]
    if overdue:
        t = max(overdue, key=lambda x: x["over"])
        return {"t": t["t"], "d": f"这件事拖了 {t['over']} 天——不用愧疚,今天把它轻轻了结,后面都会顺。",
                "time": "建议 上午先做"}
    pending = [t for t in d["todos"] if not t["done"]]
    if pending:
        return {"t": pending[0]["t"], "d": "今天的待办里,它最值得先做。做完这件,其余都是顺手的事。",
                "time": "建议 上午 9–11 点"}
    if d["events"]:
        e = d["events"][0]
        return {"t": e["title"], "d": "今天最重要的一场安排。提前十分钟到,从容开场。",
                "time": f"⏰ {e['time']}"}
    return None


# ── annotated md (substance face — readable in the report container) ─────────
def _build_md(d: dict) -> str:
    bj = d["bj"]
    lines = [
        "---", "genre: morning-briefing", f"title: 早安 · {bj.month}月{bj.day}日", "---",
        f"# 早安 · {bj.month}月{bj.day}日 {_WEEK[bj.weekday()]}",
        "Reka 帮你把今天理好了。", "",
    ]
    if d["events"]:
        lines.append("## 今日安排")
        lines.append(":::timeline")
        for e in d["events"]:
            lines.append(f"{e['time']} — {e['title']}" + (f"({e['desc']})" if e["desc"] else ""))
        lines.append(":::")
    if d["todos"]:
        lines.append(f"## 今日待办{('(' + str(d['overdue_n']) + ' 件拖了)') if d['overdue_n'] else ''}")
        for t in d["todos"]:
            mark = "✓ " if t["done"] else ""
            over = f"(拖了 {t['over']} 天)" if t["over"] else ""
            lines.append(f"- {mark}{t['t']}{over}")
    r = d["recap"]
    if r["n"]:
        lines.append("## 昨日回顾")
        lines.append(f"昨天记了 {r['n']} 条,完成 {r['done']} 件待办,跨 {max(r['domains'], 1)} 个领域。")
    return "\n".join(lines) + "\n"


# ── immersive html (presentation face, design-handoff skins) ─────────────────
def _hero_pet_js() -> str:
    """Mount the REAL user pet into hero + sign (replaces the design's placeholder)."""
    return (
        "(function(){try{var g=window.__REKA_GENE__;if(!g||!window.Mascot)return;"
        "['mb-hero-pet','reka-sign-pet'].forEach(function(id){var el=document.getElementById(id);"
        "if(!el)return;var m=window.Mascot.mount(el,{skin:g.skin,emblem:g.emblem,emblemColor:g.emblemColor,"
        "head:g.head||'none',leftItem:g.leftItem||'none',rightItem:g.rightItem||'none',"
        "carrier:g.carrier||'none',aura:g.aura||'soft',scale:3});"
        "try{m.set({eyes:'happy',mouth:'idle'});m.setState('idle');}catch(e){}});}catch(e){}})();"
    )


def _todos_html(d: dict) -> str:
    rows = []
    for t in d["todos"]:
        cls = "mb-todo" + (" done" if t["done"] else "") + (" over" if t["over"] else "")
        style = ' style="color:var(--t-lo);text-decoration:line-through"' if t["done"] else ""
        tag = f'<span class="tag">拖了 {t["over"]} 天</span>' if t["over"] else ""
        rows.append(f'<div class="{cls}"><span class="mb-todo-c"></span>'
                    f'<span class="mb-todo-t"{style}>{_esc(t["t"])}</span>{tag}</div>')
    if not rows:
        rows.append('<div class="mb-empty">今天没有排期的待办——轻装上阵 🍃</div>')
    return "".join(rows)


def _build_html(d: dict, variant: str, pet_gene: Optional[dict]) -> str:
    import json as _json
    bj = d["bj"]
    doy = int(bj.strftime("%j"))
    n_ev, n_todo = len(d["events"]), len([t for t in d["todos"] if not t["done"]])
    chips = (f'<span class="mb-chip">🗓 {n_ev} 个安排</span>'
             f'<span class="mb-chip">✓ {n_todo} 件待办</span>')  # 天气 chip = v1.5 (§14.6)
    sec_todo_n = f"{len(d['todos'])} 件" + (f" · {d['overdue_n']} 件拖了" if d["overdue_n"] else "")

    if variant == "mb-a":
        subtitle = _SUBTITLES_A[doy % len(_SUBTITLES_A)]
        motto = _MOTTOS[doy % len(_MOTTOS)]
        _bar = ["", ' style="background:var(--acc2)"', ' style="background:var(--good)"']
        evs = "".join(
            f'<div class="mb-evt"><div class="mb-evt-time">{_esc(e["time"])}</div>'
            f'<div class="mb-evt-bar"{_bar[i % 3]}></div>'
            f'<div class="mb-evt-b"><div class="mb-evt-t">{_esc(e["title"])}</div>'
            + (f'<div class="mb-evt-d">{_esc(e["desc"])}</div>' if e["desc"] else "")
            + '</div></div>'
            for i, e in enumerate(d["events"])
        ) or '<div class="mb-empty">今天没有日程——大块的自由时间 ✨</div>'
        r = d["recap"]
        feed = "".join(
            f'<div class="mb-rec" style="--sc:{f["color"] or "var(--acc)"}"><span class="mb-rec-ic">{f["icon"]}</span>'
            f'<div class="mb-rec-b"><div class="mb-rec-t">{_esc(f["title"])}</div>'
            + (f'<div class="mb-rec-s">{_esc(f["sub"])}</div>' if f["sub"] else "")
            + f'</div><span class="mb-rec-skill{" custom" if f["custom"] else ""}">{_esc(f["skill"])}</span></div>'
            for f in r["feed"]
        )
        recap_html = ""
        if r["n"]:
            recap_html = (
                '<section class="mb-sec" data-reveal>'
                '<div class="mb-sec-h"><span class="mb-sec-t">昨日回顾</span><span class="mb-sec-n">Reka 记得</span></div>'
                '<div class="mb-recap">'
                f'<div class="mb-rc"><div class="mb-rc-n" data-count>{r["n"]}</div><div class="mb-rc-l">条记录</div></div>'
                f'<div class="mb-rc"><div class="mb-rc-n" data-count>{r["done"]}</div><div class="mb-rc-l">完成待办</div></div>'
                f'<div class="mb-rc"><div class="mb-rc-n" data-count>{max(r["domains"], 1)}</div><div class="mb-rc-l">个领域</div></div>'
                f'</div><div class="mb-feed">{feed}</div></section>'
            )
        hero = (
            '<section class="mb-hero"><div class="mb-sun"></div>'
            '<div class="mb-top"><div class="mb-pet" id="mb-hero-pet"></div>'
            f'<div><div class="mb-date">{_esc(d["date_str"])}</div><div class="mb-clock">{_esc(d["clock"])} · 晨</div></div></div>'
            f'<h1 class="mb-greet">早安<small>{_esc(subtitle)}</small></h1>'
            f'<div class="mb-chips">{chips}</div>'
            f'<p class="mb-motto">"{_esc(motto)}"</p></section>'
        )
        body = (
            '<div class="mb-body">'
            '<section class="mb-sec" data-reveal>'
            f'<div class="mb-sec-h"><span class="mb-sec-t">今日安排</span><span class="mb-sec-n">{n_ev} 件</span></div>'
            f'<div class="mb-sched">{evs}</div></section>'
            '<section class="mb-sec" data-reveal>'
            f'<div class="mb-sec-h"><span class="mb-sec-t">今日待办</span><span class="mb-sec-n">{_esc(sec_todo_n)}</span></div>'
            f'{_todos_html(d)}</section>'
            f'{recap_html}'
            '<div class="mb-swipe"><div class="mb-swipe-icon">⌄</div><div class="mb-swipe-t">向上滑,开始今天</div></div>'
            '</div>'
        )
    else:  # mb-b
        subtitle = _SUBTITLES_B[doy % len(_SUBTITLES_B)]
        hero = (
            '<section class="mb-hero"><div class="mb-cloud a"></div><div class="mb-cloud b"></div>'
            f'<div class="mb-date">{_esc(d["date_str"])} · {_esc(d["clock"])}</div>'
            '<div class="mb-pet" id="mb-hero-pet"></div>'
            f'<h1 class="mb-greet">早安<small>{_esc(subtitle)}</small></h1>'
            f'<div class="mb-chips">{chips}</div></section>'
        )
        focus = _focus_of(d)
        focus_html = ""
        if focus:
            focus_html = (
                '<div class="mb-focus" data-reveal><div class="mb-focus-k">✦ 今日聚焦</div>'
                f'<div class="mb-focus-t">{_esc(focus["t"])}</div>'
                f'<div class="mb-focus-d">{_esc(focus["d"])}</div>'
                f'<span class="mb-focus-time">⏱ {_esc(focus["time"])}</span></div>'
            )
        w = d["week"]
        ring_html = ""
        if w["total"] > 0:
            pct = round(w["done"] / w["total"] * 100)
            circ = 239
            arc = round(circ * w["done"] / w["total"])
            ring_html = (
                '<section class="mb-sec" data-reveal><div class="mb-sec-t">本周进度</div>'
                '<div class="mb-ring-wrap">'
                f'<svg class="mb-ring" width="92" height="92" viewBox="0 0 92 92">'
                f'<circle cx="46" cy="46" r="38" fill="none" stroke="var(--border)" stroke-width="9"></circle>'
                f'<g transform="rotate(-90 46 46)"><circle cx="46" cy="46" r="38" fill="none" stroke="var(--acc)" stroke-width="9" stroke-linecap="round" data-arc="{arc}" data-c="{circ}" stroke-dasharray="{arc} {circ}"></circle></g>'
                f'<text x="46" y="50" text-anchor="middle" fill="var(--t-hi)" font-family="JetBrains Mono" font-size="18" font-weight="700">{pct}%</text></svg>'
                f'<div class="mb-ring-info"><div class="mb-ring-n">{w["done"]} / {w["total"]}</div>'
                f'<div class="mb-ring-l">{"本周计划已完成大半——收个尾,周末就轻松了。" if pct >= 60 else "本周才刚开始,一件一件来。"}</div></div>'
                '</div></section>'
            )
        _dot = ["", ' style="background:var(--acc2)"']
        evs = "".join(
            f'<div class="mb-line"><span class="mb-line-t">{_esc(e["time"])}</span>'
            f'<span class="mb-line-dot"{_dot[i % 2]}></span>'
            f'<span class="mb-line-x">{_esc(e["title"])}</span></div>'
            for i, e in enumerate(d["events"])
        ) or '<div class="mb-empty">今天没有日程——大块的自由时间 ✨</div>'
        body = (
            '<div class="mb-body">'
            f'{focus_html}{ring_html}'
            f'<section class="mb-sec" data-reveal><div class="mb-sec-t">今日安排</div>{evs}</section>'
            f'<section class="mb-sec" data-reveal><div class="mb-sec-t">今日待办{(" · " + str(d["overdue_n"]) + " 件拖了") if d["overdue_n"] else ""}</div>'
            f'{_todos_html(d)}</section>'
            '<div class="mb-swipe"><div class="mb-swipe-icon">⌄</div><div class="mb-swipe-t">向上滑,开始今天</div></div>'
            '</div>'
        )

    sign = (
        '<footer class="r-sign"><div class="r-sign-pet" id="reka-sign-pet"></div>'
        '<div class="r-sign-meta"><div class="r-sign-mark"><span class="r-sign-spark">✦</span>Reka Morning</div>'
        f'<div class="r-sign-tag">每天一次 · 第 {d["morning_no"]} 个早晨</div></div></footer>'
    )
    css = MORNING_CSS[variant] + "\n" + MORNING_CSS["mb-shared"]
    gene_js = ""
    if pet_gene:
        gene_js = (f"<script>window.__REKA_GENE__={_json.dumps(pet_gene, ensure_ascii=False)};</script>"
                   f"<script>{_hero_pet_js()}</script>")
    title = f"早安 · {bj.month}月{bj.day}日"
    return (
        '<!doctype html><html lang="zh"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
        f'<title>{_esc(title)} · Reka Morning</title>'
        f'{_FONTS_LINK}<script>{_ARM_JS}</script><style>{css}</style></head>'
        f'<body><main class="report mb">{hero}{body}{sign}</main>'
        f'<script>{_MOTION_JS}</script>{gene_js}</body></html>'
    )


# ── public entrypoint — idempotent per Beijing day ─────────────────────────────
async def generate_today(user_id: str) -> dict:
    """Return today's morning briefing report dict, creating it on first call
    (§14.6 每天一次). Subsequent calls (re-open, report container) return the
    same row — no regeneration, no duplicates."""
    from agents.report_pipeline import _fetch_pet_gene, _meta, _persist

    bj = datetime.now(timezone.utc).astimezone(_BEIJING)
    day0_utc = bj.replace(hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc)
    async with AsyncSessionLocal() as db:
        existing = (await db.execute(
            select(Report).where(
                Report.user_id == user_id, Report.genre == "morning-briefing",
                Report.created_at >= day0_utc,
            ).order_by(Report.created_at.desc()).limit(1)
        )).scalar_one_or_none()
        if existing is not None:
            # An existing briefing today was already deemed worth showing — never
            # thin (a thin day skips creation-time display, see below).
            return {**_meta(existing), "content_md": existing.content_md,
                    "html": existing.html, "thin": False}

    _t0 = time.perf_counter()
    d = await _fetch(user_id)
    # §9.2.2 三级 gating · tier ③:数据太薄 = 今日无日程、无待办、昨日无任何记录。
    # 客户端据此跳过晨报(空晨报比没晨报糟;刚孵化完的新用户正好命中)。仅作展示
    # 信号回传,报告照常生成、照常进资产库(一个产物两个面)。
    thin = (not d["events"]) and (not d["todos"]) and (d["recap"]["n"] == 0)
    variant = "mb-a" if int(bj.strftime("%j")) % 2 == 0 else "mb-b"  # alternate daily
    pet_gene = await _fetch_pet_gene(user_id)
    md = _build_md(d)
    html = _build_html(d, variant, pet_gene)
    spec = {"surface": variant, "palette": variant, "seed": int(bj.strftime("%j")),
            "day": bj.strftime("%Y-%m-%d"), "morning_no": d["morning_no"]}
    gen_ms = int((time.perf_counter() - _t0) * 1000)
    report = await _persist(user_id, f"早安 · {bj.month}月{bj.day}日", "morning-briefing",
                            md, html, spec, gen_ms=gen_ms, pet_gene=pet_gene)
    return {**report, "thin": thin}
