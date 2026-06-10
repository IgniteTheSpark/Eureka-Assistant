"""nudges + rhythm_profiles + users.prefs (§14 主动 REKA / handoff Phase 2)

The companion layer's data model (§14.10):
- `nudges` — every proactive prompt is a persistent server-side entity (heartbeat
  fires while the user is offline; the feed must support 回溯). Outcome states
  drive both user-facing history (「✓ 已记 / 未处理」) and the adaptive backoff
  (§14.8 ignore → REKA 退避).
- `rhythm_profiles` — per (user, skill) STATISTICAL habit profile (§14.2: median
  cadence, time-of-day peaks, weekday spread, confidence). Recomputed daily by an
  offline pass in the heartbeat; never written by an LLM.
- `users.prefs` — small JSON prefs bag; v1 carries `nudges_enabled` (the §14.8
  「球球提醒」master switch, default ON).

Idempotent skip-if-exists, mirroring 0017/0018.

Revision ID: 0019_companion_nudges
Revises: 0018_report_actions
Create Date: 2026-06-10
"""
import sqlalchemy as sa
from alembic import op

revision = "0019_companion_nudges"
down_revision = "0018_report_actions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())

    def _has_col(table, col):
        return insp.has_table(table) and any(c["name"] == col for c in insp.get_columns(table))

    if not insp.has_table("nudges"):
        op.create_table(
            "nudges",
            sa.Column("id", sa.CHAR(36), primary_key=True),
            sa.Column("user_id", sa.String(50), nullable=False, server_default="default"),
            sa.Column("type", sa.String(1), nullable=False),        # A(提醒) | B(offer)
            sa.Column("kind", sa.String(20), nullable=False),       # rhythm_gap | reminder | offer | briefing …
            sa.Column("text", sa.String(255), nullable=False),      # template copy (peek 一句话)
            sa.Column("body", sa.Text()),                           # expanded copy (action bubble)
            sa.Column("ref", sa.String(100)),                       # target ref: skill machine_name / todo / event id
            sa.Column("cta", sa.String(20)),                        # log | view | research …
            sa.Column("status", sa.String(12), nullable=False, server_default="delivered"),
            # pending|delivered|seen|acted|dismissed|ignored(过期未处理)|expired
            sa.Column("source", sa.String(20), nullable=False, server_default="rhythm"),  # scheduler|rhythm
            sa.Column("created_at", sa.TIMESTAMP(timezone=True)),
            sa.Column("delivered_at", sa.TIMESTAMP(timezone=True)),
            sa.Column("acted_at", sa.TIMESTAMP(timezone=True)),
            sa.Column("expires_at", sa.TIMESTAMP(timezone=True)),
        )
        op.create_index("idx_nudges_user_created", "nudges", ["user_id", "created_at"])
        op.create_index("idx_nudges_user_status", "nudges", ["user_id", "status"])

    if not insp.has_table("rhythm_profiles"):
        op.create_table(
            "rhythm_profiles",
            sa.Column("user_id", sa.String(50), primary_key=True),
            sa.Column("skill", sa.String(100), primary_key=True),   # GlobalSkill.name
            sa.Column("cadence_minutes", sa.Integer()),             # median inter-record gap
            sa.Column("typical_hours", sa.JSON()),                  # peak hours (Beijing), e.g. [8, 12]
            sa.Column("weekdays", sa.JSON()),                       # concentrated weekdays 0-6 (Mon=0), [] = all
            sa.Column("confidence", sa.Float(), server_default="0"),
            sa.Column("sample_n", sa.Integer(), server_default="0"),
            sa.Column("computed_at", sa.TIMESTAMP(timezone=True)),
        )

    if not _has_col("users", "prefs"):
        op.add_column("users", sa.Column("prefs", sa.JSON(), nullable=True))


def downgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())
    if insp.has_table("nudges"):
        op.drop_table("nudges")
    if insp.has_table("rhythm_profiles"):
        op.drop_table("rhythm_profiles")
    if insp.has_table("users") and any(c["name"] == "prefs" for c in insp.get_columns("users")):
        op.drop_column("users", "prefs")
