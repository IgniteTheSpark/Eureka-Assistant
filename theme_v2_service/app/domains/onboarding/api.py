"""Onboarding backend API (§6.1-6.10).

Typed-only for M2; the hardware capture intent endpoint is a 501 stub.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.db.session import get_session
from app.domains.assets.validation import AssetPayloadInvalid
from app.domains.onboarding.catalog import catalog_categories, get_category
from app.domains.onboarding.service import (
    OnboardingError,
    PreviewResult,
    SkillNotOwned,
    IdempotencyConflict,
    confirm_onboarding_asset,
    create_onboarding_skill,
    extract_preview,
    skip_onboarding,
)


router = APIRouter(prefix="/api/onboarding", tags=["onboarding"])


class SkillFieldsRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    category: str = Field(min_length=1, max_length=100)
    field_keys: list[str] = Field(min_length=1, max_length=30)


class SuggestFieldsRequest(BaseModel):
    category: str = Field(min_length=1, max_length=100)


class PreviewRequest(BaseModel):
    user_skill_id: str
    source_text: str = Field(min_length=1, max_length=8000)


class ConfirmRequest(BaseModel):
    skill_id: str
    payload: dict
    source_text: str | None = Field(default=None, max_length=8000)
    idempotency_key: str = Field(min_length=1, max_length=255)


class SkipRequest(BaseModel):
    idempotency_key: str = Field(min_length=1, max_length=255)


@router.get("/catalog")
async def onboarding_catalog() -> dict:
    return {
        "version": "2026-08-v1",
        "categories": catalog_categories(),
    }


@router.post("/suggest-fields")
async def suggest_fields(body: SuggestFieldsRequest) -> dict:
    # M2: curated categories return their fixed suggestions; custom categories
    # have no LLM enrichment yet, so the client falls back to manual fields.
    entry = get_category(body.category)
    if entry is not None:
        return {"fields": entry["fields"]}
    return {"fields": []}


@router.post("/skills")
async def create_skill(
    body: SkillFieldsRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        skill, created = await create_onboarding_skill(
            session,
            user_id,
            category=body.category,
            field_keys=body.field_keys,
        )
    except OnboardingError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "skill": {
            "id": skill.id,
            "machine_name": skill.machine_name,
            "display_name": skill.display_name,
            "schema": skill.schema_json,
        },
        "created": created,
    }


@router.post("/preview")
async def preview(
    body: PreviewRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        result: PreviewResult = await extract_preview(
            session,
            user_id,
            skill_id=body.user_skill_id,
            source_text=body.source_text,
        )
    except SkillNotOwned as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    return {
        "payload": result.payload,
        "field_warnings": result.field_warnings,
        "manual_fields": result.manual_fields,
    }


@router.post("/confirm")
async def confirm(
    body: ConfirmRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        result = await confirm_onboarding_asset(
            session,
            user_id,
            skill_id=body.skill_id,
            payload=body.payload,
            idempotency_key=body.idempotency_key,
        )
    except SkillNotOwned as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except AssetPayloadInvalid as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except IdempotencyConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    return {
        "ok": True,
        "asset_id": result.asset_id,
        "created": result.created,
    }


@router.post("/skip")
async def skip(
    body: SkipRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        status = await skip_onboarding(session, user_id)
    except OnboardingError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"ok": True, "onboarding_status": status}


@router.post("/capture-intent")
async def capture_intent() -> dict:
    raise HTTPException(
        status_code=501,
        detail="硬件采集意图将在后续版本提供;M2 仅支持文本输入",
    )
