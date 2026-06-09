"""
Per-user provisioning — give a freshly registered account the baseline skill set
(todo / idea / contact / expense / notes / misc / qa / external_ref) so the app
isn't an empty shell on first login.

Reuses the same `USER_SKILL_CONFIGS` the `default` seed uses, keyed to the shared
`global_skills` catalog (which a fresh deploy creates via `python -m db.seed`).
"""
from sqlalchemy import select

from core.domains import prior_for_skill
from db.models import GlobalSkill, UserSkill
from db.seed import USER_SKILL_CONFIGS


async def provision_user_skills(db, user_id: str) -> int:
    """Create the baseline user_skills for [user_id]. Caller commits. Returns the
    number created. No-op for skills whose global type is missing (run the seed)."""
    names = [c["name"] for c in USER_SKILL_CONFIGS]
    rows = (await db.execute(
        select(GlobalSkill.id, GlobalSkill.name).where(GlobalSkill.name.in_(names))
    )).all()
    ids = {name: gid for gid, name in rows}

    created = 0
    for pos, cfg in enumerate(USER_SKILL_CONFIGS):
        sk_id = ids.get(cfg["name"])
        if sk_id is None:
            continue
        db.add(UserSkill(
            user_id=user_id,
            skill_id=sk_id,
            display_name=cfg["display_name"],
            payload_schema=cfg["payload_schema"],
            render_spec=cfg["render_spec"],
            queryable_fields=cfg["queryable_fields"],
            position=pos,
            domain=prior_for_skill(cfg["name"]),   # §8 per-skill prior
        ))
        created += 1
    return created
