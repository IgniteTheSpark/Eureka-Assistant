"""merge cards and expense migration heads

Revision ID: 0022_merge_cards_expense_heads
Revises: 0021_cards_and_bindings, 0021_expense_single_time
Create Date: 2026-06-12
"""

revision = "0022_merge_cards_expense_heads"
down_revision = ("0021_cards_and_bindings", "0021_expense_single_time")
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
