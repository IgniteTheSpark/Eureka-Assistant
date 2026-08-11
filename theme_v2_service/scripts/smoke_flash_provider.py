"""Opt-in synthetic DeepSeek smoke for the Theme V2 Flash compatibility kernel."""

from __future__ import annotations

import asyncio
import logging
import os
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from sqlalchemy import delete, select

import litellm

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.config import get_settings
from app.auth import models as _auth_models  # noqa: F401
from app.db.models import (
    AgentToolExecution,
    Asset,
    AssetField,
    Contact,
    Event,
    EventAttendee,
    UserSkill,
)
from app.db.session import session_scope
from app.domains.assets.service import ensure_capture_skills
from app.domains.capture import models as _capture_models  # noqa: F401
from app.domains.capture.agent import CaptureSkill, capture_skill_from_model
from app.domains.capture.execution import FlashExecutionContext
from app.domains.capture.providers_legacy_flash import LiteLLMLegacyFlashProvider
from app.domains.devices import models as _device_models  # noqa: F401
from app.domains.notifications.models import Notification, OutboxEvent
from app.domains.reports import models as _report_models  # noqa: F401
from app.domains.sessions.models import ChatSession, InputTurn, SessionMessage
from app.domains.triggers import models as _trigger_models  # noqa: F401
from app.internal_mcp.runtime import get_internal_mcp_runtime


SMOKE_CUSTOM_SKILLS = (
    CaptureSkill(
        user_skill_id="skill-water",
        machine_name="daily_water_intake",
        display_name="喝水记录",
        description="记录用户实际喝下的白水",
        schema_definition={
            "type": "object",
            "properties": {
                "amount_ml": {
                    "type": "number",
                    "title": "饮水量",
                    "description": "实际喝下的毫升数",
                },
                "occurred_at": {
                    "type": "string",
                    "format": "date-time",
                    "title": "饮水时间",
                    "description": "实际饮水时间",
                },
            },
            "x-capture-enabled": True,
            "x-routing": {
                "intent": "记录用户已经实际喝下的白水",
                "aliases": ["喝水", "饮水", "补水"],
                "include": ["白水", "矿泉水", "纯净水", "饮用水"],
                "exclude": ["咖啡", "茶", "牛奶", "酒", "购买水", "提醒喝水"],
                "positive_examples": ["刚喝了500毫升水", "睡前灌了一瓶农夫山泉"],
                "negative_examples": ["下午喝了一杯拿铁", "买矿泉水花了6块"],
            },
        },
    ),
    CaptureSkill(
        user_skill_id="skill-running",
        machine_name="running_log",
        display_name="跑步记录",
        description="记录用户已经完成的跑步活动",
        schema_definition={
            "type": "object",
            "properties": {
                "distance_km": {
                    "type": "number",
                    "title": "距离",
                    "description": "已经完成的跑步公里数",
                },
                "pace": {
                    "type": "string",
                    "title": "配速",
                    "description": "本次跑步配速",
                },
            },
            "x-capture-enabled": True,
            "x-routing": {
                "intent": "记录已经完成的跑步、晨跑或慢跑",
                "aliases": ["跑步", "晨跑", "慢跑"],
                "include": ["已经跑完", "刚跑完", "实际跑步成绩"],
                "exclude": ["未来跑步计划", "跑步提醒", "观看跑步比赛"],
                "positive_examples": ["刚跑完五公里，配速六分半", "今早绕小区跑了三圈"],
                "negative_examples": ["明早去跑五公里", "提醒我晚上跑步"],
            },
        },
    ),
)


@dataclass(frozen=True)
class SyntheticCase:
    case_id: str
    utterance: str
    expected_types: tuple[str, ...]
    expected_operations: tuple[str, ...]


SYNTHETIC_CASES = (
    SyntheticCase("expense_only", "今天午饭花了28元", ("expense",), ("create",)),
    SyntheticCase(
        "mixed_expense_water",
        "早上吃饭花了28块，刚刚还喝了123ml的水。",
        ("expense", "daily_water_intake"),
        ("create", "create"),
    ),
    SyntheticCase(
        "running_natural",
        "刚跑完两公里，配速六分半",
        ("running_log",),
        ("create",),
    ),
    SyntheticCase(
        "knowledge_qa",
        "拿铁和美式有什么区别",
        ("qa",),
        ("answer",),
    ),
)


def _configure_safe_logging() -> None:
    """Keep the opt-in smoke output free of SDK payloads and credentials."""

    logging.basicConfig(level=logging.WARNING)
    for logger_name in ("LiteLLM", "litellm", "httpx", "httpcore", "mcp", "FastMCP"):
        logging.getLogger(logger_name).setLevel(logging.ERROR)
    litellm.suppress_debug_info = True


def _exception_chain(exc: BaseException) -> str:
    names: list[str] = []
    current: BaseException | None = exc
    while current is not None and len(names) < 5:
        names.append(type(current).__name__)
        current = current.__cause__ or current.__context__
    return ">".join(names)


async def _seed(user_id: str):
    async with session_scope() as database:
        session = ChatSession(
            user_id=user_id,
            session_type="chat",
            title="Synthetic Flash provider smoke",
        )
        database.add(session)
        await database.flush()
        turns = []
        for index in range(len(SYNTHETIC_CASES)):
            turn = InputTurn(
                user_id=user_id,
                session_id=session.id,
                turn_index=index,
                text=f"synthetic-case-{index + 1}",
                source="text",
                provenance_json={"kind": "synthetic_provider_smoke"},
            )
            database.add(turn)
            turns.append(turn)
        await database.flush()
        for definition in SMOKE_CUSTOM_SKILLS:
            database.add(
                UserSkill(
                    user_id=user_id,
                    machine_name=definition.machine_name,
                    display_name=definition.display_name,
                    description=definition.description,
                    schema_json=definition.schema_definition,
                    render_spec_json={},
                    chat_starters_json=[],
                    queryable_fields_json=[],
                    enabled=True,
                )
            )
        await ensure_capture_skills(database, user_id)
        await database.flush()
        skill_models = list(
            await database.scalars(
                select(UserSkill).where(
                    UserSkill.user_id == user_id,
                    UserSkill.enabled.is_(True),
                )
            )
        )
        skills = tuple(capture_skill_from_model(skill) for skill in skill_models)
        return session.id, tuple(turn.id for turn in turns), skills


def _reference_kinds(result) -> list[str]:
    kinds: list[str] = []
    for item in result.items:
        if item.status == "reply":
            kinds.append("reply")
        elif item.result.get("asset_id"):
            kinds.append("asset")
        elif item.result.get("event_id"):
            kinds.append("event")
        elif item.result.get("contact_id"):
            kinds.append("contact")
        elif item.status == "pending_confirmation":
            kinds.append("pending_contact")
        else:
            kinds.append("error")
    return kinds


def _entity_ids(result) -> list[str]:
    identifiers: list[str] = []
    for item in result.items:
        for key in ("asset_id", "event_id", "contact_id"):
            value = item.result.get(key)
            if value:
                identifiers.append(str(value))
    return identifiers


async def _cleanup(user_id: str) -> None:
    async with session_scope() as database:
        event_ids = list(
            await database.scalars(select(Event.id).where(Event.user_id == user_id))
        )
        if event_ids:
            await database.execute(
                delete(EventAttendee).where(EventAttendee.event_id.in_(event_ids))
            )
        await database.execute(delete(AgentToolExecution).where(AgentToolExecution.user_id == user_id))
        await database.execute(delete(AssetField).where(AssetField.user_id == user_id))
        await database.execute(delete(Asset).where(Asset.user_id == user_id))
        await database.execute(delete(Event).where(Event.user_id == user_id))
        await database.execute(delete(Contact).where(Contact.user_id == user_id))
        await database.execute(delete(Notification).where(Notification.user_id == user_id))
        await database.execute(delete(OutboxEvent).where(OutboxEvent.user_id == user_id))
        await database.execute(delete(UserSkill).where(UserSkill.user_id == user_id))
        await database.execute(delete(SessionMessage).where(SessionMessage.user_id == user_id))
        await database.execute(delete(InputTurn).where(InputTurn.user_id == user_id))
        await database.execute(delete(ChatSession).where(ChatSession.user_id == user_id))


async def main() -> int:
    _configure_safe_logging()
    model = os.environ.get("CAPTURE_AGENT_MODEL", "").strip()
    api_key = os.environ.get("CAPTURE_AGENT_API_KEY", "").strip()
    if not model or not api_key:
        print("pending: CAPTURE_AGENT_MODEL and CAPTURE_AGENT_API_KEY are required")
        return 2

    settings = get_settings()
    provider = LiteLLMLegacyFlashProvider(
        model=model,
        api_key=api_key,
        timeout_seconds=settings.capture_agent_timeout_seconds,
    )
    user_id = str(uuid.uuid4())
    all_ids: list[str] = []
    exit_code = 0
    try:
        session_id, turn_ids, skills = await _seed(user_id)
        reference = datetime.now(ZoneInfo(settings.default_user_timezone))
        for index, case in enumerate(SYNTHETIC_CASES):
            result = await provider.execute(
                context=FlashExecutionContext(
                    recording_id=f"synthetic-recording-{index + 1}",
                    user_id=user_id,
                    session_id=session_id,
                    input_turn_id=turn_ids[index],
                    transcript=case.utterance,
                    reference_datetime=reference,
                    skills=skills,
                )
            )
            statuses = [item.status for item in result.items]
            kinds = _reference_kinds(result)
            actual_types = tuple(item.intent.type for item in result.items)
            actual_operations = tuple(item.intent.operation for item in result.items)
            print(
                f"case={case.case_id} stage=complete "
                f"statuses={','.join(statuses)} references={','.join(kinds)}"
            )
            if (
                actual_types != case.expected_types
                or actual_operations != case.expected_operations
            ):
                print(
                    f"failed: case={case.case_id} expected_types={case.expected_types} "
                    f"actual_types={actual_types} "
                    f"expected_operations={case.expected_operations} "
                    f"actual_operations={actual_operations}"
                )
                exit_code = 1
                break
            if any(status == "error" for status in statuses):
                exit_code = 1
                break
            all_ids.extend(_entity_ids(result))
        if exit_code == 0 and len(all_ids) != len(set(all_ids)):
            print("failed: duplicate entity id detected")
            exit_code = 1
        if exit_code == 0:
            print("synthetic Flash provider smoke passed")
    except Exception as exc:
        print(f"failed: stage=execute exceptions={_exception_chain(exc)}")
        exit_code = 1
    finally:
        try:
            await get_internal_mcp_runtime().close()
            await _cleanup(user_id)
        except Exception as exc:
            print(f"failed: stage=cleanup exceptions={_exception_chain(exc)}")
            exit_code = 1
    return exit_code


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
