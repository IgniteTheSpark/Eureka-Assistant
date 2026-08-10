import asyncio

from sqlalchemy import func, select

from app.db.models import UserSkill
from app.db.session import AsyncSessionFactory
from app.domains.assets.service import (
    BASELINE_CAPTURE_SKILLS,
    ensure_capture_skills,
)


async def test_concurrent_first_use_provisions_one_baseline_row_per_skill(session):
    user_id = "concurrent-first-use-owner"

    async def provision() -> list[str]:
        async with AsyncSessionFactory() as database:
            skills = await ensure_capture_skills(database, user_id)
            await database.commit()
            return [skill.machine_name for skill in skills]

    results = await asyncio.gather(*(provision() for _ in range(6)))

    expected = [item["machine_name"] for item in BASELINE_CAPTURE_SKILLS]
    assert results == [expected] * 6
    async with AsyncSessionFactory() as database:
        count = await database.scalar(
            select(func.count()).select_from(UserSkill).where(
                UserSkill.user_id == user_id
            )
        )
        distinct_count = await database.scalar(
            select(func.count(func.distinct(UserSkill.machine_name))).where(
                UserSkill.user_id == user_id
            )
        )
    assert count == len(BASELINE_CAPTURE_SKILLS)
    assert distinct_count == count
