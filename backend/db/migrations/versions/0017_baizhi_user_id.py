"""add users.baizhi_user_id + relax email/password NOT NULL (§13.1 / B1 百智 OAuth)

百智 (100wiser) is the IdP for OAuth login. A 百智-OAuth user has no email/password —
their identity is the stable `baizhi_user_id` (unique). So:
  • add `baizhi_user_id` (String(64), nullable, UNIQUE, indexed) — 百智 ↔ Eureka map,
  • relax `email` + `password_hash` to NULLable (email users still set both).

Eureka still mints its own HS256 session token (§3 unchanged); 百智's real token is
stored encrypted in `connected_apps` (provider='baizhi'), not here.

Idempotent skip-if-exists. MySQL allows multiple NULLs in a UNIQUE index, so the
unique constraint on `baizhi_user_id` (and the relaxed `email`) coexist with NULLs.

Revision ID: 0017_baizhi_user_id
Revises: 0016_report_html_mediumtext
Create Date: 2026-06-09
"""
import sqlalchemy as sa
from alembic import op

revision = "0017_baizhi_user_id"
down_revision = "0016_report_html_mediumtext"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())

    def _has_col(table, col):
        return insp.has_table(table) and any(c["name"] == col for c in insp.get_columns(table))

    def _has_index(table, name):
        return insp.has_table(table) and any(ix["name"] == name for ix in insp.get_indexes(table))

    # 1) 百智 identity mapping column (nullable, unique, indexed).
    if not _has_col("users", "baizhi_user_id"):
        op.add_column("users", sa.Column("baizhi_user_id", sa.String(64), nullable=True))
    if not _has_index("users", "uq_users_baizhi_user_id"):
        op.create_index("uq_users_baizhi_user_id", "users", ["baizhi_user_id"], unique=True)

    # 2) Relax NOT NULL — 百智-OAuth users have no email/password. Keeps the existing
    #    unique index on email (MySQL MODIFY COLUMN preserves it). No-op if already
    #    nullable (a fresh deploy's create_all builds them nullable from the model).
    op.alter_column("users", "email", existing_type=sa.String(255), nullable=True)
    op.alter_column("users", "password_hash", existing_type=sa.String(255), nullable=True)


def downgrade() -> None:
    # NOTE: cannot safely restore NOT NULL if any 百智-only users (NULL email) exist;
    # left nullable on purpose. Just drop the mapping column + its index.
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())
    if insp.has_table("users") and any(
        ix["name"] == "uq_users_baizhi_user_id" for ix in insp.get_indexes("users")
    ):
        op.drop_index("uq_users_baizhi_user_id", table_name="users")
    if insp.has_table("users") and any(
        c["name"] == "baizhi_user_id" for c in insp.get_columns("users")
    ):
        op.drop_column("users", "baizhi_user_id")
