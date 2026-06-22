"""
Seed default global_skills and user_skills (with payload_schema + render_spec)
for user_id='default'. Run after `alembic upgrade head`:

    python -m db.seed

Idempotent — safe to re-run.
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from sqlalchemy.orm import Session
from db.models import GlobalSkill, UserSkill
# Reuse the shared sync engine (pymysql driver). Building one here from the raw
# DATABASE_URL (mysql://) would default to the missing MySQLdb C driver.
from db.database import sync_engine as engine


# ── Global skill catalog (machine names + human descriptions) ──────────────────

GLOBAL_SKILLS = [
    {"name": "todo",    "description": "待办"},
    {"name": "event",   "description": "日程 / 事件(v1.4: 一级实体,events 表,非 SkillCard)"},
    {"name": "idea",    "description": "想法 / 灵感"},
    {"name": "notes",   "description": "笔记 / 长文档(v1.4: 会议纪要、报告、briefing)"},
    {"name": "misc",    "description": "兜底,无明确分类(v1.4)"},
    {"name": "contact", "description": "名片 / 联系人"},
    {"name": "expense", "description": "记账"},
    {"name": "qa",      "description": "问答(系统能力,无资产产出)"},
    {"name": "external_ref", "description": "外部系统引用(Notion / Google Calendar / Dingtalk 等 MCP 创建的页面/事件/消息的指针)"},
]


# ── Per-skill UserSkill configuration for the default user ─────────────────────
# payload_schema + queryable_fields + render_spec follow Phase B §九.

# §1.5.1 L0 — 起聊文案 per baseline skill (资产锚定会话的开场 hint)。
# 文案基准来自 spec §1.5.1;通用兜底三连在 opening-hint 端点里。
CHAT_STARTERS = {
    "todo":    ["帮我拆成几个子任务", "什么时候做它合适?", "为什么这件事重要?"],
    "notes":   ["帮我把这条想法展开", "把它升华成一篇报告", "相关的记录还有哪些?"],
    "idea":    ["帮我把这个想法展开", "它能怎么落地?", "把它升华成一篇报告"],
    "expense": ["这个月花了多少?", "和上个月比怎么样?", "帮我把最近的消费归归类"],
    "contact": ["记一件关于 TA 的事", "TA 和我最近聊过什么?", "帮我准备下次和 TA 的见面"],
    "misc":    ["帮我分析一下这条记录", "它和我最近的记录有什么联系?", "基于它给我一点建议"],
}

USER_SKILL_CONFIGS = [
    {
        "name": "todo",
        "display_name": "待办",
        "payload_schema": {
            "content":  {"type": "string",   "required": True},
            "due_date": {"type": "datetime"},
            "status":   {"type": "string", "enum": ["pending", "done", "pending_confirmation"], "default": "pending"},
        },
        "queryable_fields": [
            {"field": "due_date", "index_type": "date"},
            {"field": "status",   "index_type": "enum"},
        ],
        "render_spec": {
            "card_layout":       "horizontal",
            "icon":              "📋",
            "accent_color":      "blue",
            "primary_field":     "content",
            "secondary_field":   "due_date",
            "secondary_format":  "relative_date",
            "actions":           ["check", "edit"],
            "timeline_position": {"time_field": "due_date", "fallback": "created_at"},
            "calendar_render":   {"date_field": "due_date"},
        },
    },
    # v1.4: event removed from USER_SKILL_CONFIGS — promoted to first-class
    # entity (events table). Event still appears in GLOBAL_SKILLS (dispatcher
    # recognizes "event" intent), and the event-skill agent calls the new
    # create_event MCP tool. Frontend renders events via dedicated EventCard /
    # CalendarPage tiles, NOT SkillCard render_spec.
    # idea merged into 随记 (notes) — see §3.2.1 + the notes config below.
    {
        "name": "contact",
        "display_name": "名片",
        # contact 的「真身」在 contacts 表;这个 asset 形态用于在时间流 / 资产库里展示
        # 「最近捕捉到的联系人引用」,payload 指向真实 contact_id。
        "payload_schema": {
            "contact_id": {"type": "uuid",   "required": True},
            "name":       {"type": "string", "required": True},
            "company":    {"type": "string"},
            "title":      {"type": "string"},
            "phone":      {"type": "string"},
        },
        "queryable_fields": [
            {"field": "name",    "index_type": "text"},
            {"field": "company", "index_type": "text"},
        ],
        "render_spec": {
            "card_layout":     "horizontal",
            "icon":            "👤",
            "accent_color":    "neutral",
            "primary_field":   "name",
            "secondary_field": "company",
            "meta_fields":     [{"field": "title"}, {"field": "phone"}],
            "actions":         ["edit", "open"],
        },
    },
    {
        "name": "expense",
        "display_name": "记账",
        "payload_schema": {
            "amount":      {"type": "number", "required": True},
            "currency":    {"type": "string", "default": "CNY"},
            "category":    {"type": "string"},
            "merchant":    {"type": "string"},
            "date":        {"type": "date", "label": "日期"},
            "description": {"type": "string"},
        },
        "queryable_fields": [
            {"field": "amount",   "index_type": "numeric"},
            {"field": "category", "index_type": "enum"},
            {"field": "date",     "index_type": "date"},
            {"field": "merchant", "index_type": "text"},
        ],
        "render_spec": {
            "card_layout":     "horizontal",
            "icon":            "💰",
            "accent_color":    "green",
            "primary_field":   "amount",
            "primary_format":  "currency",
            "secondary_field": "description",
            "meta_fields": [
                {"field": "category", "format": "badge"},
                {"field": "date",     "format": "absolute_date"},
            ],
            "actions": ["edit"],
        },
    },
    {
        # 「随记」(§3.2.1) — the unified free-text catch-all that merges the old
        # idea / notes / misc (they were isomorphic: title? + content + time, and
        # the idea-vs-notes-vs-misc split was a chronic dispatcher 糊判). Machine
        # name stays `notes` (internal; users see 随记) to avoid a global-skill +
        # re-provision churn. Open topic `tags` (≤3, agent-generated, reusing the
        # user's existing tags) organize/retrieve these — orthogonal to the §7
        # `behavior` tag. behavior = 创造.
        "name": "notes",
        "display_name": "随记",
        "payload_schema": {
            "title":   {"type": "string"},
            "content": {"type": "string", "required": True},
            "tags":    {"type": "array", "items": "string"},
        },
        # Tags are queryable so "所有『游戏』相关随记" works (§3.2.1).
        "queryable_fields": [
            {"field": "tags", "index_type": "text"},
        ],
        "render_spec": {
            "card_layout":      "stacked",
            "icon":             "✍️",
            "accent_color":     "amber",
            "primary_field":    "title",
            "secondary_field":  "content",
            "secondary_format": "truncate_40",
            "meta_fields":      [{"field": "tags"}],
            "actions":          ["edit", "open"],
        },
    },
    # idea / misc are NO LONGER provisioned (merged into 随记 above). Their
    # GLOBAL_SKILLS rows remain (FK integrity); migration 0008 repoints any
    # existing idea/misc assets → the user's 随记 (notes) skill.
    {
        # qa is a recognized system capability but produces no assets:
        # null payload_schema + null render_spec is the contract for "system skill".
        "name":             "qa",
        "display_name":     "问答",
        "payload_schema":   None,
        "render_spec":      None,
        "queryable_fields": None,
    },
    {
        # v1.4.x: external_ref — pointer to a page/event/message that lives in
        # a third-party system (Notion / Google Calendar / Dingtalk / Linear /
        # ...), created via task-skill → MCP. Eureka stores the reference, not
        # the content; tapping the card opens the external URL.
        "name":         "external_ref",
        "display_name": "外部引用",
        "payload_schema": {
            "external_system": {"type": "string", "required": True},   # notion | google_calendar | dingtalk | ...
            "external_id":     {"type": "string"},                     # filled when task completes
            "external_url":    {"type": "string"},
            "external_type":   {"type": "string"},                     # page | event | message | issue | ...
            "title":           {"type": "string"},
            "summary":         {"type": "string"},
            "status":          {"type": "string", "enum": ["pending", "running", "done", "failed"], "default": "pending"},
            "task_id":         {"type": "uuid"},
            "error":           {"type": "string"},
            "metadata":        {"type": "object"},
        },
        "queryable_fields": [
            {"field": "external_system", "index_type": "enum"},
            {"field": "status",          "index_type": "enum"},
        ],
        "render_spec": {
            "card_layout":     "horizontal",
            "icon":            "🔗",
            "accent_color":    "purple",
            "primary_field":   "title",
            "secondary_field": "external_system",
            "meta_fields":     [{"field": "status", "format": "badge"}],
            "actions":         ["open_external", "delete"],
            "timeline_position": {"time_field": "created_at"},
        },
    },
]


def seed():
    with Session(engine) as db:
        # ── global_skills ──
        skill_ids = {}
        for gs in GLOBAL_SKILLS:
            existing = db.query(GlobalSkill).filter_by(name=gs["name"]).first()
            if not existing:
                obj = GlobalSkill(**gs)
                db.add(obj)
                db.flush()
                skill_ids[gs["name"]] = obj.id
                print(f"  + global_skill: {gs['name']}")
            else:
                skill_ids[gs["name"]] = existing.id
                print(f"  ~ global_skill exists: {gs['name']}")

        # ── user_skills for default user ──
        for cfg in USER_SKILL_CONFIGS:
            sk_id = skill_ids[cfg["name"]]
            existing = db.query(UserSkill).filter_by(user_id="default", skill_id=sk_id).first()
            if not existing:
                obj = UserSkill(
                    user_id="default",
                    skill_id=sk_id,
                    display_name=cfg["display_name"],
                    payload_schema=cfg["payload_schema"],
                    render_spec=cfg["render_spec"],
                    queryable_fields=cfg["queryable_fields"],
                    chat_starters=CHAT_STARTERS.get(cfg["name"]),
                )
                db.add(obj)
                print(f"  + user_skill: {cfg['name']}")
            else:
                print(f"  ~ user_skill exists: {cfg['name']}")

        db.commit()
    print("Seed complete.")


if __name__ == "__main__":
    seed()
