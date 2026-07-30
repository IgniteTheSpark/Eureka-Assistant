"""Live-MySQL contract for the canonical Asset Detail envelope.

Run inside the backend container:
    python -m scripts.test_asset_detail_contract
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
import uuid

from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete

from core.security import create_token
from db.database import AsyncSessionLocal, async_engine
from db.models import (
    Asset,
    Contact,
    Event,
    EventAttendee,
    GlobalSkill,
    InputTurn,
    Session,
    User,
    UserSkill,
)
from main import app


async def test_canonical_detail_envelope() -> None:
    suffix = uuid.uuid4().hex[:12]
    user_id = f"asset-detail-{suffix}"
    foreign_user_id = f"asset-detail-foreign-{suffix}"
    skill_name = f"baby-meal-{suffix}"
    ids: dict[str, uuid.UUID | int] = {}

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
            global_skill = GlobalSkill(
                name=skill_name,
                description="宝贝饮食契约",
            )
            db.add_all((user, foreign_user, global_skill))
            await db.flush()
            ids["global_skill"] = global_skill.id

            payload_schema = {
                "meal": {
                    "type": "string",
                    "label": "饮食",
                    "required": True,
                    "long": False,
                    "order": 0,
                },
                "amount": {
                    "type": "number",
                    "label": "份量",
                    "required": False,
                    "long": False,
                    "order": 1,
                },
                "remark": {
                    "type": "string",
                    "label": "备注",
                    "required": False,
                    "long": True,
                    "order": 2,
                },
            }
            render_spec = {
                "icon": "🍼",
                "card_display": {
                    "primary_field_id": "meal",
                    "secondary_field_ids": ["amount", "remark"],
                },
            }
            user_skill = UserSkill(
                user_id=user_id,
                skill_id=global_skill.id,
                display_name="宝贝饮食",
                payload_schema=payload_schema,
                render_spec=render_spec,
            )
            db.add(user_skill)
            await db.flush()
            ids["user_skill"] = user_skill.id

            session = Session(
                user_id=user_id,
                session_type="flash",
                title="7月29日 闪念",
            )
            db.add(session)
            await db.flush()
            ids["session"] = session.id

            turn = InputTurn(
                user_id=user_id,
                session_id=session.id,
                index=1,
                source="voice",
                text="宝宝晚上吃了半碗粥，状态很好",
            )
            db.add(turn)
            await db.flush()
            ids["turn"] = turn.id

            manual_asset = Asset(
                user_id=user_id,
                user_skill_id=user_skill.id,
                payload={"meal": "南瓜泥", "amount": 120, "remark": "吃得很好"},
            )
            flash_asset = Asset(
                user_id=user_id,
                user_skill_id=user_skill.id,
                session_id=session.id,
                source_input_turn_id=turn.id,
                payload={
                    "meal": "小米粥",
                    "amount": 0.5,
                    "remark": "# 晚餐\n\n- 主动吃\n- 没有过敏",
                },
            )
            event = Event(
                user_id=user_id,
                title="儿保预约",
                start_at=datetime(2026, 8, 1, 2, 0, tzinfo=timezone.utc),
                description="带上疫苗本",
                source_input_turn_id=turn.id,
            )
            contact = Contact(
                user_id=user_id,
                name="王医生",
                company="儿童医院",
                notes=["负责儿保"],
            )
            db.add_all((manual_asset, flash_asset, event, contact))
            await db.flush()
            attendee = EventAttendee(
                event_id=event.id,
                contact_id=contact.id,
                name_raw="王医生",
            )
            db.add(attendee)
            await db.flush()
            ids["attendee"] = attendee.id
            await db.commit()
            for key, entity in (
                ("manual_asset", manual_asset),
                ("flash_asset", flash_asset),
                ("event", event),
                ("contact", contact),
            ):
                await db.refresh(entity)
                ids[key] = entity.id

        headers = {"Authorization": f"Bearer {create_token(user_id)}"}
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
            headers=headers,
        ) as client:
            manual_response = await client.get(
                f"/api/asset-details/asset/{ids['manual_asset']}"
            )
            flash_response = await client.get(
                f"/api/asset-details/asset/{ids['flash_asset']}"
            )
            event_response = await client.get(
                f"/api/asset-details/event/{ids['event']}"
            )
            contact_response = await client.get(
                f"/api/asset-details/contact/{ids['contact']}"
            )
            foreign_response = await client.get(
                f"/api/asset-details/asset/{ids['manual_asset']}",
                headers={"Authorization": f"Bearer {create_token(foreign_user_id)}"},
            )
            bad_kind_response = await client.get(
                f"/api/asset-details/report/{ids['manual_asset']}"
            )

            asset_update_response = await client.put(
                f"/api/asset-details/asset/{ids['manual_asset']}",
                json={
                    "expected_version": manual_response.json()["entity"]["version"],
                    "values_patch": {
                        "remark": "# 新备注\n\n支持 **Markdown** 全文。",
                    },
                },
            )
            stale_asset_response = await client.put(
                f"/api/asset-details/asset/{ids['manual_asset']}",
                json={
                    "expected_version": manual_response.json()["entity"]["version"],
                    "values_patch": {"remark": "不应覆盖较新的内容"},
                },
            )
            event_update_response = await client.put(
                f"/api/asset-details/event/{ids['event']}",
                json={
                    "expected_version": event_response.json()["entity"]["version"],
                    "values_patch": {"description": "带上疫苗本和体检报告"},
                },
            )
            contact_update_response = await client.put(
                f"/api/asset-details/contact/{ids['contact']}",
                json={
                    "expected_version": contact_response.json()["entity"]["version"],
                    "values_patch": {"notes": "## 备注\n\n负责儿保与营养咨询"},
                },
            )
            unknown_field_response = await client.put(
                f"/api/asset-details/asset/{ids['flash_asset']}",
                json={
                    "expected_version": flash_response.json()["entity"]["version"],
                    "values_patch": {"legacy_mystery_field": "must not persist"},
                },
            )

        assert manual_response.status_code == 200, manual_response.text
        assert flash_response.status_code == 200, flash_response.text
        assert event_response.status_code == 200, event_response.text
        assert contact_response.status_code == 200, contact_response.text
        assert foreign_response.status_code == 404, foreign_response.text
        assert bad_kind_response.status_code == 400, bad_kind_response.text
        assert asset_update_response.status_code == 200, asset_update_response.text
        assert stale_asset_response.status_code == 409, stale_asset_response.text
        assert event_update_response.status_code == 200, event_update_response.text
        assert contact_update_response.status_code == 200, contact_update_response.text
        assert unknown_field_response.status_code == 400, unknown_field_response.text

        manual = manual_response.json()
        flash = flash_response.json()
        event_detail = event_response.json()
        contact_detail = contact_response.json()

        assert manual["entity"]["kind"] == "asset"
        assert manual["entity"]["id"] == str(ids["manual_asset"])
        assert manual["entity"]["version"]
        assert manual["skill"] == {
            "id": str(ids["user_skill"]),
            "machine_name": skill_name,
            "display_name": "宝贝饮食",
            "icon": "🍼",
        }
        assert [field["id"] for field in manual["fields"]] == [
            "meal",
            "amount",
            "remark",
        ]
        assert manual["fields"][2] == {
            "id": "remark",
            "label": "备注",
            "type": "string",
            "required": False,
            "long": True,
            "order": 2,
        }
        assert manual["display"] == {
            "primary_field_id": "meal",
            "secondary_field_ids": ["amount", "remark"],
        }
        assert manual["source"] == {
            "kind": "manual",
            "label": "手动创建",
            "session_id": None,
            "input_turn_id": None,
        }

        assert flash["source"] == {
            "kind": "flash",
            "label": "来自闪念",
            "session_id": str(ids["session"]),
            "input_turn_id": str(ids["turn"]),
        }
        assert flash["values"]["remark"].startswith("# 晚餐")

        assert event_detail["entity"]["kind"] == "event"
        assert event_detail["skill"]["icon"] == "📅"
        assert event_detail["source"]["kind"] == "flash"
        assert event_detail["source"]["input_turn_id"] == str(ids["turn"])
        assert any(field["id"] == "description" and field["long"] for field in event_detail["fields"])
        assert any(field["id"] == "attendees" and field["type"] == "array" for field in event_detail["fields"])
        assert event_detail["values"]["attendees"] == [
            {
                "id": str(ids["attendee"]),
                "contact_id": str(ids["contact"]),
                "name_raw": "王医生",
                "display_name": "王医生",
                "role": "attendee",
                "is_resolved": True,
                "contact_summary": "儿童医院",
            }
        ]

        assert contact_detail["entity"]["kind"] == "contact"
        assert contact_detail["skill"]["icon"] == "👤"
        assert contact_detail["source"]["kind"] == "manual"
        assert any(field["id"] == "notes" and field["long"] for field in contact_detail["fields"])
        assert contact_detail["capabilities"] == {
            "editable": True,
            "deletable": True,
        }

        updated_asset = asset_update_response.json()
        assert updated_asset["entity"]["version"] != manual["entity"]["version"]
        assert updated_asset["values"]["remark"] == "# 新备注\n\n支持 **Markdown** 全文。"

        updated_event = event_update_response.json()
        assert (
            updated_event["values"]["description"]
            == "带上疫苗本和体检报告"
        )
        assert updated_event["entity"]["version"] != event_detail["entity"]["version"]

        updated_contact = contact_update_response.json()
        assert updated_contact["values"]["notes"] == "## 备注\n\n负责儿保与营养咨询"
        assert (
            updated_contact["entity"]["version"]
            != contact_detail["entity"]["version"]
        )
    finally:
        async with AsyncSessionLocal() as db:
            for model, key in (
                (Asset, "manual_asset"),
                (Asset, "flash_asset"),
                (Event, "event"),
                (Contact, "contact"),
                (InputTurn, "turn"),
                (Session, "session"),
                (UserSkill, "user_skill"),
            ):
                entity_id = ids.get(key)
                if entity_id is not None:
                    await db.execute(delete(model).where(model.id == entity_id))
            await db.execute(delete(User).where(User.id.in_((user_id, foreign_user_id))))
            global_skill_id = ids.get("global_skill")
            if global_skill_id is not None:
                await db.execute(
                    delete(GlobalSkill).where(GlobalSkill.id == global_skill_id)
                )
            await db.commit()


async def main() -> None:
    try:
        await test_canonical_detail_envelope()
        print("PASS - canonical detail envelope is authoritative and user-scoped")
    finally:
        await async_engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
