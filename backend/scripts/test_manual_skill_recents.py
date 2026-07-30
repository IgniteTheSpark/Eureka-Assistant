"""Live-MySQL contract for the recent manual Skill read model.

Run inside the backend container:
    python -m scripts.test_manual_skill_recents
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
import uuid

from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete

from core.security import create_token
from db.database import AsyncSessionLocal, async_engine
from db.models import (
    Asset,
    Contact,
    Event,
    GlobalSkill,
    InputTurn,
    Session,
    User,
    UserSkill,
)
from main import app


async def test_recent_manual_skills() -> None:
    suffix = uuid.uuid4().hex[:12]
    user_id = f"manual-recents-{suffix}"
    foreign_user_id = f"manual-recents-foreign-{suffix}"
    skill_names = [f"manual-recent-{index}-{suffix}" for index in range(5)]
    base = datetime(2026, 7, 30, 1, tzinfo=timezone.utc)

    try:
        async with AsyncSessionLocal() as db:
            user = User(
                id=user_id,
                email=f"{user_id}@example.com",
                password_hash="fixture",
            )
            foreign_user = User(
                id=foreign_user_id,
                email=f"{foreign_user_id}@example.com",
                password_hash="fixture",
            )
            db.add_all((user, foreign_user))

            global_skills = [
                GlobalSkill(name=name, description=name)
                for name in skill_names
            ]
            db.add_all(global_skills)
            await db.flush()

            user_skills = [
                UserSkill(
                    user_id=user_id,
                    skill_id=skill.id,
                    display_name=skill.name,
                    payload_schema={"title": {"type": "string"}},
                    render_spec={"icon": "🧪", "primary_field": "title"},
                )
                for skill in global_skills
            ]
            foreign_skill = UserSkill(
                user_id=foreign_user_id,
                skill_id=global_skills[-1].id,
                display_name=global_skills[-1].name,
                payload_schema={"title": {"type": "string"}},
                render_spec={"icon": "🧪", "primary_field": "title"},
            )
            db.add_all((*user_skills, foreign_skill))
            await db.flush()

            session = Session(
                user_id=user_id,
                session_type="flash",
                title="排除用闪念",
            )
            db.add(session)
            await db.flush()
            turn = InputTurn(
                user_id=user_id,
                session_id=session.id,
                index=1,
                source="voice",
                text="这些记录不应进入最近",
            )
            db.add(turn)
            await db.flush()

            db.add_all(
                [
                    Asset(
                        user_id=user_id,
                        user_skill_id=skill.id,
                        payload={"title": f"manual-{index}"},
                        created_at=base + timedelta(hours=index),
                    )
                    for index, skill in enumerate(user_skills)
                ]
            )
            db.add(
                Asset(
                    user_id=user_id,
                    user_skill_id=user_skills[-1].id,
                    payload={"title": "same-skill-newer"},
                    created_at=base + timedelta(hours=5),
                )
            )
            db.add_all(
                (
                    Asset(
                        user_id=user_id,
                        user_skill_id=user_skills[0].id,
                        source_input_turn_id=turn.id,
                        payload={"title": "agent-created"},
                        created_at=base + timedelta(hours=20),
                    ),
                    Asset(
                        user_id=user_id,
                        user_skill_id=user_skills[1].id,
                        source_report_id=uuid.uuid4(),
                        payload={"title": "report-created"},
                        created_at=base + timedelta(hours=21),
                    ),
                    Asset(
                        user_id=foreign_user_id,
                        user_skill_id=foreign_skill.id,
                        payload={"title": "foreign-manual"},
                        created_at=base + timedelta(hours=22),
                    ),
                )
            )
            db.add_all(
                (
                    Event(
                        user_id=user_id,
                        title="手动日程",
                        start_at=base + timedelta(days=1),
                        sync_source="manual",
                        created_at=base + timedelta(hours=6),
                    ),
                    Event(
                        user_id=user_id,
                        title="外部日程",
                        start_at=base + timedelta(days=1, hours=1),
                        sync_source="google",
                        sync_external_id=f"google-{suffix}",
                        created_at=base + timedelta(hours=23),
                    ),
                    Event(
                        user_id=user_id,
                        title="闪念日程",
                        start_at=base + timedelta(days=1, hours=2),
                        sync_source="manual",
                        source_input_turn_id=turn.id,
                        created_at=base + timedelta(hours=24),
                    ),
                )
            )
            db.add_all(
                (
                    Contact(
                        user_id=user_id,
                        name="手动联系人",
                        created_at=base + timedelta(hours=7),
                    ),
                    Contact(
                        user_id=user_id,
                        name="闪念联系人",
                        source_input_turn_id=turn.id,
                        created_at=base + timedelta(hours=25),
                    ),
                )
            )
            await db.commit()

        headers = {"Authorization": f"Bearer {create_token(user_id)}"}
        foreign_headers = {
            "Authorization": f"Bearer {create_token(foreign_user_id)}"
        }
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get(
                "/api/skills/recent-manual",
                headers=headers,
            )
            foreign_response = await client.get(
                "/api/skills/recent-manual",
                headers=foreign_headers,
            )

        assert response.status_code == 200, response.text
        assert response.json() == {
            "ok": True,
            "skill_names": [
                "contact",
                "event",
                skill_names[4],
                skill_names[3],
            ],
        }
        assert foreign_response.status_code == 200, foreign_response.text
        assert foreign_response.json() == {
            "ok": True,
            "skill_names": [skill_names[4]],
        }
    finally:
        async with AsyncSessionLocal() as db:
            user_ids = (user_id, foreign_user_id)
            await db.execute(delete(Asset).where(Asset.user_id.in_(user_ids)))
            await db.execute(delete(Event).where(Event.user_id.in_(user_ids)))
            await db.execute(delete(Contact).where(Contact.user_id.in_(user_ids)))
            await db.execute(
                delete(InputTurn).where(InputTurn.user_id.in_(user_ids))
            )
            await db.execute(delete(Session).where(Session.user_id.in_(user_ids)))
            await db.execute(
                delete(UserSkill).where(UserSkill.user_id.in_(user_ids))
            )
            await db.execute(delete(User).where(User.id.in_(user_ids)))
            await db.execute(
                delete(GlobalSkill).where(GlobalSkill.name.in_(skill_names))
            )
            await db.commit()


async def main() -> None:
    try:
        await test_recent_manual_skills()
        print(
            "PASS - recent manual Skills are ordered, capped, excluded, "
            "and user-scoped"
        )
    finally:
        await async_engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
