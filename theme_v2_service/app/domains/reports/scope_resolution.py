from __future__ import annotations

import json
from collections.abc import Awaitable, Callable
from datetime import datetime, timezone
from typing import Any, Protocol
from zoneinfo import ZoneInfo

import litellm
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.config import get_settings
from app.db.models import Asset, Contact, Event, WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.schemas import (
    PlanBlocker,
    PublicResearchBrief,
    ReportPlanDraft,
)
from app.domains.reports.state_machine import transition_run
from app.structured_output import extract_json_object


class ScopeResolutionModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ScopeResolutionRequest(ScopeResolutionModel):
    additional_focus: str
    current_public_scope: PublicResearchBrief
    selected_evidence: list[dict[str, Any]] = Field(
        default_factory=list,
        max_length=20,
    )


class ScopeResolutionResult(ScopeResolutionModel):
    public_research_scope: PublicResearchBrief


class ScopeResolverProvider(Protocol):
    async def resolve(self, request: ScopeResolutionRequest) -> ScopeResolutionResult:
        ...


def _local_iso(value: datetime, zone: ZoneInfo) -> str:
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return aware.astimezone(zone).isoformat()


def _asset_preview(payload: dict) -> dict:
    return {
        str(key)[:100]: value
        for key, value in list(payload.items())[:8]
        if isinstance(value, (str, int, float, bool)) or value is None
    }


async def build_scope_resolution_request(
    session: AsyncSession,
    run: ReportGenerationRun,
    *,
    timezone_name: str,
) -> ScopeResolutionRequest:
    if run.plan_draft is None:
        raise ValueError("scope resolution requires a plan draft")
    draft = ReportPlanDraft.model_validate(run.plan_draft)
    references = draft.evidence_scope.references[:20]
    event_ids = [reference.id for reference in references if reference.kind == "event"]
    asset_ids = [reference.id for reference in references if reference.kind == "asset"]
    contact_ids = [
        reference.id for reference in references if reference.kind == "contact"
    ]
    events = {
        event.id: event
        for event in await session.scalars(
            select(Event).where(
                Event.user_id == run.user_id,
                Event.id.in_(event_ids or [""]),
            )
        )
    }
    assets = {
        asset.id: asset
        for asset in await session.scalars(
            select(Asset).where(
                Asset.user_id == run.user_id,
                Asset.id.in_(asset_ids or [""]),
            )
        )
    }
    contacts = {
        contact.id: contact
        for contact in await session.scalars(
            select(Contact).where(
                Contact.user_id == run.user_id,
                Contact.id.in_(contact_ids or [""]),
            )
        )
    }
    zone = ZoneInfo(timezone_name)
    selected_evidence: list[dict[str, Any]] = []
    for reference in references:
        if reference.kind == "event" and reference.id in events:
            event = events[reference.id]
            selected_evidence.append(
                {
                    "kind": "event",
                    "id": event.id,
                    "title": event.title,
                    "notes": event.description,
                    "location": event.location,
                    "local_start": _local_iso(event.start_at, zone),
                    "local_end": _local_iso(event.end_at, zone),
                    "attendees": [
                        {
                            "name": attendee.name_raw,
                            "role": attendee.role,
                            "contact_id": attendee.contact_id,
                        }
                        for attendee in event.attendees[:10]
                    ],
                }
            )
        elif reference.kind == "asset" and reference.id in assets:
            asset = assets[reference.id]
            selected_evidence.append(
                {
                    "kind": "asset",
                    "id": asset.id,
                    "skill_id": asset.user_skill_id,
                    "effective_at": (
                        _local_iso(asset.effective_at or asset.created_at, zone)
                    ),
                    "preview": _asset_preview(asset.payload_json or {}),
                }
            )
        elif reference.kind == "contact" and reference.id in contacts:
            contact = contacts[reference.id]
            selected_evidence.append(
                {
                    "kind": "contact",
                    "id": contact.id,
                    "name": contact.name,
                    "company": contact.company,
                    "title": contact.title,
                }
            )
    return ScopeResolutionRequest(
        additional_focus=draft.additional_focus,
        current_public_scope=draft.public_research_scope,
        selected_evidence=selected_evidence,
    )


def blockers_for_scope(
    scope: PublicResearchBrief,
    *,
    additional_focus: str = "",
) -> list[PlanBlocker]:
    blockers: list[PlanBlocker] = []
    enabled = [entity for entity in scope.entities if entity.enabled]
    for entity in enabled:
        if entity.kind == "person" and not (entity.qualifier or "").strip():
            blockers.append(
                PlanBlocker(
                    code="ambiguous_person",
                    entity_id=entity.id,
                    message=f"请补充 {entity.name} 的公司、职位或公开主页后再调研。",
                )
            )
    if (scope.questions or additional_focus.strip()) and not enabled:
        blockers.append(
            PlanBlocker(
                code="missing_public_entity",
                message="请至少确认一个可公开检索的对象。",
            )
        )
    return blockers


class LiteLLMScopeResolverProvider:
    def __init__(
        self,
        *,
        model: str,
        api_key: str | None,
        timeout_seconds: float,
        completion: Callable[..., Awaitable[Any]] = litellm.acompletion,
    ) -> None:
        self.model = model
        self.api_key = api_key
        self.timeout_seconds = timeout_seconds
        self._completion = completion

    async def resolve(self, request: ScopeResolutionRequest) -> ScopeResolutionResult:
        schema = ScopeResolutionResult.model_json_schema()
        response_format: dict[str, Any]
        if self.model.startswith("deepseek/"):
            response_format = {"type": "json_object"}
        else:
            response_format = {
                "type": "json_schema",
                "json_schema": {
                    "name": "report_scope_resolution",
                    "strict": True,
                    "schema": schema,
                },
            }
        messages = [
            {
                "role": "system",
                "content": (
                    "Convert the bounded user focus and selected evidence into a "
                    "minimal public research brief. Use relevant Event notes to infer "
                    "public entities and research questions. Preserve confirmed entities "
                    "unless the new scope clearly changes them. Never copy unrelated "
                    "narrative text into a query. "
                    "A person must include company, role, or public-profile qualifier. "
                    "Return JSON matching the supplied schema and do not browse the Web."
                ),
            },
            {
                "role": "user",
                "content": json.dumps(
                    {
                        "required_output_schema": schema,
                        "bounded_focus": request.additional_focus,
                        "current_public_scope": request.current_public_scope.model_dump(
                            mode="json"
                        ),
                        "selected_evidence": request.selected_evidence,
                    },
                    ensure_ascii=False,
                ),
            },
        ]
        kwargs: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "response_format": response_format,
            "timeout": self.timeout_seconds,
        }
        if self.api_key:
            kwargs["api_key"] = self.api_key
        response = await self._completion(**kwargs)
        try:
            content = response.choices[0].message.content
        except AttributeError:
            content = response["choices"][0]["message"]["content"]
        raw_result = extract_json_object(content)
        if raw_result is None:
            raise ValueError("scope resolver response does not contain one JSON object")
        return ScopeResolutionResult.model_validate(raw_result)


async def execute_scope_resolution_job(
    job: WorkflowJob,
    *,
    provider: ScopeResolverProvider,
    session_factory: async_sessionmaker[AsyncSession] = AsyncSessionFactory,
) -> bool:
    if job.run_id is None:
        return False
    expected_revision = int((job.checkpoint_json or {}).get("plan_revision", -1))
    async with session_factory() as read_session:
        run = await read_session.scalar(
            select(ReportGenerationRun).where(
                ReportGenerationRun.id == job.run_id,
                ReportGenerationRun.state == "planning",
                ReportGenerationRun.scope_resolution_job_id == job.id,
                ReportGenerationRun.plan_revision == expected_revision,
            )
        )
        if run is None or run.plan_draft is None:
            return False
        request = await build_scope_resolution_request(
            read_session,
            run,
            timezone_name=get_settings().default_user_timezone,
        )

    result = ScopeResolutionResult.model_validate(await provider.resolve(request))
    async with session_factory() as write_session:
        run = await write_session.scalar(
            select(ReportGenerationRun)
            .where(
                ReportGenerationRun.id == job.run_id,
                ReportGenerationRun.state == "planning",
                ReportGenerationRun.scope_resolution_job_id == job.id,
                ReportGenerationRun.plan_revision == expected_revision,
            )
            .with_for_update()
        )
        if run is None or run.plan_draft is None:
            return False
        draft = ReportPlanDraft.model_validate(run.plan_draft).model_copy(
            update={
                "public_research_scope": result.public_research_scope,
                "blockers": blockers_for_scope(
                    result.public_research_scope,
                    additional_focus=ReportPlanDraft.model_validate(
                        run.plan_draft
                    ).additional_focus,
                ),
            }
        )
        run.plan_draft = draft.model_dump(mode="json", by_alias=True)
        run.plan_revision = expected_revision + 1
        run.active_stage = "awaiting_selection"
        run.scope_resolution_job_id = None
        transition_run(run, "awaiting_selection")
        await write_session.commit()
    return True


def scope_resolution_handler(
    *,
    provider: ScopeResolverProvider,
    session_factory: async_sessionmaker[AsyncSession] = AsyncSessionFactory,
) -> Callable[[WorkflowJob], Awaitable[None]]:
    async def handle(job: WorkflowJob) -> None:
        await execute_scope_resolution_job(
            job,
            provider=provider,
            session_factory=session_factory,
        )

    return handle
