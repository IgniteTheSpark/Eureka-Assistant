"""Shared Flash text processing service.

Both the old text endpoint and the new audio-file ASR path ultimately hand a
piece of text to the same Flash Pipeline. Keeping that flow here prevents the
file ingest endpoint from re-implementing session/input_turn/message semantics.
"""
import datetime
import logging
import time
import uuid
from typing import Optional

from fastapi import HTTPException
from sqlalchemy import select

from agents.flash_pipeline import run_flash_pipeline
from core.notifications import create_notification, publish_event
from core.session_service import (
    create_input_turn_for_message,
    persist_agent_message,
    persist_user_message,
)
from db.database import AsyncSessionLocal
from db.models import Session as DBSession

logger = logging.getLogger("flash_file")
LOG_TAG = "[FlashFile]"


async def get_or_create_capture_session_today(db, user_id: str, source: str) -> DBSession:
    """
    Capture sessions aggregate by natural day + modality.

    Hardware voice capture enters a `flash` session; typed/manual capture enters
    a `manual` session. This preserves the current /api/flash behavior.
    """
    is_voice = source == "voice"
    stype = "flash" if is_voice else "manual"
    today = datetime.date.today()
    result = await db.execute(
        select(DBSession).where(
            DBSession.user_id == user_id,
            DBSession.session_type == stype,
            DBSession.date == today,
        )
    )
    sess = result.scalar_one_or_none()
    if sess:
        return sess

    sess = DBSession(
        user_id=user_id,
        session_type=stype,
        title=f"{today.month}月{today.day}日 " + ("闪念" if is_voice else "记录"),
        date=today,
    )
    db.add(sess)
    await db.commit()
    await db.refresh(sess)
    return sess


async def process_flash_text(
    user_id: str,
    text: str,
    *,
    source: str = "voice",
    file_id: Optional[str] = None,
    recording_id: Optional[str] = None,
    asr_provider: Optional[str] = None,
    language: Optional[str] = None,
    segments: Optional[list] = None,
    session_id: str = "",
) -> dict:
    """Create input_turn, run the Flash Pipeline, persist chat-like messages.

    Returns a JSON-serializable dict compatible with the existing FlashResponse.
    `recording_id` is included only as provenance for callers; table updates are
    owned by the file queue.
    """
    t0 = time.monotonic()
    _now_local = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8)))
    today_str = (
        f"{_now_local.isoformat(timespec='minutes')}"
        f"(周{'一二三四五六日'[_now_local.weekday()]})"
    )
    input_source = source if source in {"voice", "typed", "imported"} else "voice"
    logger.info(
        "%s process_flash_text start user=%s recording=%s source=%s file_id=%s "
        "provider=%s text_len=%s segments=%s session=%s",
        LOG_TAG,
        user_id,
        recording_id or "-",
        input_source,
        file_id or "-",
        asr_provider or "-",
        len(text or ""),
        len(segments or []),
        session_id or "-",
    )

    try:
        async with AsyncSessionLocal() as db:
            if session_id:
                result = await db.execute(
                    select(DBSession).where(
                        DBSession.id == uuid.UUID(session_id),
                        DBSession.user_id == user_id,
                    )
                )
                session = result.scalar_one_or_none()
                if not session:
                    raise HTTPException(status_code=404, detail="session not found")
            else:
                session = await get_or_create_capture_session_today(db, user_id, input_source)

            session_id = str(session.id)
            turn = await create_input_turn_for_message(
                db,
                session_id,
                user_id,
                text,
                source=input_source,
                file_id=file_id,
                segments=segments,
                asr_provider=asr_provider,
                language=language,
            )
            input_turn_id = str(turn.id)
            await persist_user_message(db, session_id, user_id, text)
            logger.info(
                "%s process_flash_text input persisted user=%s recording=%s session=%s input_turn=%s",
                LOG_TAG,
                user_id,
                recording_id or "-",
                session_id,
                input_turn_id,
            )
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("%s process_flash_text input persist failed recording=%s", LOG_TAG, recording_id or "-")
        return {
            "ok": False,
            "session_id": "",
            "input_turn_id": "",
            "recording_id": recording_id or "",
            "error": str(e)[:200],
            "elapsed_ms": int((time.monotonic() - t0) * 1000),
        }

    publish_event(user_id, "capture", session_id=session_id)
    logger.info("%s process_flash_text capture published user=%s recording=%s session=%s", LOG_TAG, user_id, recording_id or "-", session_id)

    try:
        logger.info("%s process_flash_text pipeline start recording=%s input_turn=%s", LOG_TAG, recording_id or "-", input_turn_id)
        result = await run_flash_pipeline(
            user_text=text,
            session_id=session_id,
            input_turn_id=input_turn_id,
            today_str=today_str,
            user_id=user_id,
        )
    except Exception as e:
        logger.exception("%s process_flash_text pipeline exception recording=%s", LOG_TAG, recording_id or "-")
        return {
            "ok": False,
            "session_id": session_id,
            "input_turn_id": input_turn_id,
            "recording_id": recording_id or "",
            "error": str(e)[:200],
            "elapsed_ms": int((time.monotonic() - t0) * 1000),
        }

    reply = result.get("reply", "")
    summary = result.get("summary", "")
    cards = result.get("cards", [])
    elapsed_ms = int((time.monotonic() - t0) * 1000)
    agent_text_for_history = reply or summary

    try:
        async with AsyncSessionLocal() as db:
            await persist_agent_message(
                db,
                session_id,
                user_id,
                agent_text=agent_text_for_history,
                cards=cards,
                elapsed_ms=elapsed_ms,
            )
            logger.info(
                "%s process_flash_text agent message persisted recording=%s session=%s cards=%s elapsed_ms=%s",
                LOG_TAG,
                recording_id or "-",
                session_id,
                len(cards),
                elapsed_ms,
            )
    except Exception:
        logger.exception("%s process_flash_text persist agent message failed recording=%s", LOG_TAG, recording_id or "-")
        pass

    derived = result.get("derived_assets", []) or cards
    if result.get("ok", True) and derived:
        await create_notification(
            user_id=user_id,
            type="flash_done",
            title="闪念已整理",
            body="",
            link=session_id,
        )
        logger.info("%s process_flash_text notification created recording=%s derived=%s", LOG_TAG, recording_id or "-", len(derived))
    logger.info(
        "%s process_flash_text done recording=%s ok=%s session=%s input_turn=%s cards=%s elapsed_ms=%s",
        LOG_TAG,
        recording_id or "-",
        result.get("ok", True),
        session_id,
        input_turn_id,
        len(cards),
        elapsed_ms,
    )

    return {
        "ok": result.get("ok", True),
        "session_id": session_id,
        "input_turn_id": input_turn_id,
        "recording_id": recording_id or "",
        "reply": reply,
        "summary": summary,
        "cards": cards,
        "derived_assets": result.get("derived_assets", []),
        "has_pending": result.get("has_pending", False),
        "elapsed_ms": elapsed_ms,
    }
