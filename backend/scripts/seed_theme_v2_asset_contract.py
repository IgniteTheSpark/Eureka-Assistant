"""Reset and seed the isolated Theme V2 Asset Detail verification account.

The destructive path is deliberately hard-coded to one development account:

    python -m scripts.seed_theme_v2_asset_contract --email test@1.com --reset
"""

from __future__ import annotations

import argparse
import asyncio
from datetime import date, datetime, timedelta, timezone
import json

from sqlalchemy import delete, func, select

from core import pet as petlib
from core.demo_reset import reset_demo_workspace
from core.security import hash_password
from core.skill_schema import validate_payload_schema
from db.database import AsyncSessionLocal, async_engine
from db.models import (
    Asset,
    Contact,
    Event,
    GlobalSkill,
    InputTurn,
    Message,
    Pet,
    Session,
    User,
    UserSkill,
)
from db.seed import CHAT_STARTERS, GLOBAL_SKILLS, USER_SKILL_CONFIGS


ALLOWED_EMAIL = "test@1.com"
TEST_PASSWORD = "test123456"
_BJ = timezone(timedelta(hours=8))


def validate_seed_email(email: str) -> str:
    normalized = email.strip().lower()
    if normalized != ALLOWED_EMAIL:
        raise ValueError(
            f"refusing destructive seed for {email!r}; only {ALLOWED_EMAIL!r} is allowed"
        )
    return normalized


def build_ready_test_pet(user_id: str) -> Pet:
    """Provision deterministic app state so the contract account opens at Home."""
    skin = petlib.seeded_skin(user_id)
    return Pet(
        user_id=user_id,
        seed=user_id,
        name="Reka",
        skin=skin,
        emblem="star",
        emblem_color=petlib.default_emblem_color(skin),
        equipped={
            "head": "none",
            "leftItem": "none",
            "rightItem": "none",
            "carrier": "none",
            "aura": "soft",
        },
        unlocked={
            **petlib.empty_unlocked(),
            "skin": [skin],
            "emblem": ["star"],
        },
        milestones=petlib.empty_milestones(),
        spawned=1,
        onboarding_completed_at=datetime.now(timezone.utc),
    )


async def _resolve_test_user(email: str) -> User:
    async with AsyncSessionLocal() as db:
        async with db.begin():
            user = (
                await db.execute(
                    select(User).where(func.lower(User.email) == email)
                )
            ).scalar_one_or_none()
            if user is None:
                user = User(
                    email=email,
                    password_hash=hash_password(TEST_PASSWORD),
                )
                db.add(user)
                await db.flush()
            else:
                user.password_hash = hash_password(TEST_PASSWORD)
            user_id = user.id

    async with AsyncSessionLocal() as db:
        return (
            await db.execute(select(User).where(User.id == user_id))
        ).scalar_one()


async def _ensure_global_skill(
    db,
    *,
    name: str,
    description: str,
) -> GlobalSkill:
    skill = (
        await db.execute(select(GlobalSkill).where(GlobalSkill.name == name))
    ).scalar_one_or_none()
    if skill is None:
        skill = GlobalSkill(name=name, description=description)
        db.add(skill)
        await db.flush()
    return skill


async def _provision_user_skill(
    db,
    *,
    user_id: str,
    global_skill: GlobalSkill,
    display_name: str,
    payload_schema: dict | None,
    render_spec: dict | None,
    queryable_fields: list | None = None,
    chat_starters: list | None = None,
    position: int,
) -> UserSkill:
    skill = UserSkill(
        user_id=user_id,
        skill_id=global_skill.id,
        display_name=display_name,
        payload_schema=(
            validate_payload_schema(payload_schema)
            if payload_schema is not None
            else None
        ),
        render_spec=render_spec,
        queryable_fields=queryable_fields,
        chat_starters=chat_starters,
        position=position,
        enabled=1,
    )
    db.add(skill)
    await db.flush()
    return skill


async def seed_theme_v2_asset_contract(email: str, *, reset: bool) -> dict:
    email = validate_seed_email(email)
    if not reset:
        raise ValueError("--reset is required; seeding never merges with old fixtures")

    user = await _resolve_test_user(email)
    user_id = user.id

    async with AsyncSessionLocal() as db:
        async with db.begin():
            deleted = await reset_demo_workspace(db, user_id)
            db.add(build_ready_test_pet(user_id))
            # This fixture is also the post-migration Skill baseline. Content is
            # already gone, so replacing only this user's Skill rows is safe.
            await db.execute(delete(UserSkill).where(UserSkill.user_id == user_id))

            global_by_name: dict[str, GlobalSkill] = {}
            for config in GLOBAL_SKILLS:
                global_by_name[config["name"]] = await _ensure_global_skill(
                    db,
                    name=config["name"],
                    description=config["description"],
                )

            user_skills: dict[str, UserSkill] = {}
            position = 0
            for config in USER_SKILL_CONFIGS:
                name = config["name"]
                user_skills[name] = await _provision_user_skill(
                    db,
                    user_id=user_id,
                    global_skill=global_by_name[name],
                    display_name=config["display_name"],
                    payload_schema=config["payload_schema"],
                    render_spec=config["render_spec"],
                    queryable_fields=config["queryable_fields"],
                    chat_starters=CHAT_STARTERS.get(name),
                    position=position,
                )
                position += 1

            baby_global = await _ensure_global_skill(
                db,
                name="baby_meal",
                description="宝贝饮食",
            )
            baby_skill = await _provision_user_skill(
                db,
                user_id=user_id,
                global_skill=baby_global,
                display_name="宝贝饮食",
                payload_schema={
                    "meal": {
                        "type": "string",
                        "label": "饮食",
                        "required": True,
                        "long": False,
                    },
                    "amount": {
                        "type": "string",
                        "label": "份量",
                        "required": False,
                        "long": False,
                    },
                    "remark": {
                        "type": "string",
                        "label": "备注",
                        "required": False,
                        "long": True,
                    },
                },
                render_spec={
                    "card_layout": "stacked",
                    "icon": "🍼",
                    "accent_color": "amber",
                    "primary_field": "meal",
                    "card_display": {
                        "primary_field_id": "meal",
                        "secondary_field_ids": ["amount", "remark"],
                    },
                    "actions": ["edit", "delete"],
                },
                chat_starters=["最近吃得怎么样？", "帮我看看饮食规律"],
                position=position,
            )
            position += 1

            reading_global = await _ensure_global_skill(
                db,
                name="reading_log",
                description="阅读记录",
            )
            reading_skill = await _provision_user_skill(
                db,
                user_id=user_id,
                global_skill=reading_global,
                display_name="阅读记录",
                payload_schema={
                    "book": {
                        "type": "string",
                        "label": "书名",
                        "required": True,
                        "long": False,
                    },
                    "progress": {
                        "type": "string",
                        "label": "进度",
                        "required": False,
                        "long": False,
                    },
                    "reflection": {
                        "type": "string",
                        "label": "感想",
                        "required": False,
                        "long": True,
                    },
                },
                render_spec={
                    "card_layout": "stacked",
                    "icon": "📚",
                    "accent_color": "blue",
                    "primary_field": "book",
                    "card_display": {
                        "primary_field_id": "book",
                        "secondary_field_ids": ["progress", "reflection"],
                    },
                    "actions": ["edit", "delete"],
                },
                position=position,
            )

            flash_session = Session(
                user_id=user_id,
                session_type="flash",
                title="7月29日 闪念验证",
                date=date(2026, 7, 29),
                created_at=datetime(2026, 7, 29, 9, 0, tzinfo=_BJ),
            )
            db.add(flash_session)
            await db.flush()

            turn_texts = [
                "早上宝宝吃了一小碗南瓜泥。",
                "午饭吃了小米粥，还记录了完整的饮食观察。",
                "晚上提醒我整理今天的饮食规律。",
            ]
            turns: list[InputTurn] = []
            for index, text in enumerate(turn_texts):
                turn = InputTurn(
                    user_id=user_id,
                    session_id=flash_session.id,
                    index=index,
                    source="voice" if index < 2 else "typed",
                    text=text,
                    created_at=datetime(
                        2026,
                        7,
                        29,
                        9 + index * 3,
                        10,
                        tzinfo=_BJ,
                    ),
                )
                db.add(turn)
                await db.flush()
                turns.append(turn)
                db.add(
                    Message(
                        user_id=user_id,
                        session_id=flash_session.id,
                        input_turn_id=turn.id,
                        role="user",
                        text=text,
                        status="done",
                        created_at=turn.created_at,
                    )
                )

            markdown_overflow = """# 午餐观察

宝宝今天主动吃完了大半碗小米粥，进食节奏比昨天更稳定。

## 观察

- 主动拿勺子
- 没有出现过敏反应
- 喝水约 120 毫升

> 可以继续观察晚餐后的状态，不需要因为单次食量波动而调整计划。

| 项目 | 结果 |
| --- | --- |
| 食欲 | **良好** |
| 情绪 | 放松 |
| 过敏 | 无 |

这段文字故意超过半屏阅读阈值，用来验证真实溢出时才出现“展开全文”，并验证全屏后完整 Markdown、表格和滚动区域都可见。"""
            threshold_text = (
                "这是一段用于验证内容阈值的备注，只有达到真实排版边界时才应出现展开全文。"
                * 8
            )[:240].ljust(240, "。")

            created_10 = datetime(2026, 7, 29, 10, 0, tzinfo=_BJ)
            created_12 = datetime(2026, 7, 29, 12, 10, tzinfo=_BJ)
            created_15 = datetime(2026, 7, 29, 15, 0, tzinfo=_BJ)
            baby_short = Asset(
                user_id=user_id,
                user_skill_id=baby_skill.id,
                payload={
                    "meal": "南瓜泥",
                    "amount": "半碗",
                    "remark": "吃得很好。",
                },
                created_at=created_10,
            )
            baby_threshold = Asset(
                user_id=user_id,
                user_skill_id=baby_skill.id,
                payload={
                    "meal": "水果加餐",
                    "amount": "一小份",
                    "remark": threshold_text,
                },
                created_at=created_15,
            )
            baby_flash = Asset(
                user_id=user_id,
                user_skill_id=baby_skill.id,
                session_id=flash_session.id,
                source_input_turn_id=turns[1].id,
                payload={
                    "meal": "小米粥",
                    "amount": "大半碗",
                    "remark": markdown_overflow,
                },
                created_at=created_12,
            )
            todo_asset = Asset(
                user_id=user_id,
                user_skill_id=user_skills["todo"].id,
                payload={
                    "title": "预约儿保",
                    "content": "联系王医生确认下周的儿保时间。",
                    "due_date": "2026-07-31T10:00:00+08:00",
                    "status": "pending",
                },
                created_at=datetime(2026, 7, 29, 16, 0, tzinfo=_BJ),
            )
            notes_asset = Asset(
                user_id=user_id,
                user_skill_id=user_skills["notes"].id,
                session_id=flash_session.id,
                source_input_turn_id=turns[2].id,
                payload={
                    "title": "今天的饮食规律",
                    "content": "## 小结\n\n上午稳定，午餐食欲良好，晚餐继续观察。",
                    "tags": ["宝宝", "饮食"],
                },
                created_at=datetime(2026, 7, 29, 18, 10, tzinfo=_BJ),
            )
            reading_asset = Asset(
                user_id=user_id,
                user_skill_id=reading_skill.id,
                payload={
                    "book": "设计心理学",
                    "progress": "读到第 4 章",
                    "reflection": "反馈必须及时、清晰，并和用户刚刚的动作建立关联。",
                },
                created_at=datetime(2026, 7, 28, 21, 0, tzinfo=_BJ),
            )
            contact = Contact(
                user_id=user_id,
                name="王医生",
                company="儿童医院",
                title="儿保医生",
                phone="13800000000",
                notes=["## 备注\n\n负责儿保与营养咨询。"],
                source_input_turn_id=turns[1].id,
                created_at=datetime(2026, 7, 29, 12, 12, tzinfo=_BJ),
            )
            event = Event(
                user_id=user_id,
                title="儿保预约",
                start_at=datetime(2026, 7, 31, 10, 0, tzinfo=_BJ),
                end_at=datetime(2026, 7, 31, 10, 30, tzinfo=_BJ),
                location="儿童医院",
                description="## 准备\n\n- 疫苗本\n- 最近三天饮食记录",
                source_input_turn_id=turns[1].id,
                created_at=datetime(2026, 7, 29, 12, 15, tzinfo=_BJ),
            )
            db.add_all(
                (
                    baby_short,
                    baby_threshold,
                    baby_flash,
                    todo_asset,
                    notes_asset,
                    reading_asset,
                    contact,
                    event,
                )
            )
            await db.flush()

            ids = {
                "user_id": user_id,
                "flash_session_id": str(flash_session.id),
                "source_input_turn_id": str(turns[1].id),
                "baby_skill_id": str(baby_skill.id),
                "baby_manual_asset_id": str(baby_short.id),
                "baby_threshold_asset_id": str(baby_threshold.id),
                "baby_flash_asset_id": str(baby_flash.id),
                "todo_asset_id": str(todo_asset.id),
                "notes_asset_id": str(notes_asset.id),
                "reading_asset_id": str(reading_asset.id),
                "event_id": str(event.id),
                "contact_id": str(contact.id),
            }

    return {
        "ok": True,
        "email": email,
        "password": TEST_PASSWORD,
        "deleted": deleted,
        "ids": ids,
    }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--email", required=True)
    parser.add_argument("--reset", action="store_true")
    return parser.parse_args()


async def main() -> None:
    args = _parse_args()
    try:
        result = await seed_theme_v2_asset_contract(
            args.email,
            reset=args.reset,
        )
        print(json.dumps(result, ensure_ascii=False, indent=2))
    finally:
        await async_engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
