"""
clear_data.py — 清空所有用户数据(保留 Skill 定义和 users)

用法:
  # 交互式
  cd Eureka-BrandNew/backend && python scripts/clear_data.py
  # 通过 docker(非交互)
  docker exec eureka-brandnew-backend-1 python scripts/clear_data.py --force

M3.5 更新:覆盖到所有 M2.x / M3.x 引入的表
(input_turns / messages / events / event_attendees / event_files / files / tasks)。

清空顺序遵守 FK 依赖(子表先删,父表后删):
  asset_fields  → assets       (asset_fields.asset_id ON CASCADE)
  event_files   → events       (event_files.event_id  ON CASCADE)
  event_attendees → events     (event_attendees.event_id ON CASCADE)
  messages      → sessions     (messages.session_id    ON CASCADE)
  input_turns   → sessions     (input_turns.session_id ON CASCADE)
  tasks         → sessions     (tasks.session_id       ON CASCADE)
  assets        → sessions, user_skills
  contacts      → user_skills
  events        → (independent)
  files         → (independent)
  sessions      → (last — depended on by many)

保留:
  users / global_skills / user_skills  ← 系统配置 + 账号,非用户数据
"""

import sys
import io
import argparse
from pathlib import Path

# Force UTF-8 output on Windows
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# 确保能 import 到 backend 包
sys.path.insert(0, str(Path(__file__).parent.parent))

from dotenv import load_dotenv
load_dotenv(Path(__file__).parent.parent / ".env")

from db.database import sync_engine
from sqlalchemy import text

# Order matters — child tables first, then parents. ON DELETE CASCADE handles
# most cases but being explicit makes the intent clear and survives schema
# drift where a FK might lose CASCADE.
TABLES_TO_CLEAR = [
    # leaf / join tables first
    "asset_fields",
    "event_files",
    "event_attendees",
    "messages",
    "input_turns",
    "tasks",
    # mid-level (depend on sessions / skills)
    "assets",
    # independent first-class entities
    "contacts",
    "events",
    "files",
    # last — all the FKs above point here
    "sessions",
]

PRESERVED = ["users", "global_skills", "user_skills"]


def confirm(prompt: str) -> bool:
    try:
        answer = input(f"{prompt} [yes/N]: ").strip().lower()
    except EOFError:
        return False
    return answer == "yes"


def main():
    parser = argparse.ArgumentParser(description="Wipe Eureka user data")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Skip interactive confirmation (for scripted / docker exec use)",
    )
    args = parser.parse_args()

    print("=" * 52)
    print("  ⚠️  Eureka 数据清空工具(M3.5)")
    print("=" * 52)
    print()
    print("将清空以下表的 ALL 行:")
    for t in TABLES_TO_CLEAR:
        print(f"  • {t}")
    print()
    print("保留:" + ", ".join(PRESERVED))
    print()

    if not args.force and not confirm("确认清空?输入 yes 继续"):
        print("已取消。")
        return

    # We use `session_replication_role = replica` to temporarily disable FK
    # checks for the duration of the transaction. This sidesteps cross-FK
    # cycles like sessions.subject_asset_id ↔ assets.session_id where neither
    # table can be safely emptied "first" by order alone. Requires SUPERUSER
    # — fine inside the dev docker postgres.
    with sync_engine.connect() as conn:
        conn.execute(text("BEGIN"))
        try:
            conn.execute(text("SET session_replication_role = 'replica'"))
            for table in TABLES_TO_CLEAR:
                result = conn.execute(text(f"DELETE FROM {table}"))
                print(f"  ✓ {table}: {result.rowcount} 行已删除")
            conn.execute(text("SET session_replication_role = 'origin'"))
            conn.execute(text("COMMIT"))
            print()
            print("✅ 数据清空完成。")
        except Exception as e:
            conn.execute(text("ROLLBACK"))
            print(f"\n❌ 清空失败,已回滚: {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
