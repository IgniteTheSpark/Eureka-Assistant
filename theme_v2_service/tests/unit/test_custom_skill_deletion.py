from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.domains.assets.service import (
    SkillUpdateConflict,
    delete_user_skill,
    skill_deletion_impact,
)


class _Session:
    def __init__(self, *scalar_values):
        self._scalar_values = iter(scalar_values)
        self.delete = AsyncMock()
        self.flush = AsyncMock()

    async def scalar(self, _statement):
        return next(self._scalar_values)


@pytest.mark.asyncio
async def test_custom_skill_deletion_impact_counts_owned_assets():
    skill = SimpleNamespace(id="skill-1", global_skill_id=None)
    impact = await skill_deletion_impact(
        _Session(skill, 3),
        "user-1",
        "skill-1",
    )

    assert impact is not None
    assert impact.model_dump() == {"skill_id": "skill-1", "asset_count": 3}


@pytest.mark.asyncio
async def test_delete_custom_skill_returns_cascade_count_and_flushes():
    skill = SimpleNamespace(id="skill-1", global_skill_id=None)
    session = _Session(skill, 2, skill)

    result = await delete_user_skill(session, "user-1", "skill-1")

    assert result is not None
    assert result.model_dump() == {
        "skill_id": "skill-1",
        "deleted_asset_count": 2,
    }
    session.delete.assert_awaited_once_with(skill)
    session.flush.assert_awaited_once()


@pytest.mark.asyncio
async def test_system_skill_deletion_is_protected():
    skill = SimpleNamespace(id="skill-1", global_skill_id=42)

    with pytest.raises(SkillUpdateConflict) as error:
        await skill_deletion_impact(_Session(skill), "user-1", "skill-1")

    assert error.value.code == "system_skill_protected"
