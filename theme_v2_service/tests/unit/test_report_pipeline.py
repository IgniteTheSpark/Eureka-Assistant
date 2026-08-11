from pathlib import Path

import pytest
from pydantic import ValidationError

from app.domains.reports.pipeline import (
    STAGES,
    PipelineContext,
    PipelineWriteRejected,
    _resolved_illustration_prompt,
    build_pipeline_handlers,
    execute_report_job,
)
from app.domains.reports.providers import WebSource
from app.domains.reports.templates import TemplateRegistry


TEMPLATES = Path(__file__).parents[2] / "report-templates"


def _handlers(calls: list[str], *, fail_at: str | None = None):
    handlers = {}
    for stage in STAGES:
        async def handle(context, current=stage):
            calls.append(current)
            if current == fail_at:
                raise RuntimeError(f"crash:{current}")
            return {"stage": current}

        handlers[stage] = handle
    return handlers


def _context(
    *,
    calls: list[str],
    completed: list[str] | None = None,
    fail_at: str | None = None,
    reject_after: str | None = None,
):
    checkpoints = {stage: {"stage": stage} for stage in completed or []}

    async def assert_current():
        return None

    async def save(stage, result):
        if stage == reject_after:
            raise PipelineWriteRejected("run cancelled or superseded")
        checkpoints[stage] = result

    return PipelineContext(
        run_id="run-1",
        job_id="job-1",
        execution_plan={
            "template_id": "general_period_review",
            "template_version": "1.0.0",
            "base_family": "theme_synthesis",
            "report_goal": "Summary",
            "resolved_asset_ids": [],
            "field_bindings": {},
            "time_range": None,
            "web_policy": "none",
            "illustration_policy": "none",
            "render_policy": "report_html_v1",
        },
        handlers=_handlers(calls, fail_at=fail_at),
        checkpoints=checkpoints,
        assert_current_callback=assert_current,
        save_checkpoint_callback=save,
    )


async def test_fresh_pipeline_executes_fixed_stage_order():
    calls = []
    context = _context(calls=calls)

    await execute_report_job(context)

    assert calls == list(STAGES)
    assert list(context.checkpoints) == list(STAGES)


async def test_resume_after_content_does_not_repeat_paid_stages():
    completed = ["load_evidence", "web_search", "content_generation"]
    calls = []
    context = _context(calls=calls, completed=completed)

    await execute_report_job(context)

    assert calls == ["chart_validation", "illustration", "html_render", "persist"]


async def test_crash_after_render_resumes_at_persist_only():
    calls = []
    first = _context(calls=calls, fail_at="persist")
    with pytest.raises(RuntimeError, match="crash:persist"):
        await execute_report_job(first)
    assert calls == list(STAGES)

    resumed_calls = []
    resumed = _context(
        calls=resumed_calls,
        completed=list(first.checkpoints),
    )
    await execute_report_job(resumed)

    assert resumed_calls == ["persist"]


@pytest.mark.parametrize("rejected_stage", ["load_evidence", "content_generation"])
async def test_cancelled_or_superseded_run_cannot_write_stage_result(rejected_stage):
    calls = []
    context = _context(calls=calls, reject_after=rejected_stage)

    with pytest.raises(PipelineWriteRejected):
        await execute_report_job(context)

    assert rejected_stage not in context.checkpoints
    assert calls[-1] == rejected_stage


def test_stage_order_is_stable_and_execution_plan_is_not_a_stage_input_variant():
    assert STAGES == (
        "load_evidence",
        "web_search",
        "content_generation",
        "chart_validation",
        "illustration",
        "html_render",
        "persist",
    )
    context = _context(calls=[])
    with pytest.raises(ValidationError):
        context.execution_plan.report_goal = "mutated"


def test_optional_illustration_gets_safe_fallback_when_model_omits_prompt():
    context = _context(calls=[])
    plan = context.execution_plan.model_copy(
        update={"illustration_policy": "optional"}
    )

    prompt = _resolved_illustration_prompt(
        plan=plan,
        model_prompt=None,
    )

    assert prompt is not None
    assert "editorial abstract cover" in prompt.casefold()
    assert "theme synthesis" in prompt.casefold()
    assert _resolved_illustration_prompt(
        plan=context.execution_plan,
        model_prompt=None,
    ) is None
    assert _resolved_illustration_prompt(
        plan=plan,
        model_prompt="soft blue concentric forms",
    ) == "soft blue concentric forms"


class _BoundaryWebSearch:
    def __init__(self):
        self.queries = []

    async def search(self, queries):
        self.queries = queries
        return [
            WebSource(
                title="皇家马德里一线队阵容",
                url="https://realmadrid.example/squad",
                snippet="皇家马德里公布了当前一线队阵容和球员资料。",
                accessed_at="2026-08-07T10:00:00Z",
                query_id=queries[0].id,
                entity_ids=queries[0].entity_ids,
                question_ids=queries[0].question_ids,
            )
        ]


async def test_web_stage_uses_only_frozen_public_brief_not_private_evidence():
    provider = _BoundaryWebSearch()
    handlers = build_pipeline_handlers(
        job=type("Job", (), {"id": "job-1"})(),
        generator=None,
        web_search=provider,
        illustration=None,
        registry=TemplateRegistry.load(TEMPLATES),
        storage=None,
    )
    context = PipelineContext(
        run_id="run-1",
        job_id="job-1",
        execution_plan={
            "template_id": "pre_event_briefing",
            "template_version": "1.0.0",
            "base_family": "briefing_research",
            "report_goal": "内部预算与球队建设会议",
            "resolved_asset_ids": [],
            "resolved_references": [{"kind": "event", "id": "event-1"}],
            "attention_questions": ["阵容差异"],
            "public_research_brief": {
                "entities": [
                    {
                        "id": "real-madrid",
                        "kind": "organization",
                        "name": "皇家马德里",
                    }
                ],
                "questions": ["当前一线队阵容"],
                "freshness": "current",
            },
            "field_bindings": {},
            "time_range": None,
            "web_policy": "optional",
            "illustration_policy": "none",
            "render_policy": "report_html_v1",
        },
        handlers={},
        checkpoints={
            "load_evidence": {
                "user_evidence": [
                    {
                        "kind": "event",
                        "payload": {
                            "description": "内部预算只有 800 万，不可外发"
                        },
                    }
                ]
            }
        },
        assert_current_callback=lambda: None,
        save_checkpoint_callback=lambda stage, result: None,
    )

    result = await handlers["web_search"](context)

    assert result["status"] == "succeeded"
    query_text = " ".join(query.text for query in provider.queries)
    assert "皇家马德里" in query_text
    assert "内部预算" not in query_text
    assert "800" not in query_text
