"""expense 单一时间字段:去掉冗余的 `at`(datetime),只留 `date`

记账 schema 早先同时有 `date`(纯日期)和 `at`(datetime),手动「快创」表单把两个
都渲染 → 出现两个时间选择器(用户反馈「只要一个就行」)。卡片/agent 用的都是
`date`,`at` 基本是冗余。此迁移把所有现存 expense user_skill 的 payload_schema 去掉
`at`、queryable_fields 去掉 `at` 项,并给 `date` 补上 label「日期」。

纯数据迁移(改 user_skills.payload_schema / queryable_fields 的 JSON);幂等
(没有 `at` 就跳过)。表单动态读 /api/skills 渲染,所以迁移跑完现有 App 无需重装
即只显示一个日期字段。seed.py 同步去掉 `at`(新用户)。

Revision ID: 0021_expense_single_time
Revises: 0020_chat_starters
Create Date: 2026-06-12
"""
import json

from alembic import op

revision = "0021_expense_single_time"
down_revision = "0020_chat_starters"
branch_labels = None
depends_on = None


def _load(v):
    if v is None:
        return None
    if isinstance(v, (dict, list)):
        return v
    try:
        return json.loads(v)
    except (TypeError, ValueError):
        return None


def upgrade() -> None:
    bind = op.get_bind()
    from sqlalchemy import inspect, text
    insp = inspect(bind)
    if not insp.has_table("user_skills") or not insp.has_table("global_skills"):
        return

    rows = bind.execute(text(
        "SELECT us.id, us.payload_schema, us.queryable_fields "
        "FROM user_skills us JOIN global_skills gs ON us.skill_id = gs.id "
        "WHERE gs.name = 'expense'"
    )).fetchall()

    upd = text("UPDATE user_skills SET payload_schema = :ps, queryable_fields = :qf WHERE id = :id")
    for sid, ps_raw, qf_raw in rows:
        ps = _load(ps_raw)
        qf = _load(qf_raw)
        changed = False

        if isinstance(ps, dict) and "at" in ps:
            ps.pop("at", None)
            # date 补 label,确保表单字段名是「日期」而非裸 key
            d = ps.get("date")
            if isinstance(d, dict):
                d.setdefault("label", "日期")
            else:
                ps["date"] = {"type": "date", "label": "日期"}
            changed = True

        if isinstance(qf, list):
            nqf = [f for f in qf if not (isinstance(f, dict) and f.get("field") == "at")]
            if len(nqf) != len(qf):
                qf = nqf
                changed = True

        if changed:
            bind.execute(upd, {
                "ps": json.dumps(ps, ensure_ascii=False),
                "qf": json.dumps(qf, ensure_ascii=False) if qf is not None else None,
                "id": sid,
            })


def downgrade() -> None:
    # Re-adding `at` to every expense skill is not meaningfully reversible (the
    # field carried no required data); no-op.
    pass
