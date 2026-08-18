import asyncio

import pytest

from app.db.session import AsyncSessionFactory
from app.domains.assets.schemas import AssetCreate, UserSkillCreate, UserSkillUpdate
from app.domains.assets.service import (
    SkillUpdateConflict,
    create_asset,
    create_user_skill,
    get_asset,
    list_assets,
    update_user_skill,
)


async def test_asset_is_scoped_to_owner(session):
    skill = await create_user_skill(
        session,
        "user-1",
        UserSkillCreate(
            machine_name="notes",
            display_name="笔记",
            schema={
                "type": "object",
                "properties": {"content": {"type": "string"}},
                "required": ["content"],
                "additionalProperties": False,
            },
        ),
    )
    asset = await create_asset(
        session,
        "user-1",
        AssetCreate(
            user_skill_id=skill.id,
            payload={"content": "x"},
        ),
    )
    await session.commit()

    assert await get_asset(session, "user-1", asset.id) is not None
    assert await get_asset(session, "user-2", asset.id) is None


async def test_create_asset_does_not_commit(session):
    skill = await create_user_skill(
        session,
        "user-1",
        UserSkillCreate(
            machine_name="notes",
            display_name="笔记",
            schema={
                "type": "object",
                "properties": {"content": {"type": "string"}},
                "required": ["content"],
                "additionalProperties": False,
            },
        ),
    )
    asset = await create_asset(
        session,
        "user-1",
        AssetCreate(
            user_skill_id=skill.id,
            payload={"content": "rollback-me"},
        ),
    )

    await session.rollback()

    assert await get_asset(session, "user-1", asset.id) is None


async def test_migrated_contact_assets_are_archived_from_interactive_asset_reads(
    session,
):
    skill = await create_user_skill(
        session,
        "user-1",
        UserSkillCreate(
            machine_name="contact",
            display_name="联系人",
            schema={
                "type": "object",
                "properties": {"name": {"type": "string"}},
                "required": ["name"],
            },
        ),
    )
    asset = await create_asset(
        session,
        "user-1",
        AssetCreate(user_skill_id=skill.id, payload={"name": "Alex"}),
    )
    asset.migrated_contact_id = "contact-alex"
    await session.commit()

    assert await get_asset(session, "user-1", asset.id) is None
    assert await list_assets(session, "user-1") == []


async def test_concurrent_skill_updates_serialize_revision_check(session):
    skill = await create_user_skill(
        session,
        "user-1",
        UserSkillCreate(
            machine_name="training_atomic",
            display_name="训练",
            schema={"note": {"type": "string"}},
        ),
    )
    await session.commit()
    expected_updated_at = skill.updated_at

    first_session = AsyncSessionFactory()
    try:
        first = await update_user_skill(
            first_session,
            "user-1",
            skill.id,
            UserSkillUpdate(
                display_name="第一位编辑者",
                expected_updated_at=expected_updated_at,
            ),
        )
        assert first is not None

        async def update_second():
            async with AsyncSessionFactory() as second_session:
                return await update_user_skill(
                    second_session,
                    "user-1",
                    skill.id,
                    UserSkillUpdate(
                        display_name="第二位编辑者",
                        expected_updated_at=expected_updated_at,
                    ),
                )

        second_task = asyncio.create_task(update_second())
        await asyncio.sleep(0.1)
        await first_session.commit()

        with pytest.raises(SkillUpdateConflict) as error:
            await asyncio.wait_for(second_task, timeout=2)
        assert error.value.code == "stale_skill_revision"
    finally:
        await first_session.rollback()
        await first_session.close()
