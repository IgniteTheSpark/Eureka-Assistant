import asyncio
from dataclasses import replace
from datetime import date, datetime
from zoneinfo import ZoneInfo

from sqlalchemy import func, select

from app.db.models import (
    AgentToolExecution,
    Asset,
    AssetField,
    Contact,
    Event,
    EventAttendee,
    UserSkill,
)
from app.db.session import AsyncSessionFactory
from app.domains.sessions.models import ChatSession, InputTurn, SessionMessage
from app.internal_mcp.tools import EurekaToolContext, execute_tool
from app.internal_mcp import tools as internal_tools
from app.domains.assets import service as asset_service


async def _context(
    *,
    user_id: str = "owner",
    session_date: date | None = None,
) -> EurekaToolContext:
    async with AsyncSessionFactory() as database:
        session = ChatSession(
            user_id=user_id,
            session_type="flash" if session_date else "chat",
            session_date=session_date,
        )
        database.add(session)
        await database.flush()
        turn = InputTurn(
            user_id=user_id,
            session_id=session.id,
            turn_index=0,
            text="记录跑步五公里，并记住冯总在远山科技",
            source="typed",
        )
        database.add(turn)
        await database.commit()
        return EurekaToolContext(
            user_id=user_id,
            session_id=session.id,
            input_turn_id=turn.id,
            idempotency_prefix=f"turn:{turn.id}",
        )


async def _successive_contexts(*, user_id: str = "owner"):
    async with AsyncSessionFactory() as database:
        chat = ChatSession(user_id=user_id, session_type="chat")
        database.add(chat)
        await database.flush()
        previous = InputTurn(
            user_id=user_id,
            session_id=chat.id,
            turn_index=0,
            text="午饭花了 10 元",
            source="hardware",
        )
        current = InputTurn(
            user_id=user_id,
            session_id=chat.id,
            turn_index=1,
            text="把刚刚那个账单从 10 元改成 8 元",
            source="hardware",
        )
        database.add_all([previous, current])
        await database.flush()
        database.add(
            SessionMessage(
                session_id=chat.id,
                user_id=user_id,
                role="agent",
                status="done",
                text="已记录",
                input_turn_id=previous.id,
                cards_json=[],
            )
        )
        await database.commit()
        return (
            EurekaToolContext(
                user_id=user_id,
                session_id=chat.id,
                input_turn_id=previous.id,
                idempotency_prefix=f"turn:{previous.id}",
            ),
            EurekaToolContext(
                user_id=user_id,
                session_id=chat.id,
                input_turn_id=current.id,
                idempotency_prefix=f"turn:{current.id}",
            ),
        )


async def test_capture_target_resolver_uses_latest_completed_prior_turn(session):
    previous, current = await _successive_contexts()
    async with AsyncSessionFactory() as database:
        database.add(
            UserSkill(
                user_id="owner",
                machine_name="expense",
                display_name="消费",
                schema_json={"type": "object", "properties": {}},
            )
        )
        await database.commit()
    created = await execute_tool(
        "tool_create_asset",
        {
            "user_skill_name": "expense",
            "payload": {"title": "午饭", "amount": 10},
        },
        context=previous,
        tool_call_id="create-expense",
    )

    resolved = await execute_tool(
        "tool_resolve_capture_target",
        {
            "entity_type": "expense",
            "source_text": "把刚刚那个账单从 10 元改成 8 元",
        },
        context=current,
    )

    assert resolved["ok"] is True
    assert resolved["status"] == "resolved"
    assert resolved["entity_id"] == created["asset_id"]
    assert resolved["resolution_source"] == "prior_input_turn"

    updated = await execute_tool(
        "tool_update_asset",
        {
            "asset_id": resolved["entity_id"],
            "payload_patch": {"amount": 8},
        },
        context=current,
        tool_call_id="update-expense",
    )

    assert updated["asset_id"] == created["asset_id"]
    assert updated["payload"]["amount"] == 8
    async with AsyncSessionFactory() as database:
        assets = list(await database.scalars(select(Asset)))
    assert len(assets) == 1
    assert assets[0].payload_json["amount"] == 8


async def test_capture_target_resolver_never_guesses_between_prior_roots(session):
    previous, current = await _successive_contexts()
    async with AsyncSessionFactory() as database:
        database.add(
            UserSkill(
                user_id="owner",
                machine_name="expense",
                display_name="消费",
                schema_json={"type": "object", "properties": {}},
            )
        )
        await database.commit()
    for index, amount in enumerate((8, 20)):
        await execute_tool(
            "tool_create_asset",
            {
                "user_skill_name": "expense",
                "payload": {"title": f"消费 {index}", "amount": amount},
            },
            context=previous,
            tool_call_id=f"create-expense-{index}",
        )

    resolved = await execute_tool(
        "tool_resolve_capture_target",
        {
            "entity_type": "expense",
            "source_text": "把刚刚那个账单改一下",
        },
        context=current,
    )

    assert resolved["ok"] is True
    assert resolved["status"] == "ambiguous"
    assert resolved["entity_id"] is None
    assert len(resolved["candidates"]) == 2


async def test_capture_target_resolver_does_not_offer_unrelated_assets_for_explicit_query(
    session,
):
    context = await _context(user_id="owner")
    async with AsyncSessionFactory() as database:
        database.add(
            UserSkill(
                user_id="owner",
                machine_name="expense",
                display_name="消费",
                schema_json={"type": "object", "properties": {}},
            )
        )
        await database.commit()
    for index, amount in enumerate((8, 20)):
        await execute_tool(
            "tool_create_asset",
            {
                "user_skill_name": "expense",
                "payload": {
                    "description": f"普通消费 {index}",
                    "amount": amount,
                },
            },
            context=context,
            tool_call_id=f"create-unrelated-expense-{index}",
        )

    resolved = await execute_tool(
        "tool_resolve_capture_target",
        {
            "entity_type": "expense",
            "source_text": "删除那笔 9999 元的火箭燃料消费",
            "target_query": "9999 元火箭燃料消费",
        },
        context=context,
    )

    assert resolved["ok"] is True
    assert resolved["status"] == "not_found"
    assert resolved["entity_id"] is None
    assert resolved["candidates"] == []


async def test_contact_target_resolver_infers_unique_mentioned_name_owner_scoped(
    session,
):
    context = await _context(user_id="owner")
    async with AsyncSessionFactory() as database:
        alex = Contact(user_id="owner", name="Alex", company="Acme")
        database.add_all(
            [
                alex,
                Contact(user_id="owner", name="Kevin", company="远山科技"),
                Contact(user_id="foreign", name="Alex", company="其他公司"),
            ]
        )
        await database.commit()
        alex_id = alex.id

    resolved = await execute_tool(
        "tool_resolve_capture_target",
        {
            "entity_type": "contact",
            "source_text": "Alex 的职业改成产品经理",
            "target_query": "Alex 联系人",
        },
        context=context,
    )

    assert resolved["status"] == "resolved"
    assert resolved["entity_id"] == alex_id
    assert resolved["resolution_source"] == "exact_match"


async def test_contact_target_resolver_keeps_duplicate_names_ambiguous(session):
    context = await _context(user_id="owner")
    async with AsyncSessionFactory() as database:
        database.add_all(
            [
                Contact(user_id="owner", name="Alex", company="Acme"),
                Contact(user_id="owner", name="Alex", company="字节"),
                Contact(user_id="owner", name="Kevin"),
            ]
        )
        await database.commit()

    resolved = await execute_tool(
        "tool_resolve_capture_target",
        {
            "entity_type": "contact",
            "source_text": "Alex 的职业改成产品经理",
        },
        context=context,
    )

    assert resolved["status"] == "ambiguous"
    assert resolved["entity_id"] is None
    assert len(resolved["candidates"]) == 2


async def test_custom_asset_write_is_partial_indexed_and_idempotent(session):
    context = await _context()
    async with AsyncSessionFactory() as database:
        database.add(
            UserSkill(
                user_id="owner",
                machine_name="running_training",
                display_name="跑步训练",
                domain="运动",
                schema_json={
                    "type": "object",
                    "properties": {
                        "distance": {"type": "number"},
                        "duration": {"type": "integer"},
                        "run_date": {"type": "string", "format": "date"},
                    },
                    "required": ["distance", "duration"],
                    "additionalProperties": False,
                },
                queryable_fields_json=["distance", "duration", "run_date"],
            )
        )
        await database.commit()

    arguments = {
        "user_skill_name": "running_training",
        "payload": {"distance": 5},
        "domain": "运动",
        # A model-supplied tenant is never authoritative.
        "user_id": "victim",
    }
    first = await execute_tool(
        "tool_create_asset",
        arguments,
        context=context,
        tool_call_id="0",
    )
    replay = await execute_tool(
        "tool_create_asset",
        arguments,
        context=context,
        tool_call_id="0",
    )

    assert first == replay
    assert first["ok"] is True
    assert first["payload"] == {"distance": 5}
    assert first["source_input_turn_id"] == context.input_turn_id
    async with AsyncSessionFactory() as database:
        assets = list(await database.scalars(select(Asset)))
        fields = list(await database.scalars(select(AssetField)))
        executions = list(await database.scalars(select(AgentToolExecution)))
    assert len(assets) == 1
    assert assets[0].user_id == "owner"
    assert assets[0].session_id == context.session_id
    assert assets[0].source_input_turn_id == context.input_turn_id
    assert [(field.field_name, field.value_number) for field in fields] == [
        ("distance", 5)
    ]
    assert len(executions) == 1
    assert executions[0].status == "done"
    assert executions[0].result_json == first


async def test_custom_asset_stable_skill_id_must_match_owner_machine_name(session):
    context = await _context()
    async with AsyncSessionFactory() as database:
        skill = UserSkill(
            id="skill-running",
            user_id="owner",
            machine_name="running_training",
            display_name="跑步训练",
            schema_json={"type": "object", "properties": {}},
        )
        other = UserSkill(
            id="skill-water",
            user_id="owner",
            machine_name="water_intake",
            display_name="喝水记录",
            schema_json={"type": "object", "properties": {}},
        )
        database.add_all([skill, other])
        await database.commit()

    created = await execute_tool(
        "tool_create_asset",
        {
            "user_skill_id": "skill-running",
            "user_skill_name": "running_training",
            "payload": {"distance": 5},
        },
        context=context,
        tool_call_id="stable-custom",
    )
    mismatched = await execute_tool(
        "tool_create_asset",
        {
            "user_skill_id": "skill-water",
            "user_skill_name": "running_training",
            "payload": {"distance": 6},
        },
        context=context,
        tool_call_id="mismatch-custom",
    )

    assert created["ok"] is True
    assert created["user_skill_name"] == "running_training"
    assert mismatched == {
        "ok": False,
        "error": "custom skill id does not match machine name",
    }


async def test_capture_asset_time_is_forced_from_source_at_mcp_boundary(session):
    context = replace(
        await _context(),
        reference_datetime=datetime(
            2026, 8, 10, 16, 26, tzinfo=ZoneInfo("Asia/Shanghai")
        ),
        timezone_name="Asia/Shanghai",
    )
    async with AsyncSessionFactory() as database:
        database.add(
            UserSkill(
                user_id="owner",
                machine_name="expense",
                display_name="消费",
                schema_json={
                    "type": "object",
                    "properties": {
                        "amount": {"type": "number"},
                        "date": {"type": "string", "format": "date"},
                    },
                },
            )
        )
        await database.commit()

    created = await execute_tool(
        "tool_create_asset",
        {
            "user_skill_name": "expense",
            "payload": {"amount": 8, "date": "2099-01-01"},
            "source_text": "昨天早上买早餐花了8块",
            "period": "晚上",
            "occurred_at": "2099-01-01T23:00:00+08:00",
            "effective_at": "2099-01-01T00:00:00+08:00",
        },
        context=context,
        tool_call_id="source-time-expense",
    )

    assert created["ok"] is True
    assert created["payload"]["date"] == "2026-08-09"
    async with AsyncSessionFactory() as database:
        asset = await database.get(Asset, created["asset_id"])
    assert asset.period == "上午"
    assert asset.occurred_at is None
    assert asset.effective_at == datetime(2026, 8, 8, 16, 0)


async def test_capture_todo_deadline_is_forced_from_source_at_mcp_boundary(session):
    reference = datetime(2026, 8, 10, 19, 1, tzinfo=ZoneInfo("Asia/Shanghai"))
    context = replace(
        await _context(),
        reference_datetime=reference,
        timezone_name="Asia/Shanghai",
    )
    async with AsyncSessionFactory() as database:
        database.add(
            UserSkill(
                user_id="owner",
                machine_name="todo",
                display_name="待办",
                schema_json={"type": "object", "properties": {}},
            )
        )
        await database.commit()

    tomorrow_morning = await execute_tool(
        "tool_create_todo",
        {
            "content": "明天上午踢球",
            "source_text": "明天上午踢球",
            "due_date": "2099-01-01T23:00:00+08:00",
        },
        context=context,
        tool_call_id="todo-morning",
    )
    today_after_cutoff = await execute_tool(
        "tool_create_todo",
        {
            "content": "今天交报告",
            "source_text": "今天交报告",
            "due_date": "2099-01-01T23:00:00+08:00",
        },
        context=context,
        tool_call_id="todo-today",
    )
    exact = await execute_tool(
        "tool_create_todo",
        {
            "content": "明天晚上9点踢球",
            "source_text": "明天晚上9点踢球",
            "due_date": "",
        },
        context=context,
        tool_call_id="todo-exact",
    )

    assert tomorrow_morning["payload"]["due_date"] == (
        "2026-08-11T11:00:00+08:00"
    )
    assert today_after_cutoff["payload"]["due_date"] == (
        "2026-08-11T18:00:00+08:00"
    )
    assert exact["payload"]["due_date"] == "2026-08-11T21:00:00+08:00"


async def test_capture_event_range_is_anchored_to_source_clock(session):
    context = replace(
        await _context(),
        reference_datetime=datetime(
            2026, 8, 10, 16, 26, tzinfo=ZoneInfo("Asia/Shanghai")
        ),
        timezone_name="Asia/Shanghai",
    )

    created = await execute_tool(
        "tool_create_event",
        {
            "title": "球队建设讨论",
            "source_text": "明天下午3点到4点讨论球队建设",
            "start_at": "2099-01-01T03:00:00+08:00",
            "end_at": "2099-01-01T04:00:00+08:00",
        },
        context=context,
        tool_call_id="source-time-event",
    )

    assert created["ok"] is True
    assert created["start_at"] == "2026-08-11T07:00:00"
    assert created["end_at"] == "2026-08-11T08:00:00"


async def test_typed_todo_normalizes_once_and_generic_builtin_write_is_rejected(
    session,
    monkeypatch,
):
    context = await _context()
    async with AsyncSessionFactory() as database:
        database.add_all(
            [
                UserSkill(
                    user_id="owner",
                    machine_name="todo",
                    display_name="待办",
                    schema_json={"type": "object", "properties": {}},
                ),
                UserSkill(
                    user_id="owner",
                    machine_name="notes",
                    display_name="随记",
                    schema_json={"type": "object", "properties": {}},
                ),
            ]
        )
        await database.commit()

    calls = 0
    original = internal_tools.normalize_new_todo_payload

    def counted(*args, **kwargs):
        nonlocal calls
        calls += 1
        return original(*args, **kwargs)

    monkeypatch.setattr(internal_tools, "normalize_new_todo_payload", counted)
    monkeypatch.setattr(asset_service, "normalize_new_todo_payload", counted)

    todo = await execute_tool(
        "tool_create_todo",
        {"content": "提交评审稿", "due_date": "2026-08-11T18:00:00+08:00"},
        context=context,
        tool_call_id="typed-todo",
    )
    generic_todo = await execute_tool(
        "tool_create_asset",
        {"user_skill_name": "todo", "payload": {"title": "绕过 typed tool"}},
        context=context,
        tool_call_id="generic-todo",
    )
    generic_note = await execute_tool(
        "tool_create_asset",
        {"user_skill_name": "notes", "payload": {"content": "绕过 typed tool"}},
        context=context,
        tool_call_id="generic-note",
    )

    assert todo["ok"] is True
    assert calls == 1
    assert generic_todo == {
        "ok": False,
        "error": "use tool_create_todo for built-in todo assets",
    }
    assert generic_note == {
        "ok": False,
        "error": "use tool_create_note for built-in notes assets",
    }


async def test_asset_tools_are_owner_scoped_and_reject_foreign_provenance(session):
    owner = await _context(user_id="owner")
    foreign = await _context(user_id="foreign")
    async with AsyncSessionFactory() as database:
        skill = UserSkill(
            user_id="owner",
            machine_name="notes",
            display_name="随记",
            schema_json={"type": "object", "properties": {}},
        )
        foreign_skill = UserSkill(
            user_id="foreign",
            machine_name="notes",
            display_name="随记",
            schema_json={"type": "object", "properties": {}},
        )
        database.add_all([skill, foreign_skill])
        await database.commit()

    created = await execute_tool(
        "tool_create_note",
        {"title": "想法", "content": "做一个客户标签系统"},
        context=owner,
        tool_call_id="create",
    )
    asset_id = created["asset_id"]
    queried = await execute_tool(
        "tool_query_asset",
        {"contains": "客户标签"},
        context=foreign,
    )
    changed = await execute_tool(
        "tool_update_asset",
        {"asset_id": asset_id, "payload_patch": {"title": "偷改"}},
        context=foreign,
        tool_call_id="update",
    )
    bad_source = await execute_tool(
        "tool_create_note",
        {
            "content": "错误来源",
            "source_input_turn_id": owner.input_turn_id,
        },
        context=foreign,
        tool_call_id="foreign-source",
    )

    assert queried == {"ok": True, "assets": []}
    assert changed == {"ok": False, "error": f"asset not found: {asset_id}"}
    assert bad_source == {"ok": False, "error": "input_turn not owned by user"}
    async with AsyncSessionFactory() as database:
        count = await database.scalar(select(func.count()).select_from(Asset))
    assert count == 1


async def test_contact_and_attendee_tools_preserve_safe_exact_matching(session):
    context = await _context(session_date=date(2026, 8, 5))
    contact = await execute_tool(
        "tool_create_contact",
        {
            "name": "冯总",
            "company": "远山科技",
            "notes": "在行业会上认识",
            "socials": {"wechat": "feng_88", "unknown": "drop-me"},
        },
        context=context,
        tool_call_id="contact-create",
    )
    event = await execute_tool(
        "tool_create_event",
        {
            "title": "项目会",
            "start_at": "2026-08-06T15:00:00+08:00",
            "end_at": "2026-08-06T16:00:00+08:00",
            "location": "会议室 A",
        },
        context=context,
        tool_call_id="event-create",
    )
    attendee = await execute_tool(
        "tool_add_event_attendee",
        {"event_id": event["event_id"], "name": " 冯总 "},
        context=context,
        tool_call_id="attendee-add",
    )

    assert contact["socials"] == {"wechat": "feng_88"}
    assert attendee["attendee"]["contact_id"] == contact["contact_id"]
    assert attendee["attendee"]["display_name"] == "冯总"

    updated = await execute_tool(
        "tool_update_contact",
        {
            "contact_id": contact["contact_id"],
            "field": "notes",
            "value": "喜欢越野跑",
        },
        context=context,
        tool_call_id="contact-note",
    )
    assert updated["notes"] == ["在行业会上认识", "喜欢越野跑"]

    deleted = await execute_tool(
        "tool_delete_contact",
        {"contact_id": contact["contact_id"]},
        context=context,
        tool_call_id="contact-delete",
    )
    event_after = await execute_tool(
        "tool_get_event",
        {"event_id": event["event_id"]},
        context=context,
    )
    assert deleted["contact_action"] == "deleted"
    assert event_after["attendees"][0]["contact_id"] is None
    assert event_after["attendees"][0]["display_name"] == "冯总"
    async with AsyncSessionFactory() as database:
        assert await database.scalar(select(func.count()).select_from(Contact)) == 0
        stored_attendee = await database.scalar(select(EventAttendee))
    assert stored_attendee.name_raw == "冯总"


async def test_input_turn_tools_return_only_owned_provenance(session):
    owner = await _context(user_id="owner")
    foreign = await _context(user_id="foreign")

    owner_query = await execute_tool(
        "tool_query_input_turn",
        {"contains": "冯总", "source": "typed"},
        context=owner,
    )
    foreign_get = await execute_tool(
        "tool_get_input_turn",
        {"input_turn_id": owner.input_turn_id},
        context=foreign,
    )

    assert [row["input_turn_id"] for row in owner_query["input_turns"]] == [
        owner.input_turn_id
    ]
    assert foreign_get == {
        "ok": False,
        "error": f"input_turn not found: {owner.input_turn_id}",
    }


async def test_asset_mutation_surface_and_idempotency_conflict(session):
    context = await _context()
    async with AsyncSessionFactory() as database:
        database.add_all(
            [
                UserSkill(
                    user_id="owner",
                    machine_name="todo",
                    display_name="待办",
                    schema_json={"type": "object", "properties": {}},
                ),
                UserSkill(
                    user_id="owner",
                    machine_name="notes",
                    display_name="随记",
                    schema_json={"type": "object", "properties": {}},
                ),
            ]
        )
        await database.commit()

    todo = await execute_tool(
        "tool_create_todo",
        {
            "title": "交报告",
            "content": "把本周数据补齐",
            "due_date": "2026-08-06T15:00:00+08:00",
            "domain": "工作",
        },
        context=context,
        tool_call_id="create-todo",
    )
    conflict = await execute_tool(
        "tool_create_todo",
        {"title": "另一个待办", "content": "不应创建"},
        context=context,
        tool_call_id="create-todo",
    )
    note = await execute_tool(
        "tool_create_note",
        {"title": "复盘", "content": "今天完成了五公里", "domain": "运动"},
        context=context,
        tool_call_id="create-note",
    )
    updated = await execute_tool(
        "tool_update_asset",
        {
            "asset_id": note["asset_id"],
            "payload_patch": '{"content":"今天完成了六公里"}',
        },
        context=context,
        tool_call_id="update-note",
    )
    digest = await execute_tool("tool_query_digest", {}, context=context)
    deleted = await execute_tool(
        "tool_delete_asset",
        {"asset_id": note["asset_id"]},
        context=context,
        tool_call_id="delete-note",
    )
    replay = await execute_tool(
        "tool_delete_asset",
        {"asset_id": note["asset_id"]},
        context=context,
        tool_call_id="delete-note",
    )

    assert todo["payload"]["status"] == "pending"
    assert todo["payload"]["due_date"] == "2026-08-06T15:00:00+08:00"
    assert conflict == {
        "ok": False,
        "error": "idempotency key already used with different arguments",
    }
    assert updated["payload"]["content"] == "今天完成了六公里"
    assert digest["counts"] == {"todo": 1, "notes": 1}
    assert deleted == replay
    assert deleted["status"] == "deleted"


async def test_event_and_attendee_mutation_surface_is_owner_scoped(session):
    owner = await _context(user_id="owner")
    foreign = await _context(user_id="foreign")
    contact = await execute_tool(
        "tool_create_contact",
        {"name": "冯总", "company": "远山科技"},
        context=owner,
        tool_call_id="contact",
    )
    event = await execute_tool(
        "tool_create_event",
        {
            "title": "项目会",
            "start_at": "2026-08-06T15:00:00+08:00",
            "end_at": "2026-08-06T16:00:00+08:00",
        },
        context=owner,
        tool_call_id="event",
    )
    rejected_contact = await execute_tool(
        "tool_add_event_attendee",
        {"event_id": event["event_id"], "contact_id": contact["contact_id"]},
        context=foreign,
        tool_call_id="foreign-attendee",
    )
    attendee = await execute_tool(
        "tool_add_event_attendee",
        {"event_id": event["event_id"], "name": "待确认的人"},
        context=owner,
        tool_call_id="add-attendee",
    )
    bound = await execute_tool(
        "tool_update_event_attendee",
        {
            "event_id": event["event_id"],
            "attendee_id": attendee["attendee_id"],
            "contact_id": contact["contact_id"],
        },
        context=owner,
        tool_call_id="bind-attendee",
    )
    changed = await execute_tool(
        "tool_update_event",
        {
            "event_id": event["event_id"],
            "patch": '{"location":"会议室 B","status":"done"}',
        },
        context=owner,
        tool_call_id="update-event",
    )
    removed = await execute_tool(
        "tool_delete_event_attendee",
        {
            "event_id": event["event_id"],
            "attendee_id": attendee["attendee_id"],
        },
        context=owner,
        tool_call_id="delete-attendee",
    )
    queried = await execute_tool(
        "tool_query_event",
        {"contains": "项目", "status": "done"},
        context=owner,
    )
    foreign_delete = await execute_tool(
        "tool_delete_event",
        {"event_id": event["event_id"]},
        context=foreign,
        tool_call_id="foreign-delete",
    )
    owner_delete = await execute_tool(
        "tool_delete_event",
        {"event_id": event["event_id"]},
        context=owner,
        tool_call_id="owner-delete",
    )

    assert rejected_contact == {
        "ok": False,
        "error": f"event not found: {event['event_id']}",
    }
    assert bound["attendee"]["contact_id"] == contact["contact_id"]
    assert changed["location"] == "会议室 B"
    assert changed["status"] == "done"
    assert removed["status"] == "deleted"
    assert [item["event_id"] for item in queried["events"]] == [event["event_id"]]
    assert foreign_delete == {
        "ok": False,
        "error": f"event not found: {event['event_id']}",
    }
    assert owner_delete["status"] == "deleted"
    async with AsyncSessionFactory() as database:
        assert await database.scalar(select(func.count()).select_from(Event)) == 0


async def test_mutation_rejects_unowned_trusted_runtime_context(session):
    owner = await _context(user_id="owner")
    foreign_context = EurekaToolContext(
        user_id="foreign",
        session_id=owner.session_id,
        input_turn_id=owner.input_turn_id,
        idempotency_prefix="forged",
    )

    result = await execute_tool(
        "tool_delete_asset",
        {"asset_id": "missing"},
        context=foreign_context,
        tool_call_id="forged",
    )

    assert result == {"ok": False, "error": "session not owned by user"}
    async with AsyncSessionFactory() as database:
        executions = list(await database.scalars(select(AgentToolExecution)))
    assert executions == []


async def test_concurrent_mutation_retry_replays_one_committed_result(session):
    context = await _context()
    async with AsyncSessionFactory() as database:
        database.add(
            UserSkill(
                user_id="owner",
                machine_name="notes",
                display_name="随记",
                schema_json={"type": "object", "properties": {}},
            )
        )
        await database.commit()

    first, second = await asyncio.gather(
        execute_tool(
            "tool_create_note",
            {"content": "只应创建一次"},
            context=context,
            tool_call_id="same-call",
        ),
        execute_tool(
            "tool_create_note",
            {"content": "只应创建一次"},
            context=context,
            tool_call_id="same-call",
        ),
    )

    assert first == second
    async with AsyncSessionFactory() as database:
        asset_count = await database.scalar(select(func.count()).select_from(Asset))
        execution_count = await database.scalar(
            select(func.count()).select_from(AgentToolExecution)
        )
    assert asset_count == 1
    assert execution_count == 1
