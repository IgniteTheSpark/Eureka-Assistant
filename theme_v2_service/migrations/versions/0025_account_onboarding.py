"""Extend user_accounts and add EmailVerificationChallenge for email-verified auth.

Revision ID: 0024_account_onboarding
Revises: 0023_report_async_illustration
Create Date: 2026-08-13
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql

revision = "0025_account_onboarding"
down_revision = "0024_reka_reminders"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # --- user_accounts: relax email/password, add lifecycle fields ---
    op.alter_column("user_accounts", "email", existing_type=sa.String(320), nullable=True)
    op.alter_column(
        "user_accounts",
        "password_hash",
        existing_type=sa.String(255),
        nullable=True,
    )
    op.add_column("user_accounts", sa.Column("email_verified_at", mysql.DATETIME(fsp=6), nullable=True))
    op.add_column("user_accounts", sa.Column("onboarding_status", sa.String(length=24), nullable=False, server_default="pending"))
    op.add_column("user_accounts", sa.Column("terms_accepted_at", mysql.DATETIME(fsp=6), nullable=True))
    op.add_column("user_accounts", sa.Column("terms_version", sa.String(length=64), nullable=True))
    op.add_column("user_accounts", sa.Column("auth_version", sa.Integer(), nullable=False, server_default=sa.text("1")))
    op.add_column("user_accounts", sa.Column("password_updated_at", mysql.DATETIME(fsp=6), nullable=True))
    op.add_column("user_accounts", sa.Column("deleted_at", mysql.DATETIME(fsp=6), nullable=True))

    # Backfill existing accounts: verified, onboarding skipped, legacy terms.
    op.execute(
        "UPDATE user_accounts SET "
        "email_verified_at = created_at, "
        "onboarding_status = 'skipped', "
        "terms_version = 'legacy-pre-email-verification', "
        "terms_accepted_at = created_at, "
        "auth_version = 1 "
        "WHERE email_verified_at IS NULL"
    )
    op.create_check_constraint(
        "ck_user_accounts_onboarding_status",
        "user_accounts",
        "onboarding_status IN ('pending','skipped','completed')",
    )

    # --- email_verification_challenges ---
    op.create_table(
        "email_verification_challenges",
        sa.Column("id", sa.CHAR(length=36), primary_key=True),
        sa.Column("purpose", sa.String(length=24), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("code_digest", sa.String(length=128), nullable=False),
        sa.Column("request_ip_hash", sa.String(length=128), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("sent_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("expires_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("consumed_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("failed_attempts", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("locked_until", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("delivery_status", sa.String(length=24), nullable=False, server_default="pending"),
    )
    op.create_check_constraint(
        "ck_email_verification_challenges_purpose",
        "email_verification_challenges",
        "purpose IN ('register','password_reset')",
    )
    op.create_index(
        "ix_email_verification_challenges_email_purpose",
        "email_verification_challenges",
        ["email", "purpose"],
    )
    op.create_index(
        "ix_email_verification_challenges_consumed",
        "email_verification_challenges",
        ["consumed_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_email_verification_challenges_consumed", table_name="email_verification_challenges")
    op.drop_index("ix_email_verification_challenges_email_purpose", table_name="email_verification_challenges")
    op.drop_table("email_verification_challenges")
    op.drop_constraint("ck_user_accounts_onboarding_status", "user_accounts", type_="check")
    op.drop_column("user_accounts", "deleted_at")
    op.drop_column("user_accounts", "password_updated_at")
    op.drop_column("user_accounts", "auth_version")
    op.drop_column("user_accounts", "terms_version")
    op.drop_column("user_accounts", "terms_accepted_at")
    op.drop_column("user_accounts", "onboarding_status")
    op.drop_column("user_accounts", "email_verified_at")
    op.alter_column("user_accounts", "password_hash", existing_type=sa.String(255), nullable=False)
    op.alter_column("user_accounts", "email", existing_type=sa.String(320), nullable=False)
