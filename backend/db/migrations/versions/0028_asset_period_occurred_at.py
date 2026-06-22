"""add assets.period + assets.occurred_at (时段 + 精确发生时刻)

Revision ID: 0028_asset_period_occurred_at
Revises: 0027_flash_recording_sync_asr
Create Date: 2026-06-20

§4.5.0a 一天渲染落段:
- period      — 用户只说了模糊时段时填(凌晨/上午/中午/下午/晚上),否则 null。
- occurred_at — 用户说了钟点时填的精确时刻(≠ created_at),否则 null。
两列都可空;老数据 null,前端按 created_at 兜底落段。v1 不加索引(按 date 取
当天后内存分段)。
"""

import sqlalchemy as sa
from alembic import op

revision = "0028_asset_period_occurred_at"
down_revision = "0027_flash_recording_sync_asr"
branch_labels = None
depends_on = None


def _columns(table_name: str) -> set[str]:
    from sqlalchemy import inspect

    return {c["name"] for c in inspect(op.get_bind()).get_columns(table_name)}


def upgrade() -> None:
    from db.models import TIMESTAMPTZ
    from sqlalchemy import inspect

    insp = inspect(op.get_bind())
    if not insp.has_table("assets"):
        return

    cols = _columns("assets")
    if "period" not in cols:
        op.add_column("assets", sa.Column("period", sa.String(length=8), nullable=True))
    if "occurred_at" not in cols:
        op.add_column("assets", sa.Column("occurred_at", TIMESTAMPTZ, nullable=True))


def downgrade() -> None:
    from sqlalchemy import inspect

    insp = inspect(op.get_bind())
    if not insp.has_table("assets"):
        return

    cols = _columns("assets")
    if "occurred_at" in cols:
        op.drop_column("assets", "occurred_at")
    if "period" in cols:
        op.drop_column("assets", "period")
