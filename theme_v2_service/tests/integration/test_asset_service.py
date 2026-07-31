from app.domains.assets.schemas import AssetCreate, UserSkillCreate
from app.domains.assets.service import (
    create_asset,
    create_user_skill,
    get_asset,
)


async def test_asset_is_scoped_to_owner(session):
    skill = await create_user_skill(
        session,
        "user-1",
        UserSkillCreate(
            machine_name="notes",
            display_name="笔记",
            schema={},
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
            schema={},
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
