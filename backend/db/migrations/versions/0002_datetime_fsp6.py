"""widen all DATETIME columns to microsecond precision (fsp=6) on MySQL

MySQL DATETIME stores 0 fractional digits, so rows written within the same
second (the user + agent message of one chat turn, or N assets from a
multi-create) get an identical created_at. `ORDER BY created_at` then resolves
the tie in random (UUID/storage) order — the chat replay showed up reversed on
reload. Postgres TIMESTAMPTZ keeps microseconds by default, so this only
appeared after the Postgres -> MySQL migration.

This widens every existing DATETIME(0) column to DATETIME(6) so timestamps are
distinct again. New schemas already get fsp=6 from the TIMESTAMPTZ model
variant (db/models.py); this migration brings an already-created MySQL DB up to
the same precision without dropping data.

Revision ID: 0002_datetime_fsp6
Revises: 0001_mysql_init
Create Date: 2026-06-02
"""
import sqlalchemy as sa
from alembic import op

revision = "0002_datetime_fsp6"
down_revision = "0001_mysql_init"
branch_labels = None
depends_on = None


def _datetime_cols(bind, precision: int):
    """All DATETIME columns in the current schema at the given fractional
    precision, as (table, column, is_nullable) rows. These columns carry no DB
    server_default / ON UPDATE (defaults are Python-side), so a bare MODIFY that
    only preserves nullability is a complete column definition."""
    return bind.execute(
        sa.text(
            """
            SELECT TABLE_NAME, COLUMN_NAME, IS_NULLABLE
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND DATA_TYPE = 'datetime'
              AND DATETIME_PRECISION = :p
            """
        ),
        {"p": precision},
    ).fetchall()


def _retype(bind, target_fsp: int, from_fsp: int) -> None:
    for tbl, col, nullable in _datetime_cols(bind, from_fsp):
        null_sql = "NULL" if nullable == "YES" else "NOT NULL"
        bind.execute(
            sa.text(f"ALTER TABLE `{tbl}` MODIFY COLUMN `{col}` DATETIME({target_fsp}) {null_sql}")
        )


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "mysql":
        return  # Postgres timestamptz already has sub-second precision
    _retype(bind, target_fsp=6, from_fsp=0)


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "mysql":
        return
    _retype(bind, target_fsp=0, from_fsp=6)
