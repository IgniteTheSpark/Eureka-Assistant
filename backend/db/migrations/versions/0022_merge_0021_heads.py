"""merge 两个并行的 0021 head:cards_and_bindings(jigong · BLE 录音卡)+
expense_single_time(记账去掉冗余 at)。

两人各自从 0020_chat_starters 分叉加了一个 0021 → Alembic 出现两个 head,
`alembic upgrade head` 会报 multiple heads。此迁移把两支并回单线,无 schema 改动。

Revision ID: 0022_merge_0021_heads
Revises: 0021_cards_and_bindings, 0021_expense_single_time
Create Date: 2026-06-12
"""

revision = "0022_merge_0021_heads"
down_revision = ("0021_cards_and_bindings", "0021_expense_single_time")
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
