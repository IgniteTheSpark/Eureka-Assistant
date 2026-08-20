from __future__ import annotations

from alembic import op


revision = "0031_challenge_indexes"
down_revision = "0030_drop_cleanup_items"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index(
        "ix_email_verification_challenges_request_ip_hash",
        "email_verification_challenges",
        ["request_ip_hash"],
    )
    op.create_index(
        "ix_email_verification_challenges_sent_at",
        "email_verification_challenges",
        ["sent_at"],
    )
    op.create_index(
        "ix_email_verification_challenges_created_at",
        "email_verification_challenges",
        ["created_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_email_verification_challenges_created_at",
        table_name="email_verification_challenges",
    )
    op.drop_index(
        "ix_email_verification_challenges_sent_at",
        table_name="email_verification_challenges",
    )
    op.drop_index(
        "ix_email_verification_challenges_request_ip_hash",
        table_name="email_verification_challenges",
    )
