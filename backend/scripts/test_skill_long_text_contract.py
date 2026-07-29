"""Contract tests for explicit Markdown-capable Skill fields.

Run inside the backend container:
    python -m scripts.test_skill_long_text_contract
"""

from __future__ import annotations

import asyncio
import uuid

from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete, select

from agents.design_agent import validate_design_draft
from api.skills import validate_payload_schema
from core.security import create_token
from db.database import AsyncSessionLocal, async_engine
from db.models import GlobalSkill, User, UserSkill
from db.seed import USER_SKILL_CONFIGS
from main import app
from scripts.seed_theme_v2_asset_contract import (
    build_ready_test_pet,
    validate_seed_email,
)


def _expect_value_error(callback, expected_text: str) -> None:
    try:
        callback()
    except ValueError as error:
        assert expected_text in str(error), str(error)
    else:
        raise AssertionError(f"expected ValueError containing {expected_text!r}")


def test_schema_validation() -> None:
    validated = validate_payload_schema(
        {
            "remark": {
                "type": "string",
                "label": "备注",
                "required": False,
                "long": True,
            },
            "note": {
                "type": "string",
                "label": "短记",
                "required": False,
                "long": False,
            },
        }
    )
    assert validated["remark"]["long"] is True
    assert validated["remark"]["order"] == 0
    # Field names no longer guess the capability.
    assert validated["note"]["long"] is False
    assert validated["note"]["order"] == 1

    _expect_value_error(
        lambda: validate_payload_schema(
            {
                "amount": {
                    "type": "number",
                    "label": "金额",
                    "required": False,
                    "long": True,
                }
            }
        ),
        "long requires type=string",
    )
    _expect_value_error(
        lambda: validate_payload_schema(
            {
                "remark": {
                    "type": "string",
                    "label": "备注",
                    "required": False,
                }
            }
        ),
        "long must be boolean",
    )
    _expect_value_error(
        lambda: validate_payload_schema(
            {
                "remark": {
                    "type": "string",
                    "required": False,
                    "long": True,
                }
            }
        ),
        "label is required",
    )

    for config in USER_SKILL_CONFIGS:
        schema = config.get("payload_schema")
        if schema is not None:
            validate_payload_schema(schema)

    assert validate_seed_email(" TEST@1.COM ") == "test@1.com"
    _expect_value_error(
        lambda: validate_seed_email("someone@example.com"),
        "only 'test@1.com' is allowed",
    )


def test_design_draft_validation() -> None:
    draft = {
        "name": "contract_book",
        "display_name": "契约本",
        "payload_schema": {
            "body": {
                "type": "string",
                "label": "正文",
                "required": True,
                "long": True,
            }
        },
        "render_spec": {
            "card_layout": "stacked",
            "icon": "📓",
            "accent_color": "amber",
            "primary_field": "body",
        },
        "sample_payload": {"body": "# 示例"},
    }
    validated = validate_design_draft(draft)
    assert validated["payload_schema"]["body"]["long"] is True
    assert validated["payload_schema"]["body"]["order"] == 0


def test_asset_contract_seed_skips_product_onboarding() -> None:
    pet = build_ready_test_pet("theme-v2-fixture-user")
    assert pet.user_id == "theme-v2-fixture-user"
    assert pet.name == "Reka"
    assert pet.spawned == 1
    assert pet.onboarding_completed_at is not None


async def test_confirm_preserves_explicit_long() -> None:
    suffix = uuid.uuid4().hex[:12]
    user_id = f"skill-long-{suffix}"
    skill_name = f"contract-book-{suffix}"
    user_skill_id = None
    global_skill_id = None

    try:
        async with AsyncSessionLocal() as db:
            db.add(
                User(
                    id=user_id,
                    email=f"{user_id}@example.com",
                    password_hash="fixture",
                )
            )
            await db.commit()

        headers = {"Authorization": f"Bearer {create_token(user_id)}"}
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
            headers=headers,
        ) as client:
            response = await client.post(
                "/api/skills/confirm",
                json={
                    "name": skill_name,
                    "display_name": "长文契约本",
                    "payload_schema": {
                        "note": {
                            "type": "string",
                            "label": "短记",
                            "required": False,
                            "long": False,
                        },
                        "body": {
                            "type": "string",
                            "label": "正文",
                            "required": True,
                            "long": True,
                        },
                    },
                    "render_spec": {
                        "card_layout": "stacked",
                        "icon": "📓",
                        "accent_color": "amber",
                        "primary_field": "body",
                    },
                },
            )
        assert response.status_code == 200, response.text
        user_skill_id = uuid.UUID(response.json()["user_skill_id"])

        async with AsyncSessionLocal() as db:
            row = (
                await db.execute(
                    select(UserSkill, GlobalSkill)
                    .join(GlobalSkill, GlobalSkill.id == UserSkill.skill_id)
                    .where(UserSkill.id == user_skill_id)
                )
            ).first()
            assert row is not None
            user_skill, global_skill = row
            global_skill_id = global_skill.id
            assert user_skill.payload_schema["note"]["long"] is False
            assert user_skill.payload_schema["body"]["long"] is True
            assert user_skill.payload_schema["body"]["order"] == 1
    finally:
        async with AsyncSessionLocal() as db:
            if user_skill_id is not None:
                await db.execute(
                    delete(UserSkill).where(UserSkill.id == user_skill_id)
                )
            if global_skill_id is not None:
                await db.execute(
                    delete(GlobalSkill).where(GlobalSkill.id == global_skill_id)
                )
            await db.execute(delete(User).where(User.id == user_id))
            await db.commit()


async def main() -> None:
    try:
        test_schema_validation()
        test_design_draft_validation()
        test_asset_contract_seed_skips_product_onboarding()
        await test_confirm_preserves_explicit_long()
        print("PASS - Skill long text is explicit, strict, and preserved")
    finally:
        await async_engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
