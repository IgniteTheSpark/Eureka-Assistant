"""merge idea / misc → 随记 (notes) + tags (§3.2.1)

idea / notes / misc were isomorphic (title? + content + time); the split was a
chronic dispatcher 糊判. We fold them into one 随记 bucket (machine name kept as
`notes` to avoid global-skill churn; display → 随记) with open topic `tags`.

Per user:
  - repoint every idea/misc asset → that user's `notes` user_skill;
  - ensure the original type (想法 / 其它) is the first `tags` entry, and give
    title-less items a short title (so the stacked card has a primary line);
  - relabel/re-spec the user's `notes` skill to 随记 (+ tags render);
  - delete the now-empty idea/misc user_skills.

`global_skills` rows for idea/misc are kept (FK integrity). Idempotent: a second
run finds no idea/misc user_skills and no-ops. Downgrade is lossy (can't re-split
merged records) — it only re-creates empty idea/misc user_skills.

Revision ID: 0008_merge_suiji
Revises: 0007_connected_apps
Create Date: 2026-06-04
"""
import json
import uuid

from alembic import op
from sqlalchemy import text

revision = "0008_merge_suiji"
down_revision = "0007_connected_apps"
branch_labels = None
depends_on = None

_SUIJI_RENDER = {
    "card_layout": "stacked", "icon": "✍️", "accent_color": "amber",
    "primary_field": "title", "secondary_field": "content",
    "secondary_format": "truncate_40", "meta_fields": [{"field": "tags"}],
    "actions": ["edit", "open"],
}
_SUIJI_SCHEMA = {
    "title": {"type": "string"},
    "content": {"type": "string", "required": True},
    "tags": {"type": "array", "items": "string"},
}
_SUIJI_QUERYABLE = [{"field": "tags", "index_type": "text"}]


def _loads(v):
    if v is None:
        return {}
    if isinstance(v, (dict, list)):
        return v
    try:
        return json.loads(v)
    except (json.JSONDecodeError, TypeError, ValueError):
        return {}


def upgrade() -> None:
    bind = op.get_bind()

    gs = {name: gid for name, gid in bind.execute(
        text("SELECT name, id FROM global_skills WHERE name IN ('idea','misc','notes')")).all()}
    notes_gid = gs.get("notes")
    if notes_gid is None:
        return  # nothing to merge into

    legacy_gids = [g for g in (gs.get("idea"), gs.get("misc")) if g is not None]
    label_for_gid = {gs.get("idea"): "想法", gs.get("misc"): "其它"}

    # All user_skills for the three skills, grouped per user.
    rows = bind.execute(text(
        "SELECT id, user_id, skill_id FROM user_skills WHERE skill_id IN :gids"
    ).bindparams(__import__("sqlalchemy").bindparam("gids", expanding=True)),
        {"gids": legacy_gids + [notes_gid]}).all()

    by_user: dict[str, dict] = {}
    for us_id, user_id, skill_id in rows:
        u = by_user.setdefault(user_id, {"notes": None, "legacy": []})
        if skill_id == notes_gid:
            u["notes"] = us_id
        else:
            u["legacy"].append((us_id, skill_id))

    for user_id, info in by_user.items():
        notes_us_id = info["notes"]
        if notes_us_id is None:
            # User has idea/misc but no 随记 survivor — create one so their
            # records aren't orphaned.
            notes_us_id = str(uuid.uuid4())
            bind.execute(text(
                "INSERT INTO user_skills (id, user_id, skill_id, display_name, "
                "payload_schema, render_spec, queryable_fields, position, enabled) "
                "VALUES (:id, :uid, :sid, :dn, :ps, :rs, :qf, 0, 1)"),
                {"id": notes_us_id, "uid": user_id, "sid": notes_gid, "dn": "随记",
                 "ps": json.dumps(_SUIJI_SCHEMA), "rs": json.dumps(_SUIJI_RENDER),
                 "qf": json.dumps(_SUIJI_QUERYABLE)})

        for legacy_us_id, skill_id in info["legacy"]:
            label = label_for_gid.get(skill_id, "随记")
            assets = bind.execute(text(
                "SELECT id, payload FROM assets WHERE user_skill_id = :usid"),
                {"usid": legacy_us_id}).all()
            for aid, payload_raw in assets:
                p = _loads(payload_raw)
                if not isinstance(p, dict):
                    p = {"content": str(p)}
                tags = p.get("tags")
                if not isinstance(tags, list):
                    tags = []
                if label not in tags:
                    tags = ([label] + tags)[:3]
                p["tags"] = tags
                if not (p.get("title") or "").strip():
                    body = (p.get("content") or "").strip().splitlines()
                    p["title"] = (body[0][:20] if body else label)
                bind.execute(text(
                    "UPDATE assets SET user_skill_id = :nid, payload = :pl WHERE id = :aid"),
                    {"nid": notes_us_id, "pl": json.dumps(p, ensure_ascii=False), "aid": aid})
            # legacy skill now asset-less → remove it
            bind.execute(text("DELETE FROM user_skills WHERE id = :id"), {"id": legacy_us_id})

        # Relabel / re-spec the survivor to 随记.
        bind.execute(text(
            "UPDATE user_skills SET display_name = :dn, payload_schema = :ps, "
            "render_spec = :rs, queryable_fields = :qf WHERE id = :id"),
            {"dn": "随记", "ps": json.dumps(_SUIJI_SCHEMA), "rs": json.dumps(_SUIJI_RENDER),
             "qf": json.dumps(_SUIJI_QUERYABLE), "id": notes_us_id})


def downgrade() -> None:
    # Lossy: we can't re-split merged 随记 records back into idea/misc. Just
    # relabel the survivor back to 笔记 (idea/misc user_skills are not restored).
    bind = op.get_bind()
    notes_gid = bind.execute(
        text("SELECT id FROM global_skills WHERE name = 'notes'")).scalar()
    if notes_gid is not None:
        bind.execute(text(
            "UPDATE user_skills SET display_name = '笔记' WHERE skill_id = :g"),
            {"g": notes_gid})
