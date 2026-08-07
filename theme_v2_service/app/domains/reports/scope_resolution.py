from __future__ import annotations

import json
from collections.abc import Awaitable, Callable
from typing import Any, Protocol

import litellm
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.db.models import WorkflowJob
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


class ScopeResolutionResult(ScopeResolutionModel):
    public_research_scope: PublicResearchBrief


class ScopeResolverProvider(Protocol):
    async def resolve(self, request: ScopeResolutionRequest) -> ScopeResolutionResult:
        ...


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
                    "Convert the bounded user focus into a minimal public research "
                    "brief. Preserve confirmed entities unless the user focus clearly "
                    "adds another. Never copy private narrative text into a query. "
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
        draft = ReportPlanDraft.model_validate(run.plan_draft)
        request = ScopeResolutionRequest(
            additional_focus=draft.additional_focus,
            current_public_scope=draft.public_research_scope,
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
